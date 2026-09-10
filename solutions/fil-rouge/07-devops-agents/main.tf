# ─── Resource Group ───

resource "azurerm_resource_group" "agents" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Purpose     = "DevOpsAgents"
    ManagedBy   = "Terraform"
    Project     = var.project_name
    Environment = "shared"
  }
}

# ─── Boot diagnostics storage account ───

resource "azurerm_storage_account" "bootdiag" {
  name                     = var.boot_diag_storage_name
  resource_group_name      = azurerm_resource_group.agents.name
  location                 = azurerm_resource_group.agents.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    Purpose   = "BootDiagnostics"
    ManagedBy = "Terraform"
    Project   = var.project_name
  }
}

# ─── Networking ───

resource "azurerm_virtual_network" "agents" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.agents.location
  resource_group_name = azurerm_resource_group.agents.name

  tags = {
    Purpose   = "DevOpsAgents"
    ManagedBy = "Terraform"
    Project   = var.project_name
  }
}

resource "azurerm_subnet" "agents" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.agents.name
  virtual_network_name = azurerm_virtual_network.agents.name
  address_prefixes     = var.subnet_address_prefixes
}

resource "azurerm_network_security_group" "agents" {
  name                = "${var.vm_name}-nsg"
  location            = azurerm_resource_group.agents.location
  resource_group_name = azurerm_resource_group.agents.name

  security_rule {
    name                       = "SSH"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Purpose   = "DevOpsAgents"
    ManagedBy = "Terraform"
    Project   = var.project_name
  }
}

resource "azurerm_subnet_network_security_group_association" "agents" {
  subnet_id                 = azurerm_subnet.agents.id
  network_security_group_id = azurerm_network_security_group.agents.id
}

resource "azurerm_public_ip" "agent" {
  name                = "${var.vm_name}-ip"
  location            = azurerm_resource_group.agents.location
  resource_group_name = azurerm_resource_group.agents.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [var.availability_zone]

  tags = {
    Purpose   = "DevOpsAgents"
    ManagedBy = "Terraform"
    Project   = var.project_name
  }
}

resource "azurerm_network_interface" "agent" {
  name                           = "${var.vm_name}605"
  location                       = azurerm_resource_group.agents.location
  resource_group_name            = azurerm_resource_group.agents.name
  accelerated_networking_enabled = true

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.agents.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.agent.id
  }

  tags = {
    Purpose   = "DevOpsAgents"
    ManagedBy = "Terraform"
    Project   = var.project_name
  }
}

# ─── Linux Virtual Machine (Ubuntu 24.04 LTS, Trusted Launch) ───

resource "azurerm_linux_virtual_machine" "devops_agent" {
  name                  = var.vm_name
  resource_group_name   = azurerm_resource_group.agents.name
  location              = azurerm_resource_group.agents.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  zone                  = var.availability_zone
  network_interface_ids = [azurerm_network_interface.agent.id]

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  disk_controller_type = "NVMe"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  secure_boot_enabled = true
  vtpm_enabled        = true

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.bootdiag.primary_blob_endpoint
  }

  custom_data = nonsensitive(base64encode(templatefile("${path.module}/cloud-init.yml.tpl", {
    azuredevops_org_url = var.azuredevops_org_url
    azuredevops_pat     = nonsensitive(var.azuredevops_pat)
    agent_pool_name     = var.agent_pool_name
    agent_name          = var.agent_name
    agent_version       = var.agent_version
  })))


  tags = {
    Environment = "DevOps"
    ManagedBy   = "Terraform"
    Project     = var.project_name
  }
}


# ─── Azure DevOps Agent Pool ───

resource "azuredevops_agent_pool" "agents" {
  name           = var.agent_pool_name
  auto_provision = false
  auto_update    = true

  lifecycle {
    ignore_changes = all
  }
}

data "azuredevops_project" "main" {
  name = "terraform-snowflake"
}

resource "azuredevops_agent_queue" "agents" {
  project_id    = data.azuredevops_project.main.id
  agent_pool_id = azuredevops_agent_pool.agents.id
}

# ─── Auto-shutdown schedule (daily 19:00 CET) ───

resource "azurerm_dev_test_global_vm_shutdown_schedule" "agent" {
  virtual_machine_id    = azurerm_linux_virtual_machine.devops_agent.id
  location              = azurerm_resource_group.agents.location
  enabled               = true
  daily_recurrence_time = "1900"
  timezone              = "Central European Standard Time"

  notification_settings {
    enabled = false
  }
}