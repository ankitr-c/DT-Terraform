output "servers" {
  value = local.servers
}

output "rule" {
  value = google_compute_firewall.rule["dynatrace"].name
}




# for internal ip address
# output "addresses" {
#   value = {
#     for idx, instance in module.compute_instance : # Iterate over each instance in the compute_instance module
#     "server-${idx}" => [
#       for instance_details in instance.instances_details : # Iterate over each instance's details
#       {
#         ip_address = instance_details.network_interface[0].network_ip
#         # instance_id = instance_details.id # Access the instance_id attribute
#         # zone        = instance_details.zone
#         # Add other attributes as needed
#       }
#     ]
#   }
# }


# # for external ip address:
# output "addresses" {
#   value = {
#     for idx, instance in module.compute_instance : # Iterate over each instance in the compute_instance module
#     "server-${idx}" => [
#       for instance_details in instance.instances_details : # Iterate over each instance's details
#       {
#         ip_address = instance_details.network_interface[0].access_config.nat_ip
#         # instance_id = instance_details.id # Access the instance_id attribute
#         # zone        = instance_details.zone
#         # Add other attributes as needed
#       }
#     ]
#   }
# }



