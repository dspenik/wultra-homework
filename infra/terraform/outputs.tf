output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "aks_get_credentials" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

# Values consumed by scripts/gitops-values.sh
output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "workload_identity_client_id" {
  value = azurerm_user_assigned_identity.app.client_id
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgres_database" {
  value = azurerm_postgresql_flexible_server_database.powerauth.name
}

output "gitops_repo_url" {
  value = var.gitops_repo_url
}

output "gitops_target_revision" {
  value = var.gitops_target_revision
}
