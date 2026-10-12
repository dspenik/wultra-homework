#!/usr/bin/env bash
# Creates the Storage Account for the Terraform state and writes infra/terraform/backend.hcl.
# Safe to re-run.
set -euo pipefail

location="${LOCATION:-austriaeast}"
rg="rg-powerauth-tfstate"
container="tfstate"
root="$(cd "$(dirname "$0")/.." && pwd)"

# Not registered on a fresh subscription
az provider register --namespace Microsoft.Storage --wait

az group create --name "$rg" --location "$location" --output none

# The name must be globally unique, so a re-run looks up the existing account
account="$(az storage account list --resource-group "$rg" --query "[0].name" --output tsv)"
if [[ -z "$account" ]]; then
  account="stpowerauthtf$(openssl rand -hex 4)"
  az storage account create --name "$account" --resource-group "$rg" --location "$location" \
    --sku Standard_LRS --min-tls-version TLS1_2 \
    --allow-blob-public-access false --allow-shared-key-access false --output none
fi

az storage account blob-service-properties update --account-name "$account" --resource-group "$rg" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30 --output none

# Shared keys are disabled, the state is accessed with Entra ID.
# Object ID instead of the user name: guest users cannot look themselves up in Microsoft Graph.
az role assignment create --role "Storage Blob Data Contributor" \
  --assignee-object-id "$(az ad signed-in-user show --query id --output tsv)" --assignee-principal-type User \
  --scope "$(az storage account show --name "$account" --resource-group "$rg" --query id --output tsv)" --output none

# The role assignment takes up to a few minutes to propagate
for _ in {1..12}; do
  az storage container create --name "$container" --account-name "$account" --auth-mode login --output none 2>/dev/null && break
  sleep 10
done
az storage container create --name "$container" --account-name "$account" --auth-mode login --output none

cat > "$root/infra/terraform/backend.hcl" <<EOF
resource_group_name  = "$rg"
storage_account_name = "$account"
container_name       = "$container"
use_azuread_auth     = true
EOF
echo "Wrote infra/terraform/backend.hcl ($account)"
