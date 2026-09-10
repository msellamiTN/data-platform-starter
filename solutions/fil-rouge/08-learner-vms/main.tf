# ============================================================
# main.tf — Learner Windows VMs
# Provisions one Windows VM per learner with RDP access via
# public IP + NSG, Custom Script Extension for bootstrap, and
# auto-shutdown schedule.
# ============================================================

# ------------------------------------------------------------------
# Locals — derived names + learner map (mirrors 01-snowflake-learners)
# ------------------------------------------------------------------
locals {
  vnet_name   = "${var.project_name}-learner-vnet"
  subnet_name = "${var.project_name}-learner-subnet"
  nsg_name    = "${var.project_name}-learner-nsg"
  vm_prefix   = "${var.project_name}-learner"

  learners = [
    for i in range(1, var.learner_count + 1) : {
      index    = i
      prefix   = format("APP%02d", i)
      username = replace(var.learner_username_pattern, "{i}", format("%02d", i))
      password = replace(var.learner_password_pattern, "{i}", format("%02d", i))
      vm_size  = lookup(var.vm_size_overrides, tostring(i), var.vm_size)
    }
  ]

  shared_env_content = <<-EOT
    SNOWFLAKE_ORGANIZATION=${var.snowflake_organization}
    SNOWFLAKE_ACCOUNT=${var.snowflake_account}
    SNOWFLAKE_USER=${var.snowflake_user}
    SNOWFLAKE_ROLE=${var.snowflake_role}
    SNOWFLAKE_WAREHOUSE=${var.snowflake_warehouse}
    SNOWFLAKE_DATABASE=${var.snowflake_database}
    SNOWFLAKE_SCHEMA=${var.snowflake_schema}
    AZURE_SUBSCRIPTION_ID=${var.arm_subscription_id}
    AZURE_TENANT_ID=${var.azure_tenant_id}
    KEY_VAULT_NAME=${var.key_vault_name}
    LEARNER_COUNT=${var.learner_count}
  EOT
}

# ------------------------------------------------------------------
# Shared resource group
# ------------------------------------------------------------------
resource "azurerm_resource_group" "learner_vms" {
  name     = var.resource_group_name
  location = var.azure_location
}

# ------------------------------------------------------------------
# VNet + Subnet
# ------------------------------------------------------------------
resource "azurerm_virtual_network" "learner_vms" {
  name                = local.vnet_name
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.learner_vms.location
  resource_group_name = azurerm_resource_group.learner_vms.name
}

resource "azurerm_subnet" "learner_vms" {
  name                 = local.subnet_name
  resource_group_name  = azurerm_resource_group.learner_vms.name
  virtual_network_name = azurerm_virtual_network.learner_vms.name
  address_prefixes     = var.subnet_address_prefixes
}

