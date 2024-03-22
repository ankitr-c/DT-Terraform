
output "server_key_mapping" {
  value = local.server_key_mapping
}



# # for internal ip address
# output "addresses" {
#   value = {
#     for idx, instance in module.compute_instance : # Iterate over each instance in the compute_instance module
#     "server-${idx}" => [
#       for instance_details in instance.instances_details : # Iterate over each instance's details
#       instance_details.network_interface[0].network_ip
#     ]
#   }
# }

