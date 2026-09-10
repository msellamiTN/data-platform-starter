output "vm_name" {
  value       = azurerm_linux_virtual_machine.devops_agent.name
  description = "Name of the DevOps agent VM"
}

output "vm_public_ip" {
  value       = azurerm_public_ip.agent.ip_address
  description = "Public IP address of the DevOps agent VM"
}

output "vm_private_ip" {
  value       = azurerm_network_interface.agent.private_ip_address
  description = "Private IP address of the DevOps agent VM"
}

output "resource_group_name" {
  value       = azurerm_resource_group.agents.name
  description = "Resource group containing the agent VM"
}

output "agent_pool_name" {
  value       = azuredevops_agent_pool.agents.name
  description = "Azure DevOps agent pool name"
}

output "agent_pool_id" {
  value       = azuredevops_agent_pool.agents.id
  description = "Azure DevOps agent pool ID"
}
