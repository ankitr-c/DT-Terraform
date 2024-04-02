#####################PROXY LOAD BALANCER#####################


locals {


  /*
lb_server datastructure looks like:

lb_servers = {
  "dynatrace" = [
    "ID of Instance 1",
    "ID of Instance 2"    
  ]
  "some other server" = [
    "ID of Instance 1",
    "ID of Instance 2"    
  ]
}

*/
  lb_servers = {
    for server_name, vm_info in module.compute_instance :
    server_name => [for instance_details in vm_info.instances_details : instance_details.id]
    if contains(["dynatrace"], server_name)
  }


}


# --------------------Global Forwarding Rule----------------------
resource "google_compute_global_forwarding_rule" "default" {
  project               = var.config.project
  for_each              = local.lb_servers #for all the servers that require lb
  name                  = "${each.key}-tcp-proxy-xlb-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_tcp_proxy.default[each.key].id
}

# --------------------TCP Target Proxy----------------------
resource "google_compute_target_tcp_proxy" "default" {
  for_each        = local.lb_servers #for all the servers that require lb
  project         = var.config.project
  name            = "${each.key}-test-proxy-health-check"
  backend_service = google_compute_backend_service.default[each.key].id
}


# -----------------Global Backend Service-------------------
resource "google_compute_backend_service" "default" {
  project               = var.config.project
  for_each              = local.lb_servers #for all the servers that require lb
  name                  = "${each.key}-tcp-proxy-xlb-backend-service"
  protocol              = "TCP"
  port_name             = "tcp"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.default[each.key].id]
  backend {
    group           = google_compute_instance_group.default[each.key].id
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.70
    capacity_scaler = 1.0
  }
}

# -------------------Global Health Check---------------------
resource "google_compute_health_check" "default" {
  project            = var.config.project
  for_each           = local.lb_servers #for all the servers that require lb
  name               = "${each.key}-tcp-proxy-health-check"
  timeout_sec        = 1
  check_interval_sec = 5

  tcp_health_check {
    port = "443"
  }
}


# -------------Zonal Unmanaged instance Group---------------
# Unamanaged instance group needs zone, it cant be a global resource

resource "google_compute_instance_group" "default" {
  project   = var.config.project
  zone      = "us-west1-a"
  for_each  = local.lb_servers #for all the servers that require lb
  name      = "${each.key}-tcp-proxy-umg"
  instances = each.value #all the instances in that specific server.
  named_port {
    name = "https"
    port = "443"
  }
}

