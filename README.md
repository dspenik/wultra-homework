# PowerAuth Test Server on Azure

Infrastructure for running [powerauth-test-server](https://github.com/wultra/powerauth-tests/tree/develop/powerauth-test-server) on Azure Kubernetes Service with PostgreSQL, provisioned by Terraform and deployed by Argo CD (GitOps).

## Architecture

### Provisioning and GitOps

```mermaid
flowchart LR
    subgraph operator["Operator workstation"]
        bootstrap["1. scripts/bootstrap-state.sh<br/>(az CLI)"]
        tf["2. terraform apply<br/>infra/terraform"]
        values["3. scripts/gitops-values.sh"]
    end

    subgraph azure["Azure subscription"]
        state[("Storage Account<br/>Terraform state")]
        infra["Network, AKS, PostgreSQL,<br/>Key Vault + DB password,<br/>managed identity"]
        subgraph aks["AKS"]
            argocd["Argo CD<br/>+ root Application"]
            subgraph nsapp["ns: powerauth"]
                w0["wave 0<br/>ServiceAccount<br/>SecretProviderClass"]
                w1["wave 1<br/>Job: DB migration<br/>(init image, Sync hook)"]
                w2["wave 2<br/>Deployment + Service<br/>(test server)"]
            end
        end
    end

    subgraph github["GitHub repo"]
        apps["gitops/apps/dev/<br/>powerauth-test-server.yaml"]
        chart["gitops/charts/<br/>powerauth-test-server"]
    end

    argohelm[("argo-helm<br/>chart repo")]

    bootstrap -- "create" --> state
    tf -- "state" --> state
    tf -- "provision" --> infra
    tf -- "helm install" --> argocd
    tf -- "fetch chart" --> argohelm
    values -- "TF outputs → values,<br/>commit + push" --> apps

    argocd -- "4. pull" --> apps
    argocd -- "4. render" --> chart
    argocd -- "5. apply" --> w0 --> w1 --> w2
```

1. **Bootstrap (once):** `scripts/bootstrap-state.sh` creates the Storage Account that holds the Terraform state and grants the caller data-plane access to it.
2. **Provision:** `terraform apply` creates the network, AKS, PostgreSQL, Key Vault (with the generated DB password) and the workload identity, then installs Argo CD and a root Application pointing at `gitops/apps/<environment>/`. Terraform stops here. The values committed in `gitops/apps/dev/` belong to the previous deployment, so the first sync cannot succeed until step 3 overwrites them.
3. **Hand-off:** `scripts/gitops-values.sh` writes the Terraform outputs (identity client ID, tenant ID, Key Vault name, PostgreSQL host) into the Argo CD Application values; the change is committed and pushed.
4. **Reconcile:** Argo CD pulls the repository and renders the Helm chart.
5. **Deploy in waves:** identity and secret wiring first, then the migration Job (a failed migration stops the sync), then the application.

A new application version is a commit changing `image.tag` in `gitops/apps/dev/powerauth-test-server.yaml`; the migration Job uses the same tag and runs before the rollout on every sync.

### Runtime

```mermaid
flowchart LR
    client(["Tester / API client"])
    entra["Microsoft Entra ID"]
    dockerhub[("Docker Hub<br/>powerauth images 2.2.0")]
    enrollment(["Enrollment Server<br/>(external, optional)"])

    subgraph azure["Azure subscription"]
        subgraph rgnode["RG: MC_* (managed by AKS)"]
            lb["Standard Load Balancer<br/>public IPs: Service + outbound"]
        end

        subgraph rg["RG: rg-powerauth-dev"]
            kv["Key Vault (RBAC)"]
            uami["Managed identity<br/>+ federated credential"]
            dns["Private DNS zone<br/>(linked to VNet)"]

            subgraph vnet["VNet"]
                subgraph snetaks["Subnet: AKS nodes"]
                    subgraph nsapp["ns: powerauth (PSA restricted)"]
                        svc["Service LoadBalancer<br/>:80 → 8080, source ranges"]
                        deploy["Deployment: test server<br/>uid 999, LQ_ENABLED=false"]
                        job["Job: DB migration<br/>uid 1001"]
                        csi["Key Vault CSI volume"]
                    end
                end
                subgraph snetpg["Subnet: PostgreSQL (delegated)"]
                    pg[("PostgreSQL Flexible Server<br/>private access, TLS")]
                end
            end
        end
    end

    client -- "HTTP /powerauth-test-server" --> lb --> svc --> deploy

    csi -- "SA token" --> entra -- "token for" --> uami
    uami -. "Key Vault Secrets User" .-> kv
    csi -- "DB credentials" --> kv
    csi --> deploy
    csi --> job

    job -- "Liquibase (5432, TLS)" --> pg
    deploy -- "JDBC (5432, sslmode=require)" --> pg
    dns -. "resolves" .- pg

    lb -- "outbound: image pull" --> dockerhub
    deploy -. "configurable URL" .-> enrollment
```

- **Secrets:** each pod mounts the Key Vault CSI volume and authenticates through workload identity; no secret is stored in Git or Terraform variables.
- **Database:** reachable only from the VNet; the schema is owned by the migration Job, the application only validates it.
- **Access:** testers reach the application through the Load Balancer, restricted to allowed source ranges.

## Repository layout

```
infra/terraform/          Azure infrastructure + Argo CD bootstrap (single root module)
gitops/apps/<env>/        Argo CD Applications of one environment, watched by its root Application
gitops/charts/            Helm chart of the test server (migration Job, Deployment, Service, secrets)
scripts/                  bootstrap-state.sh (Terraform state), gitops-values.sh (Terraform → GitOps hand-off)
```

## Deploy to Azure

Prerequisites: Azure CLI, Terraform >= 1.11, kubectl, git, curl, openssl, jq and [mikefarah yq](https://github.com/mikefarah/yq) v4. The Azure identity needs Owner, or Contributor + Role Based Access Control Administrator, on the subscription (Terraform creates role assignments). Argo CD pulls `gitops_repo_url` (branch `master`) without credentials: to deploy your own copy, fork the repository and set `gitops_repo_url` in `dev.tfvars`. Check that the region is open for the subscription (Free Trial subscriptions are restricted in some regions, e.g. West Europe): `az postgres flexible-server list-skus -l austriaeast` must list `Standard_B1ms` and `az vm list-skus -l austriaeast --size Standard_D2s_v6` must show no restrictions.

```shell
az login
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

# 1. Terraform state storage (once)
./scripts/bootstrap-state.sh

# 2. Infrastructure + Argo CD; only admin_ip_ranges may reach the API server and Key Vault
export TF_VAR_admin_ip_ranges="[\"$(curl -4 -fsS https://ifconfig.me)/32\"]"
terraform -chdir=infra/terraform init -backend-config=backend.hcl -backend-config="key=powerauth-dev.tfstate"
terraform -chdir=infra/terraform apply -var-file=dev.tfvars

# 3. Hand-off to GitOps: who may reach the application, then commit and push
ALLOWED_SOURCE_RANGES="$(curl -4 -fsS https://ifconfig.me)/32" ./scripts/gitops-values.sh
git commit -am "Configure dev environment" && git push

# 4. Verify
$(terraform -chdir=infra/terraform output -raw aks_get_credentials)
kubectl -n argocd get applications
kubectl -n powerauth get pods
curl "http://$(kubectl -n powerauth get svc powerauth-test-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/powerauth-test-server/actuator/health"
```

Argo CD UI: `kubectl -n argocd port-forward svc/argocd-server 8443:443`, user `admin`, password from `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.

**Day-2 operations**

- New application version: change `image.tag` in `gitops/apps/dev/powerauth-test-server.yaml`, commit, push. The migration Job runs before the rollout; a failed migration stops the sync.
- Failed migration: Argo CD does not retry the same commit once its retries are used up. Read `kubectl -n powerauth logs job/powerauth-test-server-migration`, fix the cause, then push a new commit or sync manually in the Argo CD UI.
- Rotate the DB password: increment `db_password_version` and apply. The CSI driver refreshes the synced Secret within its rotation interval (2 minutes); then restart the Deployment, because environment variables are read only at start.
- Operator IP changed: `plan` fails while refreshing, because Key Vault and the API server reject the new address. Set the new `TF_VAR_admin_ip_ranges` and update the allowlists without a refresh: `terraform -chdir=infra/terraform plan -refresh=false -var-file=dev.tfvars -target=azurerm_key_vault.main -target=azurerm_kubernetes_cluster.main -out=ip.tfplan`, then `apply ip.tfplan`.
- Tear down: `terraform -chdir=infra/terraform destroy -var-file=dev.tfvars` (with `TF_VAR_admin_ip_ranges` set as for apply), then `az group delete --name rg-powerauth-tfstate` to remove the state storage. Stop the cluster between sessions with `az aks stop`; run `az aks start` before the next `plan` or `destroy` (the Helm resources need the API server).
- If an apply failed halfway (e.g. Key Vault RBAC not propagated yet), just re-run it. The DB password is generated on every run but written only when a resource is created or `db_password_version` changes. Whenever only one of the PostgreSQL server and the Key Vault secret is created or replaced (e.g. the first apply failed between them), increment `db_password_version` and apply again so both match.
- New environment (e.g. `test`): add `test.tfvars` (`environment` must be unique per subscription), run `init -reconfigure` with `key=powerauth-test.tfstate`, apply, then `gitops-values.sh` creates `gitops/apps/test/` from the dev Application. No code change is needed. The state key selects the environment: applying a tfvars file against another environment's key would replace that environment.

## Design decisions

| Decision | Why | Alternative considered |
|---|---|---|
| AKS + Argo CD | Pull-based GitOps works without any pipeline (pipelines are out of scope); a Helm chart is the natural unit for Argo CD | **Azure App Service (Web App for Containers)**, today's deployment target of the [Wultra CI actions](https://github.com/wultra/wultra-infrastructure), and **Azure Container Apps**: simpler to operate, but no container orchestration, no chart and no in-cluster reconciliation, so GitOps would depend on a pipeline. **Flux** (GA as an AKS extension) is equally valid; the Argo CD AKS extension is still preview, so Argo CD is installed with Helm |
| Separate migration Job (init image) | The vendor ships a dedicated init image; schema changes are gated before the rollout, the app runs with `LQ_ENABLED=false` and Hibernate `validate` | Let the app run Liquibase on start (races with multiple replicas, no gate) |
| Argo `Sync` hook in wave 1, not `PreSync` | `PreSync` runs before the ServiceAccount and SecretProviderClass exist | Sync waves without a hook (Job would not re-run on upgrades) |
| Key Vault + CSI driver + workload identity | No DB credential in Git, Terraform state or pod specs; managed AKS add-on, nothing extra to operate | External Secrets Operator (one more component), Terraform-managed Kubernetes Secret (secret in state) |
| Ephemeral password + write-only attributes | The generated DB password never lands in the Terraform state | `random_password` resource (stored in state) |
| Private PostgreSQL (VNet integration) | No public endpoint for the database | Public access with firewall rules |
| Service `LoadBalancer` with source ranges, no ingress controller | One service, no TLS requirement for a test environment; the AKS app routing NGINX add-on is supported only until November 2026 | Gateway API (application routing with Istio, Application Gateway for Containers) once there are more services or TLS is needed |
| API server and Key Vault restricted to `admin_ip_ranges`; Key Vault reachable from the AKS subnet via service endpoint | Least exposure without private endpoints / private cluster | Private cluster + private endpoints (needs a jump host or VPN) |
| Helm, not Kustomize | The chart needs hooks and required-value guards and takes its per-environment values from Terraform outputs | Kustomize overlays fit plain manifests with per-environment patches; mixing both on one chart adds a second config layer |
| One repository, one Terraform root module | One environment, one reviewer; Argo CD watches only `gitops/` | Separate infra and GitOps repositories and per-environment stacks as the platform grows |
| Terraform installs Argo CD via the Helm provider in the same stack | Keeps bootstrap to one `apply` | A separate bootstrap stack avoids configuring a provider from a resource of the same apply (relevant when the cluster is replaced) |

**Known trade-offs**

- AKS local accounts are enabled, so the Terraform state contains cluster-admin credentials (client certificate, key and token) that cannot be revoked (only rotated with the cluster certificates). Production should disable local accounts and use Microsoft Entra ID with Azure RBAC.
- The application connects with the PostgreSQL administrator account. Creating a dedicated role needs Terraform network access to the private server; production should use a dedicated role or Microsoft Entra authentication.
- The Terraform → GitOps hand-off (`gitops-values.sh`) is a manual, reviewed commit. A pipeline or the GitOps Bridge pattern would automate it.
- `automatic_upgrade_channel = "patch"` and node image upgrades are enabled; a single node means brief downtime during upgrades.
- Images are pulled from Docker Hub by tag, without signature verification.
- Both Argo CD Applications use the `default` project and `master` is not protected: write access to the repository equals cluster-admin.
- `sslmode=require` encrypts the database connection but does not verify the server certificate.
- The state Storage Account is protected by Entra ID RBAC only (no network rules). Key Vault purge protection is off so the environment can be destroyed and recreated.
- Terraform's access to Key Vault secrets is granted to the identity that runs it; another operator needs `Key Vault Secrets Officer` on the vault first.

## Production next steps

- Supply chain: pull from the Wultra Azure Container Registry with the kubelet managed identity, pin images by digest, and verify the cosign signatures and SBOM attestations the Wultra build already produces (`public-keys/cosign.pub`) with an admission policy (Kyverno or Ratify).
- CI with GitHub Actions: `terraform plan` on pull requests, apply behind an approval (OIDC federation, no stored credentials, a runner inside the VNet), chart lint and policy checks.
- Separate environments (tfvars / stacks per environment, an `ApplicationSet` or one Application per environment), Argo CD `AppProject` restrictions and SSO.
- Monitoring and logs (Azure Monitor managed Prometheus + Grafana or the existing stack), alerts on sync and health status.
- High availability: at least two nodes across zones, PodDisruptionBudget, zone-redundant PostgreSQL, backups with retention per policy.
- NetworkPolicies (Azure CNI Powered by Cilium as the data plane), TLS on the ingress path, Microsoft Entra ID for cluster access with local accounts disabled.
