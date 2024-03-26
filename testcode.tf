# locals {
#   hosts = [
#     ["server1_ip", "user1", "ssh_key1", "group1"],
#     ["server2_ip", "user2", "ssh_key2", "group2"],
#     ["server3_ip", "user3", "ssh_key3", "group1"],
#   ]
# }

# # Create Ansible hosts and groups based on the local hosts variable
# resource "ansible_host" "hosts" {
#   for_each = { for idx, host in local.hosts : idx => host[0] }

#   name = each.value
#   groups = [local.hosts[each.key][3]]

#   variables = {
#     ansible_user              = local.hosts[each.key][1]
#     ansible_ssh_private_key   = local.hosts[each.key][2]
#   }
# }

# resource "ansible_group" "groups" {
#   for_each = distinct([for host in local.hosts : host[3]])

#   name = each.value
# }

# # Define the playbook resource and execute it on the hosts
# resource "ansible_playbook" "playbook" {
#   playbook = "playbook.yml"

#   dynamic "hosts" {
#     for_each = local.hosts

#     content {
#       name = hosts.value[0]
#       groups = [hosts.value[3]]
#     }
#   }

#   extra_vars = {
#     var_a = "Some variable"
#     var_b = "Another variable"
#   }
# }
