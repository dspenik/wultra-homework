data "azurerm_client_config" "current" {}

# Suffix for globally unique names (Key Vault, PostgreSQL server)
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  name = "${var.project}-${var.environment}"
  # Argo CD Applications of this environment
  gitops_apps_path = "gitops/apps/${var.environment}"
  tags = merge(var.tags, {
    project     = var.project
    environment = var.environment
    managed-by  = "terraform"
  })
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}
