#!/usr/bin/env bash
# Writes the Terraform outputs into the Argo CD Application values. Needs mikefarah yq v4.
set -euo pipefail

export RANGES="${1:?usage: $0 <allowed CIDR>[,<CIDR>...]}"

root="$(cd "$(dirname "$0")/.." && pwd)"
tf() { terraform -chdir="$root/infra/terraform" output -raw "$1"; }
app="$root/$(tf gitops_apps_path)/powerauth-test-server.yaml"

export REPO_URL REVISION PG_HOST DB_NAME KV_NAME TENANT_ID CLIENT_ID
REPO_URL="$(tf gitops_repo_url)"
REVISION="$(tf gitops_target_revision)"
PG_HOST="$(tf postgres_fqdn)"
DB_NAME="$(tf postgres_database)"
KV_NAME="$(tf key_vault_name)"
TENANT_ID="$(tf tenant_id)"
CLIENT_ID="$(tf workload_identity_client_id)"

yq -i '
  .spec.source.repoURL = strenv(REPO_URL) |
  .spec.source.targetRevision = strenv(REVISION) |
  .spec.source.helm.valuesObject.database.host = strenv(PG_HOST) |
  .spec.source.helm.valuesObject.database.name = strenv(DB_NAME) |
  .spec.source.helm.valuesObject.secrets.keyvault.name = strenv(KV_NAME) |
  .spec.source.helm.valuesObject.secrets.keyvault.tenantId = strenv(TENANT_ID) |
  .spec.source.helm.valuesObject.secrets.keyvault.clientId = strenv(CLIENT_ID) |
  .spec.source.helm.valuesObject.service.loadBalancerSourceRanges = (strenv(RANGES) | split(","))
' "$app"

git -C "$root" diff -- "$app"
