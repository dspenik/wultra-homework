output "resource_group_name" {
  description = "Resource group of the environment"
  value       = azurerm_resource_group.main.name
}

output "aks_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_get_credentials" {
  description = "Command that writes the cluster credentials to the local kubeconfig"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

# Values consumed by scripts/gitops-values.sh
output "tenant_id" {
  description = "Microsoft Entra tenant of the workload identity"
  value       = data.azurerm_client_config.current.tenant_id
}

output "key_vault_name" {
  description = "Key Vault holding the DB credentials"
  value       = azurerm_key_vault.main.name
}

output "workload_identity_client_id" {
  description = "Client ID of the application's managed identity"
  value       = azurerm_user_assigned_identity.app.client_id
}

output "postgres_fqdn" {
  description = "Private FQDN of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgres_database" {
  description = "Application database name"
  value       = azurerm_postgresql_flexible_server_database.powerauth.name
}

output "gitops_repo_url" {
  description = "Git repository watched by Argo CD"
  value       = var.gitops_repo_url
}

output "gitops_target_revision" {
  description = "Git revision watched by Argo CD"
  value       = var.gitops_target_revision
}

output "gitops_apps_path" {
  description = "Repository path with the Argo CD Applications of this environment"
  value       = local.gitops_apps_path
}
