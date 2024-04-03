# data "google_compute_zones" "available" {
#   project = var.config.project
#   region  = var.config.region
# }

locals {
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
  source     = "terraform-google-modules/service-accounts/google"
  version    = "~>4.2.1"
  for_each   = local.servers
  project_id = var.config.project
  names      = ["${var.app.name}-${each.value.name}-sa"]

  org_id          = local.sa_conf["org_id"]
  project_roles   = each.value.additional_service_account_roles != null ? concat(each.value.additional_service_account_roles, local.default_roles) : local.default_roles
  grant_xpn_roles = false
}

locals {
  servers = {
    for idx, instance_config in var.server : instance_config.name => instance_config
  }
}

module "compute_instance" {
  source              = "terraform-google-modules/vm/google//modules/compute_instance"
  version             = "~>9.0.0"
  for_each            = local.servers
  region              = var.config.region
  hostname            = "${var.app.env}-${each.key}"
  instance_template   = module.instance_template[each.key].self_link
  num_instances       = each.value.instance_config.count
  deletion_protection = false
  subnetwork          = var.network.subnet
  subnetwork_project  = var.network.project
}


module "instance_template" {
  source             = "terraform-google-modules/vm/google//modules/instance_template"
  version            = "~>9.0.0"
  for_each           = local.servers
  region             = var.config.region
  project_id         = var.config.project
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



#########################PRIVATE KEY PART####################

resource "tls_private_key" "private_key_pair" {
  for_each  = var.app.os == "linux" ? local.servers : {}
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "ssh_key" {
  for_each        = var.app.os == "linux" ? local.servers : {}
  content         = tls_private_key.private_key_pair[each.key].private_key_pem
  filename        = "${path.module}/${each.value.name}_ssh_key.pem"
  file_permission = "0600"
}

######################FIREWALL RULE PART######################

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


locals {

  server_list = [for server_name, vm_info in module.compute_instance : server_name]

  all_vms = concat([
    for server_name, vm_info in module.compute_instance :
    [
      for instance_details in vm_info.instances_details :
      [server_name, instance_details.network_interface[0].network_ip, instance_details.id]
    ]
  ]...)

  # dynatrace_instances = [for server_data in local.all_vms : server_data[2] if server_data[0] == "dynatrace"]


  # lb_servers = {
  #   for server_name, vm_info in module.compute_instance :
  #   server_name => [for instance_details in vm_info.instances_details : instance_details.id]
  #   # if contains(local.servers_require_lb, server_name)
  #   if contains(["dynatrace"], server_name)

  # }
}

# if server_name == "dynatrace"

locals {
  # instances = [
  #   for server_name, vm_info in module.compute_instance :
  #   flatten(
  #     [
  #       for instance_details in vm_info.instances_details :
  #       [server_name, vm_i.network_interface[0].network_ip]
  #   ]...)
  # ]


  # instances_hosts = [
  #   for server_name, vm_info in module.compute_instance :
  #   flatten(
  #     [
  #       for instance_details in vm_info.instances_details :
  #       [server_name, instance_details.hostname]
  #   ]...)
  # ]


  # server_key_mapping = {
  #   for server_name, vm_info in module.compute_instance :
  #   server_name => [
  #     for instance_details in vm_info.instances_details :
  #     instance_details.network_interface[0].network_ip
  #   ]
  # }

}

# resource "null_resource" "ansible_instances_connection_check" {
#   # depends_on = [module.compute_instance]
#   count = length(local.instances)
#   provisioner "remote-exec" {
#     inline = ["echo 'Wait until SSH is ready'"]
#     connection {
#       type        = "ssh"
#       user        = "centos"
#       private_key = tls_private_key.private_key_pair[local.instances[count.index][0]].private_key_pem
#       host        = local.instances[count.index][1]
#     }
#   }
# }

# resource "ansible_host" "hosts" {
#   count  = length(local.instances)
#   name   = local.instances[count.index][1]
#   groups = [local.instances[count.index][0]]
#   variables = {
#     ansible_user                 = "centos",
#     ansible_ssh_private_key_file = "${local.instances[count.index][0]}_ssh_key.pem",
#     ansible_python_interpreter   = "/usr/bin/python3"
#   }
# }

# resource "ansible_group" "group" {
#   for_each = local.server_key_mapping
#   name     = each.key
# }

# output "groups" {
#   value = ansible_group.group
# }

# output "hosts" {
#   value = ansible_host.hosts
# }


# resource "null_resource" "ansible_inventory_creator" {
#   triggers = {
#     always_run = "${timestamp()}"
#   }

#   provisioner "local-exec" {
#     command = <<EOT
# cat <<EOF > inventory.ini
# ${join("\n", [for server_name, data in module.compute_instance : "[${server_name}]\n${join("\n", [for instance in data.instances_details : "${instance.name} ansible_host=${instance.network_interface[0].network_ip}"])}"])}
# EOF
# EOT
#   }
# }


# resource "ansible_playbook" "playbook" {
#   # depends_on = [ansible_group.group,
#   # ansible_host.hosts]
#   depends_on = [null_resource.ansible_instances_connection_check,
#   null_resource.ansible_inventory_creator]
#   # for_each   = local.server_key_mapping
#   count      = length(local.instances)
#   playbook   = "${local.instances[count.index][0]}-playbook.yml"
#   name       = local.instances[count.index][1]
#   groups     = [local.instances[count.index][0]]
#   verbosity  = 6
#   replayable = true
#   extra_vars = {
#     inventory = "inventory.ini"
#   }
# }



# output "instances" {
#   value = local.instances
# }

# output "instances_name" {
#   value = local.instances_hosts
# }

# output "server_key_mapping" {
#   value = local.server_key_mapping
# }


################|^OP-IN-THE-CHAT^|#########################
# resource "ansible_playbook" "playbook" {
#   # count     = length(local.instances)
#   playbook  = "${local.instances[0][0]}-playbook.yml"
#   name      = local.instances[0][1]
#   verbosity = 6
# }

####################################





###########################ANSIBLE PART NULL RESOURCE WORKING############################

# resource "null_resource" "ansible_inventory_creator" {
#   triggers = {
#     always_run = "${timestamp()}"
#   }

#   provisioner "local-exec" {
#     command = <<EOT
# cat <<EOF > inventory.ini
# ${join("\n", [for server_name, data in module.compute_instance : "[${server_name}]\n${join("\n", [for instance in data.instances_details : "${instance.name} ansible_host=${instance.network_interface[0].network_ip}"])}"])}
# EOF
# EOT
#   }
# }

# resource "null_resource" "ansible_instances_connection_check" {
#   count = length(local.all_vms)
#   provisioner "remote-exec" {
#     inline = ["echo 'Wait until SSH is ready'"]
#     connection {
#       type        = "ssh"
#       user        = "centos"
#       private_key = tls_private_key.private_key_pair[local.all_vms[count.index][0]].private_key_pem
#       host        = local.all_vms[count.index][1]
#     }
#   }
# }

# resource "null_resource" "ansible_playbook_runner" {
#   triggers = {
#     always_run = "${timestamp()}"
#   }
#   depends_on = [null_resource.ansible_instances_connection_check]
#   count      = length(local.server_list)
#   provisioner "local-exec" {
#     command = "ansible-playbook  -i inventory.ini -u centos --private-key ${local.server_list[count.index]}_ssh_key.pem ${local.server_list[count.index]}-playbook.yml"
#   }
# }

######################PASSTHROUGH LOAD BALANCER PART FOR DYNATRACE###########################

# resource "google_compute_instance_group" "default" {
#   project  = var.config.project
#   zone     = "us-west1-a"
#   for_each = local.lb_servers
#   name     = "${each.key}-tcp-passthrough-umg"
#   # instances = [for server_data in local.all_vms : server_data[2] if server_data[0] == "dynatrace"]
#   instances = each.value
#   named_port {
#     name = "https"
#     port = "443"
#   }
# }


# resource "google_compute_region_health_check" "default" {
#   for_each           = local.lb_servers
#   project            = var.config.project
#   region             = var.config.region
#   name               = "${each.key}-tcp-passthrough-health-check"
#   timeout_sec        = 1
#   check_interval_sec = 5

#   tcp_health_check {
#     port = "443"
#   }
# }

# resource "google_compute_region_backend_service" "default" {
#   project               = var.config.project
#   region                = var.config.region
#   for_each              = local.lb_servers
#   name                  = "${each.key}-tcp-passthrough-xlb-backend-service"
#   protocol              = "TCP"
#   port_name             = "tcp"
#   load_balancing_scheme = "EXTERNAL"
#   timeout_sec           = 10
#   health_checks         = [google_compute_region_health_check.default[each.key].id]
#   backend {
#     group = google_compute_instance_group.default[each.key].id
#     # balancing_mode = "UTILIZATION"
#     balancing_mode = "CONNECTION"
#     # max_utilization = 0.70
#     # capacity_scaler = 1.0
#   }
# }



# resource "google_compute_forwarding_rule" "default" {
#   project               = var.config.project
#   region                = var.config.region
#   for_each              = local.lb_servers
#   name                  = "${each.key}-tcp-passthrouugh-xlb-forwarding-rule"
#   backend_service       = google_compute_region_backend_service.default[each.key].id
#   ip_protocol           = "TCP"
#   load_balancing_scheme = "EXTERNAL"
#   port_range            = "443"
#   # all_ports = true
#   # allow_global_access = true
#   # all_ports             = true
#   # allow_global_access   = true
#   # network               = google_compute_network.ilb_network.id
#   # subnetwork            = google_compute_subnetwork.ilb_subnet.id
# }




####################ABOVE IS THE WORKING BLOCK##################


####################TARGET GROUP FORWARDING RULE################

# lb_servers = {
#   for server_name, vm_info in module.compute_instance :
#   server_name => [for instance_details in vm_info.instances_details : instance_details.id]
#   # if contains(local.servers_require_lb, server_name)
#   if contains(["dynatrace"], server_name)

# }

locals {
  lb_servers = {
    for server_name, vm_info in module.compute_instance :
    server_name => [for instance_details in vm_info.instances_details : instance_details.id]
    if contains(["dynatrace"], server_name)
  }


  # lb_instances = [
  #   for server_name, vm_info in module.compute_instance :
  #   [for instance_details in vm_info.instances_details : instance_details.id]
  #   if server_name == "dynatrace"
  # ]


  lb_instances = [
    for vm_info in module.compute_instance["dynatrace"].instances_details : [vm_info.name, vm_info.id]
  ]


  # instances = [
  #   for server_name, vm_info in module.compute_instance :
  #   flatten(
  #     [
  #       for instance_details in vm_info.instances_details :
  #       [server_name, instance_details.network_interface[0].network_ip]
  #   ]...)
  # ]

}

output "lb_jugad" {
  value = local.lb_instances
}

# output "lb_instances" {
#   value = local.lb_instances
# }
resource "google_compute_address" "default" {
  count   = length(local.lb_instances)
  name    = "${local.lb_instances[count.index][0]}-external-ip"
  project = var.config.project
  region  = var.config.region
}

resource "google_compute_target_instance" "default" {

  count = length(local.lb_instances)
  # for_each = local.lb_servers
  project = var.config.project
  zone    = "us-west1-a"
  # name     = "${each.key}tcp-target-instance"
  name     = "${local.lb_instances[count.index][0]}-tcp-target-instance"
  instance = local.lb_instances[count.index][1]
  # instance = each.value[0].instances_details[0].id

}

resource "google_compute_forwarding_rule" "default" {
  count = length(local.lb_instances)
  # for_each              = local.lb_servers
  project               = var.config.project
  ip_protocol           = "TCP"
  name                  = "${local.lb_instances[count.index][0]}-tcp-fwd-rule"
  region                = var.config.region
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  target                = google_compute_target_instance.default[count.index].self_link
  ip_address            = google_compute_address.default[count.index].address
}


output "ip_addresses" {
  value = google_compute_address.default
}
output "target" {
  value = google_compute_target_instance.default
}


output "frd_rule" {
  value = google_compute_forwarding_rule.default
}

output "compute-op" {
  value = module.compute_instance["dynatrace"].instances_details[0].hostname
}
#####################PROXY LOAD BALANCER#####################


# locals {

#   lb_servers = {
#     for server_name, vm_info in module.compute_instance :
#     server_name => [for instance_details in vm_info.instances_details : instance_details.id]
#     # if contains(local.servers_require_lb, server_name)
#     if contains(["dynatrace"], server_name)

#   }
# }



# resource "google_compute_global_forwarding_rule" "default" {
#   project               = var.config.project
#   for_each              = local.lb_servers
#   name                  = "${each.key}-tcp-proxy-xlb-forwarding-rule"
#   ip_protocol           = "TCP"
#   load_balancing_scheme = "EXTERNAL"
#   port_range            = "80"
#   target                = google_compute_target_tcp_proxy.default[each.key].id
#   # ip_address            = module.global_external_address[count.index].addresses
# }

# resource "google_compute_target_tcp_proxy" "default" {
#   for_each        = local.lb_servers
#   project         = var.config.project
#   name            = "${each.key}-test-proxy-health-check"
#   backend_service = google_compute_backend_service.default[each.key].id
# }

# resource "google_compute_backend_service" "default" {
#   project               = var.config.project
#   for_each              = local.lb_servers
#   name                  = "${each.key}-tcp-proxy-xlb-backend-service"
#   protocol              = "TCP"
#   port_name             = "tcp"
#   load_balancing_scheme = "EXTERNAL"
#   timeout_sec           = 10
#   health_checks         = [google_compute_health_check.default[each.key].id]
#   backend {
#     group           = google_compute_instance_group.default[each.key].id
#     balancing_mode  = "UTILIZATION"
#     max_utilization = 0.70
#     capacity_scaler = 1.0
#   }
# }


# resource "google_compute_health_check" "default" {
#   project            = var.config.project
#   for_each           = local.lb_servers
#   name               = "${each.key}-tcp-proxy-health-check"
#   timeout_sec        = 1
#   check_interval_sec = 5

#   tcp_health_check {
#     port = "443"
#   }
# }

# resource "google_compute_instance_group" "default" {
#   project   = var.config.project
#   zone      = "us-west1-a"
#   for_each  = local.lb_servers
#   name      = "${each.key}-tcp-proxy-umg"
#   instances = each.value
#   named_port {
#     name = "https"
#     port = "443"
#   }
# }



# resource "google_compute_instance_group" "default" {
#   project  = var.config.project
#   zone     = "us-west1-a"
#   for_each = local.lb_servers
#   name     = "${each.key}-tcp-passthrough-umg"
#   # instances = [for server_data in local.all_vms : server_data[2] if server_data[0] == "dynatrace"]
#   instances = each.value
#   named_port {
#     name = "https"
#     port = "443"
#   }
# }


# resource "google_compute_region_health_check" "default" {
#   for_each           = local.lb_servers
#   project            = var.config.project
#   region             = var.config.region
#   name               = "${each.key}-tcp-passthrough-health-check"
#   timeout_sec        = 1
#   check_interval_sec = 5

#   tcp_health_check {
#     port = "443"
#   }
# }

# resource "google_compute_region_backend_service" "default" {
#   project               = var.config.project
#   region                = var.config.region
#   for_each              = local.lb_servers
#   name                  = "${each.key}-tcp-passthrough-xlb-backend-service"
#   protocol              = "TCP"
#   port_name             = "tcp"
#   load_balancing_scheme = "EXTERNAL"
#   timeout_sec           = 10
#   health_checks         = [google_compute_region_health_check.default[each.key].id]
#   backend {
#     group = google_compute_instance_group.default[each.key].id
#     # balancing_mode = "UTILIZATION"
#     balancing_mode = "CONNECTION"
#     # max_utilization = 0.70
#     # capacity_scaler = 1.0
#   }
# }



# resource "google_compute_forwarding_rule" "default" {
#   project               = var.config.project
#   region                = var.config.region
#   for_each              = local.lb_servers
#   name                  = "${each.key}-tcp-passthrouugh-xlb-forwarding-rule"
#   backend_service       = google_compute_region_backend_service.default[each.key].id
#   ip_protocol           = "TCP"
#   load_balancing_scheme = "EXTERNAL"
#   port_range            = "443"
#   # all_ports = true
#   # allow_global_access = true
#   # all_ports             = true
#   # allow_global_access   = true
#   # network               = google_compute_network.ilb_network.id
#   # subnetwork            = google_compute_subnetwork.ilb_subnet.id
# }



# for_each   = local.server_key_mapping


# locals {
#   server_key_mapping = {
#     for server_name, vm_info in module.compute_instance :
#     server_name => [
#       for instance_details in vm_info.instances_details :
#       instance_details.network_interface[0].network_ip
#     ]
#   }

# }

# resource "null_resource" "ansible_instances_connection_check" {
#   triggers = {
#     always_run = "${timestamp()}"
#   }
#   for_each = local.server_key_mapping
#   provisioner "remote-exec" {
#     inline = ["echo 'Wait until SSH is ready'"]
#     connection {
#       type        = "ssh"
#       user        = "centos"
#       private_key = tls_private_key.private_key_pair[each.key].private_key_pem
#       host        = each.value[0]
#     }
#   }
# }



####$$$$$ ABOVE IS WORKING $$$$$####



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
