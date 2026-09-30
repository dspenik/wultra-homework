#!/usr/bin/env bash
# One-time creation of the Storage Account holding the Terraform state.
# Writes infra/terraform/backend.hcl. Safe to re-run.
set -euo pipefail

LOCATION="${LOCATION:-westeurope}"
RESOURCE_GROUP="${STATE_RESOURCE_GROUP:-rg-powerauth-tfstate}"
CONTAINER="tfstate"
STATE_KEY="${STATE_KEY:-powerauth-dev.tfstate}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
az role assignment create --assignee "$(az ad signed-in-user show --query id --output tsv)" \
  --role "Storage Blob Data Contributor" --scope "$scope" --output none

# The role assignment takes a while to propagate
for attempt in $(seq 1 12); do
  if az storage container create --name "$CONTAINER" --account-name "$account" --auth-mode login --output none 2>/dev/null; then
    break
  fi
  [[ "$attempt" -eq 12 ]] && { echo "Container creation failed, re-run the script" >&2; exit 1; }
  sleep 10
done

cat > "$ROOT/infra/terraform/backend.hcl" <<EOF
resource_group_name  = "$RESOURCE_GROUP"
storage_account_name = "$account"
container_name       = "$CONTAINER"
key                  = "$STATE_KEY"
use_azuread_auth     = true
EOF

echo "Wrote infra/terraform/backend.hcl (storage account: $account)"
