data "google_compute_zones" "available" {
  project = var.config.project
  region  = var.config.region
}

locals {
  #   instance_template = [for i in module.instance_template : i.self_link]

  default_roles = [
    "${var.config.project}=>roles/monitoring.metricWriter",
    "${var.config.project}=>roles/logging.logWriter",
    "${var.config.project}=>roles/iap.tunnelResourceAccessor",
    "${var.config.project}=>roles/compute.instanceAdmin.v1"
  ]
  sa_conf = {
    org_id = var.config.org_id
  }
  gce_user = var.app.os == "windows" ? "Admin" : "centos"

}
module "service_accounts" {
  source  = "terraform-google-modules/service-accounts/google"
  version = "~>4.2.1"
  #   count           = length(var.server)
  for_each   = local.servers
  project_id = var.config.project
  #   names           = ["${var.app.name}-${var.server[count.index].name}-sa"]
  names = ["${var.app.name}-${each.value.name}-sa"]

  org_id          = local.sa_conf["org_id"]
  project_roles   = each.value.additional_service_account_roles != null ? concat(each.value.additional_service_account_roles, local.default_roles) : local.default_roles
  grant_xpn_roles = false
}

locals {
  servers = {
    for idx, instance_config in var.server : instance_config.name => instance_config
  }
  #   zone_counter = 0
}
# # Use a null_resource to manage the zone counter
# resource "null_resource" "zone_counter" {
#   triggers = {
#     always_run = "${timestamp()}"
#   }

#   provisioner "local-exec" {
#     command = "echo $((local.zone_counter += 1)) > zone_counter.txt"
#   }
# }

module "compute_instance" {
  source  = "terraform-google-modules/vm/google//modules/compute_instance"
  version = "~>9.0.0"
  #   count   = length(module.instance_template)
  for_each = local.servers
  region   = var.config.region
  #   zone                = var.zone == null ? data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names)] : var.zone
  #   zone = data.google_compute_zones.available.names[0]
  # zone = var.zone == null ? data.google_compute_zones.available.names[local.zone_counter % length(data.google_compute_zones.available.names)] : var.zone
  #   zone = var.zone == null ? data.google_compute_zones.available.names[local.zone_counter % length(data.google_compute_zones.available.names)] : var.zone
  #   hostname = "${var.app.env}-${var.server[count.index].name}"
  hostname = "${var.app.env}-${each.key}"
  #   instance_template   = tostring(local.instance_template[count.index])
  instance_template   = module.instance_template[each.key].self_link
  num_instances       = each.value.instance_config.count
  deletion_protection = false
  subnetwork          = var.network.subnet
  subnetwork_project  = var.network.project
}


module "instance_template" {
  source  = "terraform-google-modules/vm/google//modules/instance_template"
  version = "~>9.0.0"
  #   count              = length(var.server)
  for_each   = local.servers
  region     = var.config.region
  project_id = var.config.project
  #   tags               = var.server[count.index].tags
  tags               = each.value.tags
  source_image       = each.value.instance_config.source_image
  disk_size_gb       = each.value.instance_config.root_disk_size
  machine_type       = each.value.instance_config.machine_type
  subnetwork         = var.network.subnet
  subnetwork_project = var.network.project
  labels             = merge(var.app.labels, each.value.labels)

  metadata = each.value.instance_config.os_type == "linux" ? {
    sshKeys                = each.value.instance_config.os_type == "linux" ? "${each.value.instance_config.gce_user}:${tls_private_key.private_key_pair[each.key].public_key_openssh}" : ""
    block-project-ssh-keys = true
  } : {}


  service_account = {
    email  = module.service_accounts[each.key].email
    scopes = ["cloud-platform"]
  }

  additional_disks = [
    {
      disk_name    = each.value.instance_config.additional_disk_name
      device_name  = each.value.instance_config.additional_disk_name
      disk_size_gb = each.value.instance_config.additional_disk_size
      disk_type    = each.value.instance_config.additional_disk_type
      auto_delete  = true
      boot         = false
      disk_labels  = {}
    }
  ]
}



############# Private Key ##############

