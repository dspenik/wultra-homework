# Ephemeral: the password is passed to write-only attributes and never stored in the state.
# Alphanumeric only, the init image passes it to Liquibase unquoted.
ephemeral "random_password" "db" {
  length      = 32
  special     = false
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                              = "psql-${local.name}-${random_string.suffix.result}"
  location                          = azurerm_resource_group.main.location
  resource_group_name               = azurerm_resource_group.main.name
  version                           = var.postgres_version
  sku_name                          = var.postgres_sku
  storage_mb                        = var.postgres_storage_mb
  backup_retention_days             = 7
  delegated_subnet_id               = azurerm_subnet.postgres.id
  private_dns_zone_id               = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled     = false
  administrator_login               = var.postgres_admin_login
  administrator_password_wo         = ephemeral.random_password.db.result
  administrator_password_wo_version = var.db_password_version
  tags                              = local.tags

  lifecycle {
    # Azure picks the zone when none is requested
    ignore_changes = [zone]
  }

  # Secret first: if the Key Vault write fails, the server is not created with a password nobody knows
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.postgres,
    azurerm_key_vault_secret.db_password,
  ]
}

resource "azurerm_postgresql_flexible_server_database" "powerauth" {
  name      = "powerauth"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
