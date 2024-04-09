# regional proxy lb using mig and regional_proxy_lb

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
  hostname          = "dynatrace-tcp-proxy-xlb-mig"
  # target_pools      = ["${module.gce-lb-fr.target_pool}"]
  # ssh_source_ranges = ["0.0.0.0/0"]
}


module "regional_proxy_lb" {
  source                   = "terraform-google-modules/lb/google//modules/regional_proxy_lb"
  version                  = "4.1.0"
  name                     = "dynatrace-lb"
  region                   = var.config.region
  project                  = var.config.project
  network_project          = var.config.project
  network                  = "default"
  target_tags              = ["dummy-tag"]
  port_front_end           = 443
  create_proxy_only_subnet = true
  proxy_only_subnet_cidr   = "192.168.5.0/24"
  create_firewall_rules    = true
  health_check = {
    description        = "Health check to determine whether instances are responsive and able to do work"
    check_interval_sec = 10
    tcp_health_check = {
      port_specification = "USE_SERVING_PORT"
    }
  }


  backend = {
    port             = 80
    port_name        = "tcp"
    backend_type     = "INSTANCE_GROUP"
    session_affinity = "CLIENT_IP"
    timeout_sec      = 50 #default 30

    log_config = {
      enable      = true
      sample_rate = 1
    }

    groups = [{
      group                        = module.managed_instance_group.instance_group
      balancing_mode               = "UTILIZATION"
      capacity_scaler              = 0.5
      max_connections_per_instance = 1000
      max_rate_per_instance        = null
      max_utilization              = 0.7
    }]
  }
}
