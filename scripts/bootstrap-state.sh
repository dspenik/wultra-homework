#!/usr/bin/env bash
# One-time creation of the Storage Account holding the Terraform state.
# Writes infra/terraform/backend.hcl; the state key (one per environment) is passed at terraform init. Safe to re-run.
set -euo pipefail

LOCATION="${LOCATION:-austriaeast}"
RESOURCE_GROUP="${STATE_RESOURCE_GROUP:-rg-powerauth-tfstate}"
CONTAINER="tfstate"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Fresh subscriptions have no resource providers registered
az provider register --namespace Microsoft.Storage --wait

az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

# Reuse the account from a previous run; its name must be globally unique
account="${STATE_STORAGE_ACCOUNT:-$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv)}"
if [[ -z "$account" ]]; then
  account="stpowerauthtf$(openssl rand -hex 4)"
  az storage account create --name "$account" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" \
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
    --allow-blob-public-access false --allow-shared-key-access false --output none
fi

az storage account blob-service-properties update --account-name "$account" --resource-group "$RESOURCE_GROUP" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30 --output none

# Entra ID auth only (shared keys disabled)
scope="$(az storage account show --name "$account" --resource-group "$RESOURCE_GROUP" --query id --output tsv)"
# Object ID + principal type: guest users cannot query Microsoft Graph to resolve the assignee
az role assignment create --assignee-object-id "$(az ad signed-in-user show --query id --output tsv)" \
  --assignee-principal-type User --role "Storage Blob Data Contributor" --scope "$scope" --output none

# The role assignment takes a while to propagate
for attempt in $(seq 1 12); do
  if error="$(az storage container create --name "$CONTAINER" --account-name "$account" --auth-mode login --output none 2>&1)"; then
    break
  fi
  [[ "$attempt" -eq 12 ]] && { echo "Container creation failed: $error" >&2; exit 1; }
  sleep 10
done

cat > "$ROOT/infra/terraform/backend.hcl" <<EOF
resource_group_name  = "$RESOURCE_GROUP"
storage_account_name = "$account"
container_name       = "$CONTAINER"
use_azuread_auth     = true
EOF

echo "Wrote infra/terraform/backend.hcl (storage account: $account)"
