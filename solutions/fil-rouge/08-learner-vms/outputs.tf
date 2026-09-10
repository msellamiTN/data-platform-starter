# ============================================================
# outputs.tf — Learner Windows VMs
# ============================================================

output "learner_vm_ips" {
  description = "Public IP addresses for each learner VM (RDP target)."
  value = {
    for i in range(0, var.learner_count) :
    local.learners[i].prefix => azurerm_public_ip.learner_vm[i].ip_address
  }
}

output "learner_vm_fqdns" {
  description = "FQDN for each learner VM (if configured)."
  value = {
    for i in range(0, var.learner_count) :
    local.learners[i].prefix => azurerm_public_ip.learner_vm[i].fqdn
  }
}

output "learner_rdp_info" {
  description = "Formatted RDP connection info per learner (IP + credentials)."
  sensitive   = true
  value = [
    for i in range(0, var.learner_count) : {
      learner    = local.learners[i].prefix
      rdp_target = azurerm_public_ip.learner_vm[i].ip_address
      username   = local.learners[i].username
      password   = local.learners[i].password
    }
  ]
}

output "resource_group_name" {
  description = "Resource group containing all learner VM resources."
  value       = azurerm_resource_group.learner_vms.name
}

output "vnet_name" {
  description = "Virtual network name for learner VMs."
  value       = azurerm_virtual_network.learner_vms.name
}

output "nsg_name" {
  description = "Network security group name for learner VMs."
  value       = azurerm_network_security_group.learner_vms.name
}
