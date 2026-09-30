# User-assigned control plane identity, so the subnet permission exists before the cluster is created
resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks-${local.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "aks_subnet" {
  scope                = azurerm_subnet.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_kubernetes_cluster" "main" {
  name                              = "aks-${local.name}"
  location                          = azurerm_resource_group.main.location
  resource_group_name               = azurerm_resource_group.main.name
  dns_prefix                        = local.name
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = "Free"
  automatic_upgrade_channel         = "patch"
  node_os_upgrade_channel           = "NodeImage"
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  role_based_access_control_enabled = true
  tags                              = local.tags

  api_server_access_profile {
    authorized_ip_ranges = var.admin_ip_ranges
  }

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    node_count                  = var.node_count
    os_disk_size_gb             = 64
    vnet_subnet_id              = azurerm_subnet.aks.id
    temporary_name_for_rotation = "systemtmp"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  # Node auto-provisioning (Karpenter) off, the single node pool above is enough
  node_provisioning_profile {
    mode = "Manual"
  }

  key_vault_secrets_provider {
    # Keeps the synced Kubernetes Secret current after a password rotation
    secret_rotation_enabled = true
  }

  depends_on = [azurerm_role_assignment.aks_subnet]
}
