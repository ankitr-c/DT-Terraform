resource "google_compute_region_instance_group_manager" "mig" {
  name    = "dynatrace-mig"
  project = var.config.project
  region  = var.config.region
  version {
    instance_template = module.instance_template["dynatrace"].self_link
    name              = "primary"
  }
  base_instance_name = "dynatrace-vm"
  target_size        = 2
}


resource "google_compute_region_health_check" "default" {
  name    = "dynatrace-hc"
  project = var.config.project
  region  = var.config.region
  http_health_check {
    port = "443"
  }
}

resource "google_compute_region_backend_service" "default" {
  name                  = "dynatrace-be"
  project               = var.config.project
  region                = var.config.region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.default.self_link]
  backend {
    group          = google_compute_region_instance_group_manager.mig.instance_group
    balancing_mode = "CONNECTION"
  }
}


resource "google_compute_forwarding_rule" "google_compute_forwarding_rule" {
  name                  = "dynatrace-forwarding-rule"
  backend_service       = google_compute_region_backend_service.default.self_link
  region                = var.config.region
  project               = var.config.project
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  all_ports             = true
}

# {^|^
# allow_global_access   = true
# network               = "default" #google_compute_network.ilb_network.id
# all_ports             = true
# subnetwork            = google_compute_subnetwork.ilb_subnet.id
# }
