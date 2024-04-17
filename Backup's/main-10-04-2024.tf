# # XXXXXXXXXXXX---Testing for 10-02-2024---XXXXXXXXXXXX
# # includes instances, firewall and filestore.


# locals {
#   default_roles = [
#     "${var.config.project}=>roles/monitoring.metricWriter",
#     "${var.config.project}=>roles/logging.logWriter",
#     "${var.config.project}=>roles/iap.tunnelResourceAccessor",
#     "${var.config.project}=>roles/compute.instanceAdmin.v1"
#   ]
#   sa_conf = {
#     org_id = var.config.org_id
#   }
#   gce_user = var.app.os == "windows" ? "Admin" : "centos"

# }
# module "service_accounts" {
#   source     = "terraform-google-modules/service-accounts/google"
#   version    = "4.2.2"
#   for_each   = local.servers
#   project_id = var.config.project
#   names      = ["${var.app.name}-${each.value.name}-sa"]

#   org_id          = local.sa_conf["org_id"]
#   project_roles   = each.value.additional_service_account_roles != null ? concat(each.value.additional_service_account_roles, local.default_roles) : local.default_roles
#   grant_xpn_roles = false
# }

# locals {
#   servers = {
#     for idx, instance_config in var.server : instance_config.name => instance_config
#   }
# }

# module "compute_instance" {
#   source              = "terraform-google-modules/vm/google//modules/compute_instance"
#   version             = "11.1.0"
#   for_each            = local.servers
#   region              = var.config.region
#   hostname            = "${var.app.env}-${each.key}"
#   instance_template   = module.instance_template[each.key].self_link
#   num_instances       = each.value.instance_config.count
#   deletion_protection = false
#   subnetwork          = var.network.subnet
#   subnetwork_project  = var.network.project
# }


# module "instance_template" {
#   source             = "terraform-google-modules/vm/google//modules/instance_template"
#   version            = "11.1.0"
#   for_each           = local.servers
#   region             = var.config.region
#   project_id         = var.config.project
#   tags               = each.value.tags
#   source_image       = each.value.instance_config.source_image
#   disk_size_gb       = each.value.instance_config.root_disk_size
#   machine_type       = each.value.instance_config.machine_type
#   subnetwork         = var.network.subnet
#   subnetwork_project = var.network.project
#   labels             = merge(var.app.labels, each.value.labels)

#   # metadata = each.value.instance_config.os_type == "linux" ? {
#   #   sshKeys                = each.value.instance_config.os_type == "linux" ? "${each.value.instance_config.gce_user}:${tls_private_key.private_key_pair[each.key].public_key_openssh}" : ""
#   #   block-project-ssh-keys = true
#   # } : {}


#   service_account = {
#     email  = module.service_accounts[each.key].email
#     scopes = ["cloud-platform"]
#   }

#   additional_disks = [
#     {
#       disk_name    = each.value.instance_config.additional_disk_name
#       device_name  = each.value.instance_config.additional_disk_name
#       disk_size_gb = each.value.instance_config.additional_disk_size
#       disk_type    = each.value.instance_config.additional_disk_type
#       auto_delete  = true
#       boot         = false
#       disk_labels  = {}
#     }
#   ]
# }



# #########################PRIVATE KEY PART####################

# resource "tls_private_key" "private_key_pair" {
#   for_each  = var.app.os == "linux" ? local.servers : {}
#   algorithm = "RSA"
#   rsa_bits  = 4096
# }

# resource "local_sensitive_file" "ssh_key" {
#   for_each        = var.app.os == "linux" ? local.servers : {}
#   content         = tls_private_key.private_key_pair[each.key].private_key_pem
#   filename        = "${path.module}/${each.value.name}_ssh_key.pem"
#   file_permission = "0600"
# }


# data "http" "example" {
#   url = "https://www.cloudflare.com/ips-v4"

#   # Optional request headers
#   request_headers = {
#     Accept = "application/json"
#   }
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
#   version      = "9.0.0"
#   project_id   = var.config.project
#   network_name = "default" #module.vpc.network_name
#   #   for_each     = { for rule in local.firewall_rules_flat : "${rule.server_name}-${rule.rule_name}" => rule }
#   for_each = local.map_loops
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


# module "firewall_rule-cloudflare" {
#   source       = "terraform-google-modules/network/google//modules/firewall-rules"
#   version      = "9.0.0"
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


# resource "google_filestore_instance" "instance" {
#   name     = "dt-nfs"
#   location = "us-central1-b"
#   tier     = "BASIC_HDD"
#   project  = var.config.project

#   file_shares {
#     capacity_gb = 1024
#     name        = "testing"

#     # nfs_export_options {
#     #   # ip_ranges   = ["10.10.0.0/24"]
#     #   ip_ranges   = ["192.168.1.5", "192.168.1.7"]
#     #   access_mode = "READ_ONLY"
#     #   squash_mode = "ROOT_SQUASH"
#     #   anon_uid    = 123
#     #   anon_gid    = 456
#     # }

#     nfs_export_options {
#       #   ip_ranges = ["192.168.1.6"]
#       ip_ranges   = [for instance in local.lb_instances : instance.ip_address]
#       access_mode = "READ_WRITE"
#       squash_mode = "NO_ROOT_SQUASH"
#     }
#   }

#   networks {
#     network      = "default"
#     modes        = ["MODE_IPV4"]
#     connect_mode = "PRIVATE_SERVICE_ACCESS"
#   }
# }


# locals {
#   lb_instances = [for vm_info in module.compute_instance["dynatrace"].instances_details : {
#     name       = vm_info.name,
#     id         = vm_info.id,
#     zone       = vm_info.zone,
#     ip_address = vm_info.network_interface[0].network_ip
#   }]

#   # vm_instances = [for vm_info in module.compute_instance["dynatrace"].instances_details : vm_info.id]
# }


