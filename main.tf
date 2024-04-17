# # data "google_compute_zones" "available" {
# #   project = var.config.project
# #   region  = var.config.region
# # }

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
output "servers" {
  value = local.servers
}

module "compute_instance" {
  source            = "terraform-google-modules/vm/google//modules/compute_instance"
  version           = "~>9.0.0"
  for_each          = local.servers
  region            = var.config.region
  hostname          = "${var.app.env}-${each.key}"
  instance_template = module.instance_template[each.key].self_link
  # num_instances       = each.value.instance_config.count
  deletion_protection = false
  subnetwork          = var.network.subnet
  subnetwork_project  = var.network.project

  # provisioner "local-exec" {
  #   command = "ssh ${each.value.instance_config.gce_user}@${("${var.app.env}-${each.key}-001")} && git clone ${each.instance_config.link}"
  # }
}

# data "external" "execute_script" {
#   depends_on = [module.compute_instance]

#   program = ["bash", "path/to/your/external_script.sh"]

#   query = {
#   instance_data = jsonencode([
#     for instance_key, instance_value in local.servers : [      
#       module.compute_instance[instance_key].instances_details[0].network_interface[0].network_ip,
#       local.servers[instance_key].instance_config.gce_user,
#       local.servers[instance_key].instance_config.link
#     ]
#   ])
#   }
# }

data "external" "execute_script" {
  depends_on = [module.compute_instance]

  program = ["bash", "external_script.sh"]

  query = {
    instance_data = jsonencode(flatten([
      for instance_key, instance_value in local.servers : {
        ip   = module.compute_instance[instance_key].instances_details[0].network_interface[0].network_ip,
        user = local.servers[instance_key].instance_config.gce_user,
        link = local.servers[instance_key].instance_config.link,
      }
    ]))
  }
}

locals {
  instance_data = [
    for instance_key, instance_value in local.servers : [
      # module.compute_instance[instance_key].instances_details.network_interface[0].network_ip,
      module.compute_instance[instance_key].instances_details[0].network_interface[0].network_ip,
      local.servers[instance_key].instance_config.gce_user,
      local.servers[instance_key].instance_config.link
    ]
  ]
}

output "instance_data" {
  value = local.instance_data

}

# output "sample" {
#   value = module.compute_instance["dt"].instances_details[0].network_interface[0].network_ip
# }

# locals {
#   servers = {
#     for idx, instance_config in var.server : instance_config.name => instance_config
#   }
# }

# resource "google_compute_instance" "compute_instances" {
#   count = length(local.servers)

#   name         = "${var.app.env}-${local.servers[count.index].name}-001"
#   machine_type = local.servers[count.index].machine_type
#   zone         = local.servers[count.index].zone

#   metadata_startup_script = "git clone ${local.servers[count.index].link}"

#   provisioner "remote-exec" {
#     inline = [
#       "chmod +x /tmp/startup-script.sh",
#       "sudo /tmp/startup-script.sh",
#     ]

#     connection {
#       type        = "ssh"
#       user        = local.servers[count.index].gce_user
#       host        = self.network_interface[0].access_config[0].nat_ip
#       private_key = file(var.ssh_private_key_path)
#     }
#   }
# }


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

  # metadata = each.value.instance_config.os_type == "linux" ? {
  #   sshKeys                = each.value.instance_config.os_type == "linux" ? "${each.value.instance_config.gce_user}:${tls_private_key.private_key_pair[each.key].public_key_openssh}" : ""
  #   block-project-ssh-keys = true
  # } : {}


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