# ------------------------------------------------------------------
# NSG — restrict RDP to instructor IP(s)
# ------------------------------------------------------------------
resource "azurerm_network_security_group" "learner_vms" {
  name                = local.nsg_name
  location            = azurerm_resource_group.learner_vms.location
  resource_group_name = azurerm_resource_group.learner_vms.name

  dynamic "security_rule" {
    for_each = toset(var.rdp_allowed_source_prefixes)
    content {
      name                       = "Allow-RDP-${replace(replace(security_rule.key, "/", "-"), "*", "Any")}"
      priority                   = 100 + index(var.rdp_allowed_source_prefixes, security_rule.key)
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      source_address_prefix      = security_rule.key
      destination_port_range     = "3389"
      destination_address_prefix = "*"
    }
  }

  security_rule {
    name                       = "Deny-All-Other-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "learner_vms" {
  subnet_id                 = azurerm_subnet.learner_vms.id
  network_security_group_id = azurerm_network_security_group.learner_vms.id
}

# ------------------------------------------------------------------
# Per-learner VM resources
# ------------------------------------------------------------------
resource "azurerm_public_ip" "learner_vm" {
  count               = var.learner_count
  name                = "${local.vm_prefix}-${format("%02d", count.index + 1)}-pip"
  location            = azurerm_resource_group.learner_vms.location
  resource_group_name = azurerm_resource_group.learner_vms.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "learner_vm" {
  count               = var.learner_count
  name                = "${local.vm_prefix}-${format("%02d", count.index + 1)}-nic"
  location            = azurerm_resource_group.learner_vms.location
  resource_group_name = azurerm_resource_group.learner_vms.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.learner_vms.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.learner_vm[count.index].id
  }
}

resource "azurerm_windows_virtual_machine" "learner_vm" {
  count               = var.learner_count
  name                = "${local.vm_prefix}-${format("%02d", count.index + 1)}"
  location            = azurerm_resource_group.learner_vms.location
  resource_group_name = azurerm_resource_group.learner_vms.name
  size                = local.learners[count.index].vm_size
  computer_name       = "learner-${format("%02d", count.index + 1)}"
  admin_username      = local.learners[count.index].username
  admin_password      = local.learners[count.index].password
  network_interface_ids = [
    azurerm_network_interface.learner_vm[count.index].id,
  ]

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "microsoftwindowsdesktop"
    offer     = "windows-11"
    sku       = var.windows_sku
    version   = "latest"
  }

  secure_boot_enabled = true
  vtpm_enabled        = true

  license_type = "Windows_Client"

  patch_mode = "AutomaticByOS"

  automatic_updates_enabled = true

  boot_diagnostics {
    storage_account_uri = null
  }

  tags = {
    Environment = "training"
    Module      = "08-learner-vms"
    Learner     = local.learners[count.index].prefix
  }
}

# ------------------------------------------------------------------
# Key Vault access — grant each VM's managed identity read access
# so the bootstrap script can fetch SP credentials + Snowflake PAT
# without interactive AAD login.
# ------------------------------------------------------------------
data "azurerm_key_vault" "secrets" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group_name
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  count                = var.learner_count
  scope                = data.azurerm_key_vault.secrets.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_windows_virtual_machine.learner_vm[count.index].identity[0].principal_id
}

# ------------------------------------------------------------------
# Auto-shutdown schedule (per VM) — uses azurerm_dev_test_global_vm_shutdown_schedule
# ------------------------------------------------------------------
resource "azurerm_dev_test_global_vm_shutdown_schedule" "learner_vm" {
  count                 = var.auto_shutdown_enabled ? var.learner_count : 0
  virtual_machine_id    = azurerm_windows_virtual_machine.learner_vm[count.index].id
  location              = azurerm_resource_group.learner_vms.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone

  notification_settings {
    enabled = false
  }
}

# ------------------------------------------------------------------
# Run Command — bootstrap each VM
# Uses azurerm_virtual_machine_run_command which delivers the script
# via the Azure API (no 8191-char command line limit).
# ------------------------------------------------------------------
resource "azurerm_virtual_machine_run_command" "bootstrap" {
  count              = var.learner_count
  name               = "bootstrap-${format("%02d", count.index + 1)}"
  location           = azurerm_resource_group.learner_vms.location
  virtual_machine_id = azurerm_windows_virtual_machine.learner_vm[count.index].id

  source {
    script = templatefile("${path.module}/bootstrap-vm.ps1.tpl", {
      learner_prefix         = local.learners[count.index].prefix
      repo_url               = var.repo_url
      repo_local_path        = var.repo_local_path
      install_root           = var.install_root
      shared_env_content     = local.shared_env_content
      key_vault_name         = var.key_vault_name
      snowflake_organization = var.snowflake_organization
      snowflake_account      = var.snowflake_account
      snowflake_user         = var.snowflake_user
      snowflake_role         = var.snowflake_role
    })
  }

  depends_on = [
    azurerm_windows_virtual_machine.learner_vm,
  ]
}
