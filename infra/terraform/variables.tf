variable "project" {
  description = "Short project name used in resource names"
  type        = string
  default     = "powerauth"
}

variable "environment" {
  description = "Environment name used in resource names and tags"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "admin_ip_ranges" {
  description = "Public CIDRs of operators allowed to reach the AKS API server and Key Vault, e.g. 203.0.113.10/32"
  type        = list(string)
}

variable "vnet_address_space" {
  description = "VNet address space; must not overlap the AKS pod (10.244.0.0/16) and service (10.0.0.0/16) CIDRs"
  type        = string
  default     = "10.10.0.0/16"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes minor version"
  type        = string
  default     = "1.36"
}

variable "node_vm_size" {
  description = "VM size of the AKS system node pool (B-series is not supported for system pools)"
  type        = string
  default     = "Standard_D2as_v5"
}

variable "node_count" {
  description = "Number of AKS nodes"
  type        = number
  default     = 1
}

variable "postgres_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "18"
}

variable "postgres_sku" {
  description = "PostgreSQL Flexible Server SKU"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "PostgreSQL storage size in MB"
  type        = number
  default     = 32768
}

variable "postgres_admin_login" {
  description = "PostgreSQL administrator login"
  type        = string
  default     = "powerauth"
}

variable "db_password_version" {
  description = "Increment to rotate the generated DB password"
  type        = number
  default     = 1
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version"
  type        = string
  default     = "10.9.4"
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps Helm chart version"
  type        = string
  default     = "2.0.6"
}

variable "gitops_repo_url" {
  description = "Git repository watched by Argo CD"
  type        = string
}

variable "gitops_target_revision" {
  description = "Git branch or tag watched by Argo CD"
  type        = string
  default     = "main"
}

variable "app_namespace" {
  description = "Kubernetes namespace of the application"
  type        = string
  default     = "powerauth"
}

variable "app_service_account" {
  description = "Kubernetes ServiceAccount of the application (must match the Helm chart)"
  type        = string
  default     = "powerauth-test-server"
}
