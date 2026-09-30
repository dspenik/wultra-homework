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
        apps["gitops/apps/<br/>powerauth-test-server.yaml"]
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
2. **Provision:** `terraform apply` creates the network, AKS, PostgreSQL, Key Vault (with the generated DB password) and the workload identity, then installs Argo CD and a root Application pointing at `gitops/apps/`. Terraform stops here. Until step 3 is done the application shows a render error in Argo CD (required values are missing) instead of starting a sync that cannot succeed.
3. **Hand-off:** `scripts/gitops-values.sh` writes the Terraform outputs (identity client ID, tenant ID, Key Vault name, PostgreSQL host) into the Argo CD Application values; the change is committed and pushed.
4. **Reconcile:** Argo CD pulls the repository and renders the Helm chart.
5. **Deploy in waves:** identity and secret wiring first, then the migration Job (a failed migration stops the sync), then the application.

A new application version is a commit changing `image.tag` in `gitops/apps/powerauth-test-server.yaml`; every sync runs the migration Job before the rollout.

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

        subgraph rg["RG: powerauth-dev"]
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
