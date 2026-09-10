# â”€â”€â”€ Azure location & naming â”€â”€â”€

variable "location" {
  type        = string
  description = "Azure region for the DevOps agent VM"
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group for the agent VM"
  default     = "rg-data2ai-agents-eus"
}

variable "project_name" {
  type        = string
  description = "Prefix for naming resources"
  default     = "data2ai-tf-training"
}

# â”€â”€â”€ VM configuration â”€â”€â”€

variable "vm_name" {
  type        = string
  description = "Name of the Linux Virtual Machine"
  default     = "agent-terraform"
}

variable "vm_size" {
  type        = string
  description = "VM size for the DevOps agent"
  default     = "Standard_D2as_v7"
}

variable "availability_zone" {
  type        = number
  description = "Availability zone for the VM"
  default     = 1
}

variable "admin_username" {
  type        = string
  description = "Admin username for SSH access"
  default     = "azureuser"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for authentication"
  sensitive   = true
  default     = ""
}

# â”€â”€â”€ Boot diagnostics â”€â”€â”€

variable "boot_diag_storage_name" {
  type        = string
  description = "Storage account name for boot diagnostics (3-24 chars, lowercase)"
  default     = "stadata2aiagenteus001"
}

# â”€â”€â”€ Networking â”€â”€â”€

variable "vnet_name" {
  type        = string
  description = "Virtual network name"
  default     = "vnet-eastus-1"
}

variable "vnet_address_space" {
  type        = list(string)
  description = "Address space for the VNet"
  default     = ["10.20.0.0/16"]
}

variable "subnet_name" {
  type        = string
  description = "Subnet name"
  default     = "snet-eastus-1"
}

variable "subnet_address_prefixes" {
  type        = list(string)
  description = "Subnet address prefixes"
  default     = ["10.20.1.0/24"]
}

# â”€â”€â”€ Azure DevOps configuration â”€â”€â”€

variable "azuredevops_org_url" {
  type        = string
  description = "Azure DevOps organization URL"
  default     = "https://dev.azure.com/mokhtarsellami0877"
}

variable "azuredevops_pat" {
  type        = string
  description = "Azure DevOps Personal Access Token"
  sensitive   = true
}

variable "agent_pool_name" {
  type        = string
  description = "Name of the Azure DevOps agent pool"
  default     = "azure-vm-agents"
}

variable "agent_name" {
  type        = string
  description = "Name of the agent as it appears in Azure DevOps"
  default     = "linux-vm-agent"
}

variable "agent_version" {
  type        = string
  description = "Version of the Azure DevOps agent to install"
  default     = "3.246.0"
}

variable "arm_subscription_id" {
  type        = string
  description = "Azure subscription ID for the azurerm provider"
  default     = ""
}
