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
  lb_instances = [for vm_info in module.compute_instance["dynatrace"].instances_details : {
    name       = vm_info.name,
    id         = vm_info.id,
    zone       = vm_info.zone,
    ip_address = vm_info.network_interface[0].network_ip
  }]

  # vm_instances = [for vm_info in module.compute_instance["dynatrace"].instances_details : vm_info.id]
}

resource "google_compute_address" "default" {
  depends_on = [module.compute_instance]
  count      = length(local.lb_instances)
  name       = "${local.lb_instances[count.index].name}-external-ip"
  project    = var.config.project
  region     = var.config.region
}

# Create target instances for load balancing
resource "google_compute_target_instance" "default" {
  depends_on = [module.compute_instance]
  count      = length(local.lb_instances)
  project    = var.config.project
  zone       = local.lb_instances[count.index].zone
  name       = "${local.lb_instances[count.index].name}-tcp-target-instance"
  instance   = local.lb_instances[count.index].id
}


# Create forwarding rules for directing traffic to the target instances
resource "google_compute_forwarding_rule" "default" {
  depends_on            = [module.compute_instance]
  count                 = length(local.lb_instances)
  project               = var.config.project
  ip_protocol           = "TCP"
  name                  = "${local.lb_instances[count.index].name}-tcp-fwd-rule"
  region                = var.config.region
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  target                = google_compute_target_instance.default[count.index].self_link
  ip_address            = google_compute_address.default[count.index].address
}


# output "ip_addresses" {
#   value = google_compute_address.default
# }
# output "target" {
#   value = google_compute_target_instance.default
# }

# output "frd_rule" {
#   value = google_compute_forwarding_rule.default
# }



resource "ansible_playbook" "playbook" {
  depends_on = [
    module.compute_instance
  ]
  count      = length(local.lb_instances)
  playbook   = "dynatrace-playbook.yml"
  name       = local.lb_instances[count.index].ip_address
  verbosity  = 6
  replayable = true
}
