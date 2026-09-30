resource "azurerm_key_vault" "main" {
  name                       = "kv-${local.name}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  tags                       = local.tags

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    ip_rules                   = var.admin_ip_ranges
    virtual_network_subnet_ids = [azurerm_subnet.aks.id]
  }
}

resource "azurerm_role_assignment" "kv_terraform" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# RBAC assignments take a while to propagate to the Key Vault data plane
resource "time_sleep" "kv_rbac" {
  create_duration = "60s"
  depends_on      = [azurerm_role_assignment.kv_terraform]
}

resource "azurerm_key_vault_secret" "db_username" {
  name         = "db-username"
  value        = var.postgres_admin_login
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [time_sleep.kv_rbac]
}

resource "azurerm_key_vault_secret" "db_password" {
  name             = "db-password"
  value_wo         = ephemeral.random_password.db.result
  value_wo_version = var.db_password_version
  key_vault_id     = azurerm_key_vault.main.id
  depends_on       = [time_sleep.kv_rbac]
}
