
# resource "google_compute_instance_group" "webservers" {
#   project   = var.config.project
#   name      = "dynatrace-servers-instance-group"
#   instances = local.vm_instances
#   named_port {
#     name = "https"
#     port = "443"
#   }
#   zone = "us-west1-a"
# }

# locals {
#   health_check = {
#     type                = "http"
#     check_interval_sec  = 1
#     healthy_threshold   = 2
#     timeout_sec         = 1
#     unhealthy_threshold = 5
#     response            = ""
#     proxy_header        = "NONE"
#     port                = 443
#     port_name           = "health-check-port"
#     request             = ""
#     request_path        = "/"
#     host                = "1.2.3.4"
#     enable_log          = false
#   }
# }


# module "gce-ilb" {
#   project      = var.config.project
#   source       = "GoogleCloudPlatform/lb-internal/google"
#   version      = "5.1.0"
#   region       = var.config.region
#   name         = "group2-ilb"
#   ports        = ["80"]
#   health_check = local.health_check
#   source_tags  = ["allow-group1"]
#   target_tags  = ["allow-group2", "allow-group3"]
#   backends = [
#     { group = google_compute_instance_group.webservers.self_link, description = "", failover = false }
#   ]
# }



# module "mig1" {
#   source            = "GoogleCloudPlatform/managed-instance-group/google"
#   version           = "1.1.14"
#   region            = var.region
#   zone              = var.zone
#   name              = "group1"
#   size              = 2
#   service_port      = 80
#   service_port_name = "http"
#   http_health_check = false
#   target_pools      = ["${module.gce-lb-fr.target_pool}"]
#   target_tags       = ["allow-service1"]
#   ssh_source_ranges = ["0.0.0.0/0"]
# }
