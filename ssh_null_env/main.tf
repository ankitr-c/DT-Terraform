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


locals {
  instance_data = {
    for instance_key, instance_value in local.servers : instance_key => {
      # name=module.compute_instance[instance_key].instances_details[0].network_interface[0].name,
      name = module.compute_instance[instance_key].instances_details[0].name,
      user = local.servers[instance_key].instance_config.gce_user,
      link = local.servers[instance_key].instance_config.link
      zone = module.compute_instance[instance_key].instances_details[0].zone
    }
  }
}

resource "null_resource" "post_provisioning" {
  for_each = local.instance_data
  provisioner "local-exec" {
    environment = {
      NAME = each.value.name
      USER = each.value.user
      LINK = each.value.link
      ZONE = each.value.zone
    }
    command = "./external_script.sh"
  }
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
    ranges      = ["130.211.0.0/22", "35.191.0.0/16"]
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
