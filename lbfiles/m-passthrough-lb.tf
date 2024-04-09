
module "managed_instance_group" {
  project_id  = var.config.project
  source      = "terraform-google-modules/vm/google//modules/mig"
  version     = "11.1.0"
  region      = var.config.region
  target_size = 2
  named_ports = [{
    name = "https"
    port = 443
  }]
  instance_template = tostring(module.instance_template["dynatrace"].self_link)
  hostname          = "dynatrace-instance"
}

# {^|^

# hostname          = "dynatrace-tcp-passthrough-xlb-mig"
# target_pools      = ["${module.gce-lb-fr.target_pool}"]
# ssh_source_ranges = ["0.0.0.0/0"]
# }


resource "google_compute_health_check" "default" {
  project             = var.config.project
  name                = "dynatrace-tcp-proxy-health-check"
  timeout_sec         = 3
  check_interval_sec  = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2
  tcp_health_check {
    port = "443"
  }
}


module "gce-ilb" {
  source  = "GoogleCloudPlatform/lb-internal/google"
  version = "5.1.0"
  region  = var.config.region
  project = var.config.project
  name    = "dynatrace-lb"
  ports   = ["443"]
  # health_check = local.health_check
  health_check = google_compute_health_check.default
  source_tags  = ["allow-group1"]
  target_tags  = ["allow-group2"]
  backends = [
  { group = module.managed_instance_group.instance_group, description = "", failover = false }]
}

locals {
  health_check = {
    type                = "tcp"
    check_interval_sec  = 300
    healthy_threshold   = 2
    timeout_sec         = 5
    unhealthy_threshold = 2
    response            = ""
    proxy_header        = "NONE"
    port                = 443
    port_name           = "health-check-port"
    request             = ""
    request_path        = "/"
    host                = "1.2.3.4"
    enable_log          = false
  }
}

