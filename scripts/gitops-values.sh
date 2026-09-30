#!/usr/bin/env bash
# Copies Terraform outputs into the Argo CD Application values (the Terraform → GitOps hand-off).
# Review and commit the resulting change.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/gitops/apps/powerauth-test-server.yaml"
ALLOWED_SOURCE_RANGES="${ALLOWED_SOURCE_RANGES:?Set ALLOWED_SOURCE_RANGES, e.g. 203.0.113.10/32 (comma separated)}"

outputs="$(terraform -chdir="$ROOT/infra/terraform" output -json)"
out() { jq -er ".$1.value" <<<"$outputs"; }

export REPO_URL REVISION PG_HOST KV_NAME TENANT_ID CLIENT_ID DB_NAME RANGES
REPO_URL="$(out gitops_repo_url)"
REVISION="$(out gitops_target_revision)"
PG_HOST="$(out postgres_fqdn)"
KV_NAME="$(out key_vault_name)"
TENANT_ID="$(out tenant_id)"
CLIENT_ID="$(out workload_identity_client_id)"
DB_NAME="$(out postgres_database)"
RANGES="$ALLOWED_SOURCE_RANGES"

# mikefarah yq v4
yq -i '
  .spec.source.repoURL = strenv(REPO_URL) |
  .spec.source.targetRevision = strenv(REVISION) |
  .spec.source.helm.valuesObject.database.host = strenv(PG_HOST) |
  .spec.source.helm.valuesObject.database.name = strenv(DB_NAME) |
  .spec.source.helm.valuesObject.secrets.keyvault.name = strenv(KV_NAME) |
  .spec.source.helm.valuesObject.secrets.keyvault.tenantId = strenv(TENANT_ID) |
  .spec.source.helm.valuesObject.secrets.keyvault.clientId = strenv(CLIENT_ID) |
  .spec.source.helm.valuesObject.service.loadBalancerSourceRanges = (strenv(RANGES) | split(","))
' "$APP"

git -C "$ROOT" diff -- "$APP"
echo "Review the diff above, then commit and push it; Argo CD syncs the change."