resource "tls_private_key" "private_key_pair" {
  #   count     = var.app.os == "linux" ? length(var.server) : 0
  for_each  = var.app.os == "linux" ? local.servers : {}
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "ssh_key" {
  #   count           = var.app.os == "linux" ? length(var.server) : 0
  for_each        = var.app.os == "linux" ? local.servers : {}
  content         = tls_private_key.private_key_pair[each.key].private_key_pem
  filename        = "${path.module}/${each.value.name}_ssh_key.pem"
  file_permission = "0600"
}

locals {
  default_allow_cidr = ["192.168.5.0/24"]
}

resource "google_compute_firewall" "rule" {
  for_each      = var.app.os == "linux" ? local.servers : {}
  name          = "${var.app.env}-${each.key}-ssh"
  network       = var.network.vpc
  project       = var.config.project
  source_ranges = each.value.additional_ssh_allow_cidr != null ? concat(each.value.additional_ssh_allow_cidr, local.default_allow_cidr) : local.default_allow_cidr
  target_tags   = each.value.tags
  direction     = "INGRESS"
  priority      = 1
  allow {
    protocol = "tcp"
    ports = [
      "22"
    ]
  }
}


resource "null_resource" "ansible_inventory_creator" {
  provisioner "local-exec" {
    command = <<EOT
cat <<EOF > inventory.ini
${join("\n", [for server_name, data in module.compute_instance : "[${server_name}]\n${join("\n", [for instance in data.instances_details : "${instance.name} ansible_host=${instance.network_interface[0].network_ip}"])}"])}
EOF
EOT
  }
}

locals {
  server_key_mapping = merge([
    for idx, instance in module.compute_instance :
    {
      for instance_details in instance.instances_details :
      instance_details.network_interface[0].network_ip => idx
    }
  ]...)
}


resource "null_resource" "ansible_provisioner" {
  for_each = local.server_key_mapping
  provisioner "remote-exec" {
    inline = ["echo 'Wait until SSH is ready'"]
    connection {
      type        = "ssh"
      user        = "centos"
      private_key = tls_private_key.private_key_pair[each.value].private_key_pem
      host        = each.key
    }
  }
}



# locals {
#   server_key_mapping = {
#     for idx, instance in module.compute_instance :
#     idx => {
#       for instance_details in instance.instances_details :
#       idx => instance_details.network_interface[0].network_ip
#     }
#   }
# }

# output "server_key_mapping" {
#   value = local.server_key_mapping
# }


# resource "null_resource" "ansible_provisioner" {

#   provisioner "remote-exec" {
#     inline = ["echo 'Wait until SSH is ready'"]

#     connection {
#       type = "ssh"
#       user = local.ssh_user
#       private_key = tls_private_key.private_key_pair["dynatrace"].private_key_pem
#       host        = local.ip_addresses.server-dynatrace[0]
#     }
#   }
#   # provisioner "local-exec" {
#   #   command = "ansible-inventory -i ${local.ip_addresses.server-dynatrace[0]} --list"
#   #   # command = "ansible-playbook  -i ${aws_instance.nginx.public_ip}, --private-key ${local.private_key_path} nginx.yaml"
#   # }

# }


# # Ansible Code Block 

# locals {
#   ssh_user         = "centos"

# ip_addresses = {
#   for idx, instance in module.compute_instance :
#   "server-${idx}" => [
#     for instance_details in instance.instances_details :
#     instance_details.network_interface[0].network_ip
#   ]
# }
# }

#################
##Map for inventory file
# locals {
#   ssh_user = "centos"

#   ip_addresses = {
#     for idx, instance in module.compute_instance :
#     "${idx}" => {
#       for instance_details in instance.instances_details :
#       instance_details.name => instance_details.network_interface[0].network_ip
#     }
#   }
# }
# #################

# output "testing" {
#   value = local.ip_addresses
# }



# --------------------safe------------------------
# locals {
#   ssh_user = "centos"

#   ip_addresses = {
#     for idx, instance in module.compute_instance :
#     "${idx}" => {
#       for instance_details in instance.instances_details :
#       instance_details.name => instance_details.network_interface[0].network_ip
#     }
#   }
# }

# resource "null_resource" "ansible_inventory" {
#   provisioner "local-exec" {
#     command = <<EOT
# cat <<EOF > inventory.ini
# ${join("\n", [for key, val in local.ip_addresses : "[${key}]\n${join("\n", [for sn, ip in val : "${sn} ansible_host=${ip}"])}"])}
# EOF
# EOT
#   }
# }
# --------------------safe------------------------




#######
# resource "null_resource" "ansible_provisioner" {

#   provisioner "remote-exec" {
#     inline = ["echo 'Wait until SSH is ready'"]

#     connection {
#       type = "ssh"
#       user = local.ssh_user
#       private_key = tls_private_key.private_key_pair["dynatrace"].private_key_pem
#       host        = local.ip_addresses.server-dynatrace[0]
#     }
#   }
#   # provisioner "local-exec" {
#   #   command = "ansible-inventory -i ${local.ip_addresses.server-dynatrace[0]} --list"
#   #   # command = "ansible-playbook  -i ${aws_instance.nginx.public_ip}, --private-key ${local.private_key_path} nginx.yaml"
#   # }

# }
########

#Ansible using resources:

#   ip_addresses = {
#     for idx, instance in module.compute_instance :
#     "server-${idx}" => [
#       for instance_details in instance.instances_details :
#       instance_details.network_interface[0].network_ip
#     ]
#   }

# locals {
#   ssh_user         = "ankitraut0987"
#   private_key_path = "dynatrace_ssh_key.pem"

#   ip_addresses = {
#     for idx, instance in module.compute_instance :
#     "server-${idx}" => [
#       for instance_details in instance.instances_details :
#       instance_details.network_interface[0].network_ip
#     ]
#   }

# }

# resource "ansible_host" "dynatrace" {
#   name   = "server-dynatrace"
#   groups = [ansible_group.server_group.name]

#   variables = {
#     yaml_list = jsonencode(local.ip_addresses.server-dynatrace[0])
#   }
# }

# resource "ansible_group" "server_group" {
#   name     = "server_group"
#   children = ["server-dynatrace"]
# }

# resource "ansible_playbook" "playbook" {
#   playbook = "playbook.yml"
#   name     = "apache installation playbook"
#   # replayable = true
#   groups    = [ansible_group.server_group.name]
#   verbosity = 6
# }




#NOT USEFULL

# ---------------------------------------------------
# module "instance_template" {
#   source             = "terraform-google-modules/vm/google//modules/instance_template"
#   version            = "~>9.0.0"
#   count              = length(var.server)
#   region             = var.config.region
#   project_id         = var.config.project
#   tags               = var.server[count.index].tags
#   source_image       = var.server[count.index].instance_config.source_image
#   disk_size_gb       = var.server[count.index].instance_config.root_disk_size
#   machine_type       = var.server[count.index].instance_config.machine_type
#   subnetwork         = var.network.subnet
#   subnetwork_project = var.network.project
#   labels             = merge(var.app.labels, var.server[count.index].labels)

#   metadata = var.server[count.index].instance_config.os_type == "linux" ? {
#     sshKeys                = var.server[count.index].instance_config.os_type == "linux" ? "${var.server[count.index].instance_config.gce_user}:${tls_private_key.private_key_pair[count.index].public_key_openssh}" : ""
#     block-project-ssh-keys = true
#   } : {}

#   service_account = {
#     email  = module.service_accounts[count.index].email
#     scopes = ["cloud-platform"]
#   }
#   additional_disks = [
#     {
#       disk_name    = var.server[count.index].instance_config.additional_disk_name
#       device_name  = var.server[count.index].instance_config.additional_disk_name
#       disk_size_gb = var.server[count.index].instance_config.additional_disk_size
#       disk_type    = var.server[count.index].instance_config.additional_disk_type
#       auto_delete  = true
#       boot         = false
#       disk_labels  = {}
#     }
#   ]
# }

############# Private Key ##############

# resource "tls_private_key" "private_key_pair" {
#   #   count     = var.app.os == "linux" ? length(var.server) : 0
#   for_each  = var.app.os == "linux" ? local.servers : {}
#   algorithm = "RSA"
#   rsa_bits  = 4096
# }

# resource "local_sensitive_file" "ssh_key" {
#   #   count           = var.app.os == "linux" ? length(var.server) : 0
#   for_each        = var.app.os == "linux" ? local.servers : {}
#   content         = tls_private_key.private_key_pair[each.key].private_key_pem
#   filename        = "${path.module}/${each.value.name}_ssh_key.pem"
#   file_permission = "0600"
# }