module "firewall_rules" {
  source       = "terraform-google-modules/network/google//modules/firewall-rules"
  project_id   = var.config.project
  network_name = "default" #module.vpc.network_name
  rules = [{
    name        = "allow-iap-traffic"
    description = null
    direction   = "INGRESS"
    priority    = 1000
    ranges      = ["130.211.0.0/22","35.191.0.0/16"]
    # target_tags = each.value.tags
    allow = [{
      protocol = "TCP"
      ports    = ["80"]
    }]
    deny = []
    log_config = {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }]
}

# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# resource "google_compute_firewall" "example" {
#   name          = "from-cloudflare"
#   network       = "default"
#   project       = var.config.project
#   source_ranges = data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks

#   allow {
#     ports    = ["443"]
#     protocol = "tcp"
#   }
# }

# resource "google_compute_firewall" "rule" {
#   for_each      = { for rule in local.firewall_rules_flat : "${rule.server_name}-${rule.rule_name}" => rule }
#   name          = each.value.rule_name
#   network       = var.network.vpc
#   source_ranges = concat(each.value.source_ranges, data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks)
#   target_tags   = each.value.tags
#   direction     = try(each.value.direction, "INGRESS")
#   priority      = try(each.value.priority, 1000)
#   allow {
#     protocol = each.value.protocol
#     ports    = each.value.ports
#   }
# }

# module firewall me [parameter **rule**] ka data-structure:
# rules = [
#   {
#     name                   = string
#     description            = optional(string, null)
#     direction              = optional(string, "INGRESS")
#     disabled               = optional(bool, null)
#     priority               = optional(number, null)
#     ranges                 = optional(list(string), [])
#     source_tags            = optional(list(string))
#     source_service_accounts = optional(list(string))
#     target_tags            = optional(list(string))
#     target_service_accounts = optional(list(string))
#     allow                  = optional(list(object({
#       protocol = string
#       ports    = optional(list(string))
#     })), [])
#     deny                   = optional(list(object({
#       protocol = string
#       ports    = optional(list(string))
#     })), [])
#     log_config             = optional(object({
#       metadata = string
#     }))
#   }
# ]


# XXXXXXXXX---cloudflare ip---XXXXXXXXXXXX

# data "cloudflare_ip_ranges" "cloudflare" {}

# data "http" "example" {
#   url = "https://www.cloudflare.com/ips-v4"

#   # Optional request headers
#   request_headers = {
#     Accept = "application/json"
#   }
# }


# locals {
#   firewall_rules_flat = flatten([
#     for server in var.server : [
#       for rule in server.instance_config.firewall_rules : {
#         server_name   = server.name, # This attribute must exist in every object
#         rule_name     = rule.name,
#         direction     = rule.direction,
#         ports         = rule.ports,
#         source_ranges = rule.source_ranges
#         protocol      = rule.protocol
#         tags          = server.tags
#       }
#     ]
#   ])


# }


# locals {
#   map_loops = {
#     for value in flatten([
#       for server in var.server : [
#         for rule in server.instance_config.firewall_rules : {
#           server_name   = server.name, # This attribute must exist in every object
#           rule_name     = rule.name,
#           direction     = rule.direction,
#           ports         = rule.ports,
#           source_ranges = rule.source_ranges
#           protocol      = rule.protocol
#           tags          = server.tags
#         }
#       ]
#     ]) : "${value.server_name}-${value.rule_name}" => value
#   }

#   # ip_cidrs = split("\n", data.http.example.response_body)

# }

# module "firewall_rules" {
#   source       = "terraform-google-modules/network/google//modules/firewall-rules"
#   project_id   = var.config.project
#   network_name = "default" #module.vpc.network_name
#   for_each     = { for rule in local.firewall_rules_flat : "${rule.server_name}-${rule.rule_name}" => rule }
#   # for_each = local.map_loops
#   rules = [{
#     name        = each.value.rule_name
#     description = null
#     direction   = try(each.value.direction, "INGRESS")
#     priority    = try(each.value.priority, 1000)
#     ranges      = each.value.source_ranges
#     # source_tags             = null
#     # source_service_accounts = null
#     target_tags = each.value.tags
#     # target_service_accounts = null
#     allow = [{
#       protocol = each.value.protocol
#       ports    = each.value.ports
#     }]
#     deny = []
#     log_config = {
#       metadata = "INCLUDE_ALL_METADATA"
#     }
#   }]
# }



# data "http" "example" {
#   url = "https://www.cloudflare.com/ips-v4"

#   request_headers = {
#     Accept = "application/json"
#   }
# }

# module "firewall_rule-cloudflare" {
#   source       = "terraform-google-modules/network/google//modules/firewall-rules"
#   project_id   = var.config.project
#   network_name = "default" 
#   rules = [{
#     name        = "fw-dynatrace-app-cloudflare-traffic-v2"
#     description = null
#     direction   = "INGRESS"
#     priority    = 1000
#     ranges      = split("\n", data.http.example.response_body)
#     target_tags = ["dynatrace"]
#     allow = [{
#       protocol = "TCP"
#       ports    = ["443", "80"]
#     }]
#     deny = []
#     log_config = {
#       metadata = "INCLUDE_ALL_METADATA"
#     }
#   }]
# }


# output "ip_cidrs" {
#   value = data.http.example
# }

# XXXXXXXXX---cloudflare ip---XXXXXXXXXXXX

# locals {
#   key_val = { for rule in local.firewall_rules_flat : "${rule.server_name}-${rule.rule_name}" => rule }
# }
# output "key_val" {
#   value = local.key_val
# }

# output "cidrs" {
#   value = google_compute_firewall.rule
# }


# output "firewall_rules" {
#   value = module.firewall_rules
# }

# output "firewall_rules_ip_ranges" {
#   value = module.firewall_rules["dynatrace-fw-dynatrace-app-traffic-v2"].firewall_rules.fw-dynatrace-app-traffic-v2.source_ranges
# }

# output "pass_rules" {
#   value = toset([concat(local.firewall_rules_flat[0].source_ranges, data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks)])
# }

# output "flat_firewall" {
#   value = local.firewall_rules_flat
# }


# output "cloudflareip" {
#   value = data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks
# }

# XXXXXXXXXXXXXXXXXXXXX


# output "firewall_rules_flat" {
#   value = local.firewall_rules_flat
# }


# XXXXXXXXXXXXXX---FILE STORE---XXXXXXXXXXXXXXXXX



# # Reserve an IP CIDR range for Private Google Access
# resource "google_compute_global_address" "private_google_access_cidr" {
#   project       = var.config.project
#   name          = "private-google-access-cidr"
#   purpose       = "VPC_PEERING"
#   address_type  = "INTERNAL"
#   prefix_length = 20 # Adjust the prefix length according to your requirements
#   network       = "default"
# }
# # --------------------------------------------------------
# resource "google_filestore_instance" "instance" {
#   name     = "dt-nfs"
#   location = "us-central1-b"
#   tier     = "BASIC_HDD"
#   project  = var.config.project

#   file_shares {
#     capacity_gb = 1024
#     name        = "testing"

#     nfs_export_options {
#       # ip_ranges   = ["10.10.0.0/24"]
#       ip_ranges   = ["192.168.1.5", "192.168.1.7"]
#       access_mode = "READ_ONLY"
#       squash_mode = "ROOT_SQUASH"
#       anon_uid    = 123
#       anon_gid    = 456
#     }

#     nfs_export_options {
#       ip_ranges = ["192.168.1.6"]
#       # ip_ranges   = [for instance in local.lb_instances : instance.ip_address]
#       access_mode = "READ_WRITE"
#       squash_mode = "NO_ROOT_SQUASH"
#     }
#   }

#   networks {
#     network           = "default"
#     modes             = ["MODE_IPV4"]
#     connect_mode      = "PRIVATE_SERVICE_ACCESS"
#     reserved_ip_range = "testing-ip-range"
#   }
# }
# # --------------------------------------------------------


# data "google_compute_global_address" "allocated_range" {
#   name    = "default-ip-range" # Replace with the name of the allocated IP range you want to fetch
#   project = var.config.project
# }

# output "allocated_ip_range_cidr" {
#   value = data.google_compute_global_address.allocated_range
# }

# XXXXXXXXXXXXXX---FILE STORE---XXXXXXXXXXXXXXXXX


# XXXXXXXXXXXXXX---vpc-private-connect---XXXXXXXXXXXXXXXXX

# # Define the global network endpoint group
# # Define the global network endpoint group
# resource "google_compute_global_network_endpoint_group" "example" {
#   project               = var.config.project
#   name                  = "example-endpoint-group"
#   description           = "Example global network endpoint group"
#   network_endpoint_type = "INTERNET_IP_PORT" # Adjust based on your requirement
# }


# # Reserve an IP CIDR range for Private Google Access
# resource "google_compute_global_address" "private_google_access_cidr" {
#   project       = var.config.project
#   name          = "private-google-access-cidr"
#   purpose       = "VPC_PEERING"
#   address_type  = "INTERNAL"
#   prefix_length = 16 # Adjust the prefix length according to your requirements
#   network       = "default"
# }

# resource "google_compute_global_network_endpoint" "private_google_access" {
#   project                       = var.config.project
#   provider                      = google-beta
#   global_network_endpoint_group = google_compute_global_network_endpoint_group.example.name # Replace with the name of your global network endpoint group
#   port                          = 80                                                        # Adjust the port number according to your requirements
#   ip_address                    = "10.95.0.2"
# }

#NOT WORKING PROPERLY.

# XXXXXXXXXXXXXX---vpc-private-connect---XXXXXXXXXXXXXXXXX



# locals {
#   lb_instances = [for vm_info in module.compute_instance["dynatrace"].instances_details : {
#     name       = vm_info.name,
#     id         = vm_info.id,
#     zone       = vm_info.zone,
#     ip_address = vm_info.network_interface[0].network_ip
#   }]

#   # vm_instances = [for vm_info in module.compute_instance["dynatrace"].instances_details : vm_info.id]
# }

# module "managed_instance_group" {
#   project_id  = var.config.project
#   source      = "terraform-google-modules/vm/google//modules/mig"
#   version     = "11.1.0"
#   region      = var.config.region
#   target_size = 2
#   named_ports = [{
#     name = "https"
#     port = 443
#   }]
#   instance_template = tostring(module.instance_template["dynatrace"].self_link)
#   hostname          = "dynatrace-tcp-proxy-xlb-mig"
#   # target_pools      = ["${module.gce-lb-fr.target_pool}"]
#   # ssh_source_ranges = ["0.0.0.0/0"]
# }


# module "regional_proxy_lb" {
#   source                   = "terraform-google-modules/lb/google//modules/regional_proxy_lb"
#   version                  = "4.1.0"
#   name                     = "dynatrace-lb"
#   region                   = var.config.region
#   project                  = var.config.project
#   network_project          = var.config.project
#   network                  = "default"
#   target_tags              = ["dummy-tag"]
#   port_front_end           = 443
#   create_proxy_only_subnet = true
#   proxy_only_subnet_cidr   = "192.168.5.0/24"
#   create_firewall_rules    = true
#   health_check = {
#     description        = "Health check to determine whether instances are responsive and able to do work"
#     check_interval_sec = 10
#     tcp_health_check = {
#       port_specification = "USE_SERVING_PORT"
#     }
#   }


#   backend = {
#     port             = 443
#     port_name        = "tcp"
#     backend_type     = "INSTANCE_GROUP"
#     session_affinity = "CLIENT_IP"
#     timeout_sec      = 50 #default 30

#     log_config = {
#       enable      = true
#       sample_rate = 1
#     }

#     groups = [{
#       group                        = module.managed_instance_group.instance_group
#       balancing_mode               = "UTILIZATION"
#       capacity_scaler              = 0.5
#       max_connections_per_instance = 1000
#       max_rate_per_instance        = null
#       max_utilization              = 0.7
#     }]
#   }
# }

# module "load_balancer" {
#   source       = "GoogleCloudPlatform/lb/google"
#   version      = "~> 2.0.0"
#   project      = var.config.project
#   region       = var.config.region
#   name         = "load-balancer"
#   service_port = 443
#   target_tags  = ["allow-lb-service"]
#   network      = "default"
# }

# module "managed_instance_group" {
#   source            = "terraform-google-modules/vm/google//modules/mig"
#   version           = "~> 1.0.0"
#   region            = var.config.region
#   project           = var.config.project
#   target_size       = 2
#   hostname          = "mig-simple"
#   instance_template = module.instance_template["dynatrace"].self_link
#   target_pools      = [module.load_balancer.target_pool]
#   named_ports = [{
#     name = "http"
#     port = 443
#   }]
# }



#############WORKING BLOCK#############
# Create external IP addresses for each instance
# resource "google_compute_address" "default" {
#   depends_on = [module.compute_instance]
#   count      = length(local.lb_instances)
#   name       = "${local.lb_instances[count.index].name}-external-ip"
#   project    = var.config.project
#   region     = var.config.region
# }

# # Create target instances for load balancing
# resource "google_compute_target_instance" "default" {
#   depends_on = [module.compute_instance]
#   count      = length(local.lb_instances)
#   project    = var.config.project
#   zone       = local.lb_instances[count.index].zone
#   name       = "${local.lb_instances[count.index].name}-tcp-target-instance"
#   instance   = local.lb_instances[count.index].id
# }


# # Create forwarding rules for directing traffic to the target instances
# resource "google_compute_forwarding_rule" "default" {
#   depends_on            = [module.compute_instance]
#   count                 = length(local.lb_instances)
#   project               = var.config.project
#   ip_protocol           = "TCP"
#   name                  = "${local.lb_instances[count.index].name}-tcp-fwd-rule"
#   region                = var.config.region
#   load_balancing_scheme = "EXTERNAL"
#   port_range            = "443"
#   target                = google_compute_target_instance.default[count.index].self_link
#   ip_address            = google_compute_address.default[count.index].address
#   # ip_address = module.regional_external_address.addresses[count.index]

# }


# output "ip_addresses" {
#   value = google_compute_address.default
# }
# output "target" {
#   value = google_compute_target_instance.default
# }

# output "frd_rule" {
#   value = google_compute_forwarding_rule.default
# }


# resource "ansible_playbook" "playbook" {
#   depends_on = [
#     # ansible_group.group,
#     # ansible_host.hosts,
#     module.compute_instance
#   ]
#   count    = length(local.lb_instances)
#   playbook = "dynatrace-playbook.yml"
#   name     = local.lb_instances[count.index].ip_address
#   # name       = local.instances[0].ip_address
#   # groups     = [ansible_group.group.name]
#   verbosity  = 6
#   replayable = true
#   # temp_inventory_file = "inventory.ini"

#   # extra_vars = {
#   #   temp_inventory_file = "inventory.ini"
#   #   inventory           = "inventory.ini"
#   #   #   # private_key_file = "./dynatrace_ssh_key.pem"
#   # }
# }



# output "lb_instances" {
#   value = local.lb_instances
# }

##############WORKING BLOCK#############



locals {

  # server_list = [for server_name, vm_info in module.compute_instance : server_name]

  # all_vms = concat([
  #   for server_name, vm_info in module.compute_instance :
  #   [
  #     for instance_details in vm_info.instances_details :
  #     [server_name, instance_details.network_interface[0].network_ip, instance_details.id]
  #   ]
  # ]...)


}

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

# locals {
#   lb_instances = [for vm_info in module.compute_instance["dynatrace"].instances_details : {
#     name = vm_info.name,
#     id   = vm_info.id,
#     zone = vm_info.zone
#   }]
# }




#####LEGACY MODULE ISSUE
# module "ip_address_only" {
#   depends_on = [module.compute_instance]
#   count      = length(local.lb_instances)
#   name       = "${local.lb_instances[count.index].name}-external-ip-module"
#   project    = var.config.project
#   region     = var.config.region
#   source     = "terraform-google-modules/address/google//examples/ip_address_only"
#   version    = "3.2.0"
#   # insert the 4 required variables here
# }

# module "global_external_address" {
#   depends_on = [module.compute_instance]
#   count      = length(local.lb_instances)
#   source     = "terraform-google-modules/address/google//examples/global_external_address"
#   version    = "3.2.0"
#   project_id = var.config.project
# }


# ################3 ip's###############
# module "regional_external_address" {
#   depends_on = [module.compute_instance]
#   # count      = length(local.lb_instances)
#   source     = "terraform-google-modules/address/google//examples/regional_external_address"
#   version    = "3.2.0"
#   project_id = var.config.project
# }
################3 ip's###############

# module "ip_address_with_specific_ip" {
#   depends_on = [module.compute_instance]
#   source     = "terraform-google-modules/address/google//examples/ip_address_with_specific_ip"
#   version    = "3.2.0"
#   project_id = var.config.project
#   names      = []
#   addresses =[]
# }


# module "gce-lb-fr" {
#   source       = "GoogleCloudPlatform/lb/google"
#   version      = "~> 4.0"
#   region       = var.config.region
#   network      = "default"
#   project      = var.config.project
#   name         = "group1-lb"
#   service_port = "80"
#   target_tags  = ["allow-group1"]
# }



###################SELF DECLARED MODULES####################


# module "compute_external_ip_address" {
#   source     = "ankitr-c/compute_external_ip_address/google"
#   version    = "1.0.1"
#   depends_on = [module.compute_instance]
#   count      = length(local.lb_instances)
#   name       = "${local.lb_instances[count.index].name}-external-ip"
#   project    = var.config.project
#   region     = var.config.region
# }

# module "compute_target_instance" {
#   source      = "ankitr-c/compute_target_instance/google"
#   version     = "1.0.1"
#   depends_on  = [module.compute_instance]
#   count       = length(local.lb_instances)
#   project     = var.config.project
#   zone        = local.lb_instances[count.index].zone
#   name        = "${local.lb_instances[count.index].name}-tcp-target-instance"
#   instance_id = local.lb_instances[count.index].id
# }


# module "compute_forwarding_rule_for_target" {
#   source                         = "ankitr-c/compute_forwarding_rule_for_target/google"
#   version                        = "1.0.0"
#   depends_on                     = [module.compute_instance]
#   count                          = length(local.lb_instances)
#   project                        = var.config.project
#   name                           = "${local.lb_instances[count.index].name}-tcp-fwd-rule"
#   region                         = var.config.region
#   port_range                     = "443"
#   google_compute_target_instance = module.compute_target_instance[count.index].self_link
#   ip_address                     = module.compute_external_ip_address[count.index].ip_address
# }

##############SELF MODULES####################



# output "compute-op" {
#   value = module.compute_instance["dynatrace"].instances_details[0].hostname
# }



# instances_hosts = [
#   for server_name, vm_info in module.compute_instance :
#   flatten(
#     [
#       for instance_details in vm_info.instances_details :
#       [server_name, instance_details.hostname]
#   ]...)
# ]


# locals {
# instances = [
#   for server_name, vm_info in module.compute_instance :
#   flatten(
#     [
#       for instance_details in vm_info.instances_details :
#       {
#         server     = server_name
#         ip_address = instance_details.network_interface[0].network_ip
#       }
#   ]...)
# ]

# instances = [
#   for server_name, vm_info in module.compute_instance :
#   flatten([
#     for instance_details in vm_info.instances_details :
#     {
#       server     = server_name
#       ip_address = instance_details.network_interface[0].network_ip
#     }
#   ])
# ]


############TEMP LOCK############
#   instances = flatten([
#     for server_name, vm_info in module.compute_instance :
#     [
#       for instance_details in vm_info.instances_details :
#       {
#         server     = server_name
#         ip_address = instance_details.network_interface[0].network_ip
#       }
#     ]
#   ])


#   server_key_mapping = {
#     for server_name, vm_info in module.compute_instance :
#     server_name => [
#       for instance_details in vm_info.instances_details :
#       instance_details.network_interface[0].network_ip
#     ]
#   }

# }

############TEMP LOCK############


# resource "null_resource" "ansible_instances_connection_check" {
#   depends_on = [module.compute_instance]
#   count      = length(local.instances)
#   provisioner "remote-exec" {
#     inline = ["echo 'Wait until SSH is ready'"]
#     connection {
#       type        = "ssh"
#       user        = "centos"
#       private_key = tls_private_key.private_key_pair[local.instances[count.index].server].private_key_pem
#       host        = local.instances[count.index].ip_address
#     }
#   }
# }

# resource "ansible_host" "hosts" {
#   count  = length(local.instances)
#   name   = local.instances[count.index].ip_address
#   groups = [local.instances[count.index].server]
#   variables = {
#     ansible_user                 = "centos",
#     ansible_ssh_private_key_file = "${local.instances[count.index].server}_ssh_key.pem",
#     ansible_python_interpreter   = "/usr/bin/python3"
#   }
# }


# resource "ansible_group" "group" {
#   for_each = local.server_key_mapping
#   name     = each.key
# }

# ######################################################
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
# ######################################################

#VIP BLOCK


################VIP ANSIBLE TESTING########################
# resource "null_resource" "ansible_inventory_tester" {
#   triggers = {
#     always_run = "${timestamp()}"
#   }

#   provisioner "local-exec" {
#     command = <<EOT
# cat <<EOF > inventory.ini
# [dynatrace]
# ${join("\n", [for instance in module.compute_instance["dynatrace"].instances_details : "${instance.name} ansible_host=${instance.network_interface[0].network_ip}"])}
# EOF
# EOT
#   }
# }


# locals {
#   lb_instances = [for vm_info in module.compute_instance["dynatrace"].instances_details : {
#     name       = vm_info.name,
#     id         = vm_info.id,
#     zone       = vm_info.zone,
#     ip_address = vm_info.network_interface[0].network_ip
#   }]
# }

# resource "ansible_host" "hosts" {
#   count  = length(local.lb_instances)
#   name   = local.lb_instances[count.index].ip_address
#   groups = ["dynatrace"]
#   variables = {
#     ansible_user                 = "centos",
#     ansible_ssh_private_key_file = "dynatrace_ssh_key.pem",
#     ansible_python_interpreter   = "/usr/bin/python3"
#   }
# }


# resource "ansible_group" "group" {
#   name = "dyantrace"
# }


# output "groups" {
#   value = ansible_group.group
# }

# output "hosts" {
#   value = ansible_host.hosts
# }

# ------------------
# output "instances" {
#   value = local.instances
# }

# output "key_mapping" {
#   value = local.server_key_mapping
# }
# ----------------------
# output "instances_name" {
#   value = local.instances_hosts
# }

################VIP ANSIBLE TESTING########################




# resource "null_resource" "Ansible part null resource working" {

#   ###########################ANSIBLE PART NULL RESOURCE WORKING############################

#   # resource "null_resource" "ansible_inventory_creator" {
#   #   triggers = {
#   #     always_run = "${timestamp()}"
#   #   }

#   #   provisioner "local-exec" {
#   #     command = <<EOT
#   # cat <<EOF > inventory.ini
#   # ${join("\n", [for server_name, data in module.compute_instance : "[${server_name}]\n${join("\n", [for instance in data.instances_details : "${instance.name} ansible_host=${instance.network_interface[0].network_ip}"])}"])}
#   # EOF
#   # EOT
#   #   }
#   # }

#   # resource "null_resource" "ansible_instances_connection_check" {
#   #   count = length(local.all_vms)
#   #   provisioner "remote-exec" {
#   #     inline = ["echo 'Wait until SSH is ready'"]
#   #     connection {
#   #       type        = "ssh"
#   #       user        = "centos"
#   #       private_key = tls_private_key.private_key_pair[local.all_vms[count.index][0]].private_key_pem
#   #       host        = local.all_vms[count.index][1]
#   #     }
#   #   }
#   # }

#   # resource "null_resource" "ansible_playbook_runner" {
#   #   triggers = {
#   #     always_run = "${timestamp()}"
#   #   }
#   #   depends_on = [null_resource.ansible_instances_connection_check]
#   #   count      = length(local.server_list)
#   #   provisioner "local-exec" {
#   #     command = "ansible-playbook  -i inventory.ini -u centos --private-key ${local.server_list[count.index]}_ssh_key.pem ${local.server_list[count.index]}-playbook.yml"
#   #   }
#   # }

# }

# resource "null_resource" "PASSTHROUGH LOAD BALANCER PART FOR DYNATRACE" {

#   ######################PASSTHROUGH LOAD BALANCER PART FOR DYNATRACE###########################

#   # resource "google_compute_instance_group" "default" {
#   #   project  = var.config.project
#   #   zone     = "us-west1-a"
#   #   for_each = local.lb_servers
#   #   name     = "${each.key}-tcp-passthrough-umg"
#   #   # instances = [for server_data in local.all_vms : server_data[2] if server_data[0] == "dynatrace"]
#   #   instances = each.value
#   #   named_port {
#   #     name = "https"
#   #     port = "443"
#   #   }
#   # }


#   # resource "google_compute_region_health_check" "default" {
#   #   for_each           = local.lb_servers
#   #   project            = var.config.project
#   #   region             = var.config.region
#   #   name               = "${each.key}-tcp-passthrough-health-check"
#   #   timeout_sec        = 1
#   #   check_interval_sec = 5

#   #   tcp_health_check {
#   #     port = "443"
#   #   }
#   # }

#   # resource "google_compute_region_backend_service" "default" {
#   #   project               = var.config.project
#   #   region                = var.config.region
#   #   for_each              = local.lb_servers
#   #   name                  = "${each.key}-tcp-passthrough-xlb-backend-service"
#   #   protocol              = "TCP"
#   #   port_name             = "tcp"
#   #   load_balancing_scheme = "EXTERNAL"
#   #   timeout_sec           = 10
#   #   health_checks         = [google_compute_region_health_check.default[each.key].id]
#   #   backend {
#   #     group = google_compute_instance_group.default[each.key].id
#   #     # balancing_mode = "UTILIZATION"
#   #     balancing_mode = "CONNECTION"
#   #     # max_utilization = 0.70
#   #     # capacity_scaler = 1.0
#   #   }
#   # }



#   # resource "google_compute_forwarding_rule" "default" {
#   #   project               = var.config.project
#   #   region                = var.config.region
#   #   for_each              = local.lb_servers
#   #   name                  = "${each.key}-tcp-passthrouugh-xlb-forwarding-rule"
#   #   backend_service       = google_compute_region_backend_service.default[each.key].id
#   #   ip_protocol           = "TCP"
#   #   load_balancing_scheme = "EXTERNAL"
#   #   port_range            = "443"
#   #   # all_ports = true
#   #   # allow_global_access = true
#   #   # all_ports             = true
#   #   # allow_global_access   = true
#   #   # network               = google_compute_network.ilb_network.id
#   #   # subnetwork            = google_compute_subnetwork.ilb_subnet.id
#   # }

#   ####################ABOVE IS THE WORKING BLOCK##################

# }

# resource "null_resource" "TARGET GROUP FORWARDING RULE FOR SERVER SPECIFIC" {

#   ####################TARGET GROUP FORWARDING RULE################

#   # lb_servers = {
#   #   for server_name, vm_info in module.compute_instance :
#   #   server_name => [for instance_details in vm_info.instances_details : instance_details.id]
#   #   # if contains(local.servers_require_lb, server_name)
#   #   if contains(["dynatrace"], server_name)

#   # }


#   # #################IMP###################
#   # locals {
#   #   lb_servers = {
#   #     for server_name, vm_info in module.compute_instance :
#   #     server_name => [for instance_details in vm_info.instances_details : instance_details.id]
#   #     if contains(["dynatrace"], server_name)
#   #   }
#   # #################IMP##################

#   # lb_instances = [
#   #   for server_name, vm_info in module.compute_instance :
#   #   [for instance_details in vm_info.instances_details : instance_details.id]
#   #   if server_name == "dynatrace"
#   # ]

#   ############################
#   # lb_instances = [
#   #   for vm_info in module.compute_instance["dynatrace"].instances_details : [vm_info.name, vm_info.id, vm_info.zone]
#   # ]
#   #############################

#   # instances = [
#   #   for server_name, vm_info in module.compute_instance :
#   #   flatten(
#   #     [
#   #       for instance_details in vm_info.instances_details :
#   #       [server_name, instance_details.network_interface[0].network_ip]
#   #   ]...)
#   # ]

#   # }

# }

# resource "null_resource" "working block for forwarding rule" {

#   # # ----------working block for forwarding rule---------------

#   # # locals {
#   # #   lb_instances = [
#   # #     for vm_info in module.compute_instance["dynatrace"].instances_details : [vm_info.name, vm_info.id, vm_info.zone]
#   # #   ]
#   # # }

#   # # output "lb_instances" {
#   # #   value = local.lb_instances
#   # # }

#   # resource "google_compute_address" "default" {
#   #   count   = length(local.lb_instances)
#   #   name    = "${local.lb_instances[count.index][0]}-external-ip"
#   #   project = var.config.project
#   #   region  = var.config.region
#   # }

#   # resource "google_compute_target_instance" "default" {
#   #   depends_on = [ module.compute_instance ]
#   #   count = length(local.lb_instances)
#   #   # for_each = local.lb_servers
#   #   project = var.config.project
#   #   # zone    = "us-west1-a"
#   #   zone = local.lb_instances[count.index][2]
#   #   # name     = "${each.key}tcp-target-instance"
#   #   name     = "${local.lb_instances[count.index][0]}-tcp-target-instance"
#   #   instance = local.lb_instances[count.index][1]
#   #   # instance = each.value[0].instances_details[0].id

#   # }

#   # resource "google_compute_forwarding_rule" "default" {
#   #   depends_on = [ module.compute_instance ]
#   #   count = length(local.lb_instances)
#   #   # for_each              = local.lb_servers
#   #   project               = var.config.project
#   #   ip_protocol           = "TCP"
#   #   name                  = "${local.lb_instances[count.index][0]}-tcp-fwd-rule"
#   #   region                = var.config.region
#   #   load_balancing_scheme = "EXTERNAL"
#   #   port_range            = "443"
#   #   target                = google_compute_target_instance.default[count.index].self_link
#   #   ip_address            = google_compute_address.default[count.index].address
#   # }
#   # # ----------working block for forwarding rule---------------

# }

# resource "null_resource" "PROXY LOAD BALANCER" {

#   #####################PROXY LOAD BALANCER#####################


#   # locals {

#   #   lb_servers = {
#   #     for server_name, vm_info in module.compute_instance :
#   #     server_name => [for instance_details in vm_info.instances_details : instance_details.id]
#   #     # if contains(local.servers_require_lb, server_name)
#   #     if contains(["dynatrace"], server_name)

#   #   }
#   # }



#   # resource "google_compute_global_forwarding_rule" "default" {
#   #   project               = var.config.project
#   #   for_each              = local.lb_servers
#   #   name                  = "${each.key}-tcp-proxy-xlb-forwarding-rule"
#   #   ip_protocol           = "TCP"
#   #   load_balancing_scheme = "EXTERNAL"
#   #   port_range            = "80"
#   #   target                = google_compute_target_tcp_proxy.default[each.key].id
#   #   # ip_address            = module.global_external_address[count.index].addresses
#   # }

#   # resource "google_compute_target_tcp_proxy" "default" {
#   #   for_each        = local.lb_servers
#   #   project         = var.config.project
#   #   name            = "${each.key}-test-proxy-health-check"
#   #   backend_service = google_compute_backend_service.default[each.key].id
#   # }

#   # resource "google_compute_backend_service" "default" {
#   #   project               = var.config.project
#   #   for_each              = local.lb_servers
#   #   name                  = "${each.key}-tcp-proxy-xlb-backend-service"
#   #   protocol              = "TCP"
#   #   port_name             = "tcp"
#   #   load_balancing_scheme = "EXTERNAL"
#   #   timeout_sec           = 10
#   #   health_checks         = [google_compute_health_check.default[each.key].id]
#   #   backend {
#   #     group           = google_compute_instance_group.default[each.key].id
#   #     balancing_mode  = "UTILIZATION"
#   #     max_utilization = 0.70
#   #     capacity_scaler = 1.0
#   #   }
#   # }


#   # resource "google_compute_health_check" "default" {
#   #   project            = var.config.project
#   #   for_each           = local.lb_servers
#   #   name               = "${each.key}-tcp-proxy-health-check"
#   #   timeout_sec        = 1
#   #   check_interval_sec = 5

#   #   tcp_health_check {
#   #     port = "443"
#   #   }
#   # }

#   # resource "google_compute_instance_group" "default" {
#   #   project   = var.config.project
#   #   zone      = "us-west1-a"
#   #   for_each  = local.lb_servers
#   #   name      = "${each.key}-tcp-proxy-umg"
#   #   instances = each.value
#   #   named_port {
#   #     name = "https"
#   #     port = "443"
#   #   }
#   # }



#   # resource "google_compute_instance_group" "default" {
#   #   project  = var.config.project
#   #   zone     = "us-west1-a"
#   #   for_each = local.lb_servers
#   #   name     = "${each.key}-tcp-passthrough-umg"
#   #   # instances = [for server_data in local.all_vms : server_data[2] if server_data[0] == "dynatrace"]
#   #   instances = each.value
#   #   named_port {
#   #     name = "https"
#   #     port = "443"
#   #   }
#   # }


#   # resource "google_compute_region_health_check" "default" {
#   #   for_each           = local.lb_servers
#   #   project            = var.config.project
#   #   region             = var.config.region
#   #   name               = "${each.key}-tcp-passthrough-health-check"
#   #   timeout_sec        = 1
#   #   check_interval_sec = 5

#   #   tcp_health_check {
#   #     port = "443"
#   #   }
#   # }

#   # resource "google_compute_region_backend_service" "default" {
#   #   project               = var.config.project
#   #   region                = var.config.region
#   #   for_each              = local.lb_servers
#   #   name                  = "${each.key}-tcp-passthrough-xlb-backend-service"
#   #   protocol              = "TCP"
#   #   port_name             = "tcp"
#   #   load_balancing_scheme = "EXTERNAL"
#   #   timeout_sec           = 10
#   #   health_checks         = [google_compute_region_health_check.default[each.key].id]
#   #   backend {
#   #     group = google_compute_instance_group.default[each.key].id
#   #     # balancing_mode = "UTILIZATION"
#   #     balancing_mode = "CONNECTION"
#   #     # max_utilization = 0.70
#   #     # capacity_scaler = 1.0
#   #   }
#   # }



#   # resource "google_compute_forwarding_rule" "default" {
#   #   project               = var.config.project
#   #   region                = var.config.region
#   #   for_each              = local.lb_servers
#   #   name                  = "${each.key}-tcp-passthrouugh-xlb-forwarding-rule"
#   #   backend_service       = google_compute_region_backend_service.default[each.key].id
#   #   ip_protocol           = "TCP"
#   #   load_balancing_scheme = "EXTERNAL"
#   #   port_range            = "443"
#   #   # all_ports = true
#   #   # allow_global_access = true
#   #   # all_ports             = true
#   #   # allow_global_access   = true
#   #   # network               = google_compute_network.ilb_network.id
#   #   # subnetwork            = google_compute_subnetwork.ilb_subnet.id
#   # }



#   # for_each   = local.server_key_mapping


#   # locals {
#   #   server_key_mapping = {
#   #     for server_name, vm_info in module.compute_instance :
#   #     server_name => [
#   #       for instance_details in vm_info.instances_details :
#   #       instance_details.network_interface[0].network_ip
#   #     ]
#   #   }

#   # }

#   # resource "null_resource" "ansible_instances_connection_check" {
#   #   triggers = {
#   #     always_run = "${timestamp()}"
#   #   }
#   #   for_each = local.server_key_mapping
#   #   provisioner "remote-exec" {
#   #     inline = ["echo 'Wait until SSH is ready'"]
#   #     connection {
#   #       type        = "ssh"
#   #       user        = "centos"
#   #       private_key = tls_private_key.private_key_pair[each.key].private_key_pem
#   #       host        = each.value[0]
#   #     }
#   #   }
#   # }


# }

# resource "null_resource" "OLD CODE" {

#   # locals {
#   #   server_key_mapping = {
#   #     for idx, instance in module.compute_instance :
#   #     idx => {
#   #       for instance_details in instance.instances_details :
#   #       idx => instance_details.network_interface[0].network_ip
#   #     }
#   #   }
#   # }

#   # output "server_key_mapping" {
#   #   value = local.server_key_mapping
#   # }


#   # resource "null_resource" "ansible_provisioner" {

#   #   provisioner "remote-exec" {
#   #     inline = ["echo 'Wait until SSH is ready'"]

#   #     connection {
#   #       type = "ssh"
#   #       user = local.ssh_user
#   #       private_key = tls_private_key.private_key_pair["dynatrace"].private_key_pem
#   #       host        = local.ip_addresses.server-dynatrace[0]
#   #     }
#   #   }
#   #   # provisioner "local-exec" {
#   #   #   command = "ansible-inventory -i ${local.ip_addresses.server-dynatrace[0]} --list"
#   #   #   # command = "ansible-playbook  -i ${aws_instance.nginx.public_ip}, --private-key ${local.private_key_path} nginx.yaml"
#   #   # }

#   # }


#   # # Ansible Code Block 

#   # locals {
#   #   ssh_user         = "centos"

#   # ip_addresses = {
#   #   for idx, instance in module.compute_instance :
#   #   "server-${idx}" => [
#   #     for instance_details in instance.instances_details :
#   #     instance_details.network_interface[0].network_ip
#   #   ]
#   # }
#   # }

#   #################
#   ##Map for inventory file
#   # locals {
#   #   ssh_user = "centos"

#   #   ip_addresses = {
#   #     for idx, instance in module.compute_instance :
#   #     "${idx}" => {
#   #       for instance_details in instance.instances_details :
#   #       instance_details.name => instance_details.network_interface[0].network_ip
#   #     }
#   #   }
#   # }
#   # #################

#   # output "testing" {
#   #   value = local.ip_addresses
#   # }



#   # --------------------safe------------------------
#   # locals {
#   #   ssh_user = "centos"

#   #   ip_addresses = {
#   #     for idx, instance in module.compute_instance :
#   #     "${idx}" => {
#   #       for instance_details in instance.instances_details :
#   #       instance_details.name => instance_details.network_interface[0].network_ip
#   #     }
#   #   }
#   # }

#   # resource "null_resource" "ansible_inventory" {
#   #   provisioner "local-exec" {
#   #     command = <<EOT
#   # cat <<EOF > inventory.ini
#   # ${join("\n", [for key, val in local.ip_addresses : "[${key}]\n${join("\n", [for sn, ip in val : "${sn} ansible_host=${ip}"])}"])}
#   # EOF
#   # EOT
#   #   }
#   # }
#   # --------------------safe------------------------




#   #######
#   # resource "null_resource" "ansible_provisioner" {

#   #   provisioner "remote-exec" {
#   #     inline = ["echo 'Wait until SSH is ready'"]

#   #     connection {
#   #       type = "ssh"
#   #       user = local.ssh_user
#   #       private_key = tls_private_key.private_key_pair["dynatrace"].private_key_pem
#   #       host        = local.ip_addresses.server-dynatrace[0]
#   #     }
#   #   }
#   #   # provisioner "local-exec" {
#   #   #   command = "ansible-inventory -i ${local.ip_addresses.server-dynatrace[0]} --list"
#   #   #   # command = "ansible-playbook  -i ${aws_instance.nginx.public_ip}, --private-key ${local.private_key_path} nginx.yaml"
#   #   # }

#   # }
#   ########

#   #Ansible using resources:

#   #   ip_addresses = {
#   #     for idx, instance in module.compute_instance :
#   #     "server-${idx}" => [
#   #       for instance_details in instance.instances_details :
#   #       instance_details.network_interface[0].network_ip
#   #     ]
#   #   }

#   # locals {
#   #   ssh_user         = "ankitraut0987"
#   #   private_key_path = "dynatrace_ssh_key.pem"

#   #   ip_addresses = {
#   #     for idx, instance in module.compute_instance :
#   #     "server-${idx}" => [
#   #       for instance_details in instance.instances_details :
#   #       instance_details.network_interface[0].network_ip
#   #     ]
#   #   }

#   # }

#   # resource "ansible_host" "dynatrace" {
#   #   name   = "server-dynatrace"
#   #   groups = [ansible_group.server_group.name]

#   #   variables = {
#   #     yaml_list = jsonencode(local.ip_addresses.server-dynatrace[0])
#   #   }
#   # }

#   # resource "ansible_group" "server_group" {
#   #   name     = "server_group"
#   #   children = ["server-dynatrace"]
#   # }

#   # resource "ansible_playbook" "playbook" {
#   #   playbook = "playbook.yml"
#   #   name     = "apache installation playbook"
#   #   # replayable = true
#   #   groups    = [ansible_group.server_group.name]
#   #   verbosity = 6
#   # }




#   #NOT USEFULL

#   # ---------------------------------------------------
#   # module "instance_template" {
#   #   source             = "terraform-google-modules/vm/google//modules/instance_template"
#   #   version            = "~>9.0.0"
#   #   count              = length(var.server)
#   #   region             = var.config.region
#   #   project_id         = var.config.project
#   #   tags               = var.server[count.index].tags
#   #   source_image       = var.server[count.index].instance_config.source_image
#   #   disk_size_gb       = var.server[count.index].instance_config.root_disk_size
#   #   machine_type       = var.server[count.index].instance_config.machine_type
#   #   subnetwork         = var.network.subnet
#   #   subnetwork_project = var.network.project
#   #   labels             = merge(var.app.labels, var.server[count.index].labels)

#   #   metadata = var.server[count.index].instance_config.os_type == "linux" ? {
#   #     sshKeys                = var.server[count.index].instance_config.os_type == "linux" ? "${var.server[count.index].instance_config.gce_user}:${tls_private_key.private_key_pair[count.index].public_key_openssh}" : ""
#   #     block-project-ssh-keys = true
#   #   } : {}

#   #   service_account = {
#   #     email  = module.service_accounts[count.index].email
#   #     scopes = ["cloud-platform"]
#   #   }
#   #   additional_disks = [
#   #     {
#   #       disk_name    = var.server[count.index].instance_config.additional_disk_name
#   #       device_name  = var.server[count.index].instance_config.additional_disk_name
#   #       disk_size_gb = var.server[count.index].instance_config.additional_disk_size
#   #       disk_type    = var.server[count.index].instance_config.additional_disk_type
#   #       auto_delete  = true
#   #       boot         = false
#   #       disk_labels  = {}
#   #     }
#   #   ]
#   # }

#   ############# Private Key ##############

#   # resource "tls_private_key" "private_key_pair" {
#   #   #   count     = var.app.os == "linux" ? length(var.server) : 0
#   #   for_each  = var.app.os == "linux" ? local.servers : {}
#   #   algorithm = "RSA"
#   #   rsa_bits  = 4096
#   # }

#   # resource "local_sensitive_file" "ssh_key" {
#   #   #   count           = var.app.os == "linux" ? length(var.server) : 0
#   #   for_each        = var.app.os == "linux" ? local.servers : {}
#   #   content         = tls_private_key.private_key_pair[each.key].private_key_pem
#   #   filename        = "${path.module}/${each.value.name}_ssh_key.pem"
#   #   file_permission = "0600"
#   # }

# }


