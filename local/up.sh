#!/usr/bin/env bash
# Local test on a kind cluster running in Podman.
#   ./up.sh         install the chart directly with Helm
#   ./up.sh argocd  install Argo CD and let it sync local/argocd-app.yaml (branch must be pushed)
set -euo pipefail

MODE="${1:-helm}"
ARGOCD_CHART_VERSION="10.9.4"
# Same Kubernetes minor as the AKS cluster
KIND_NODE_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
CLUSTER="${CLUSTER:-powerauth}"
APP_NS="powerauth"
DB_NS="local-db"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KIND_EXPERIMENTAL_PROVIDER=podman

if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER" --image "$KIND_NODE_IMAGE"
fi
kubectl config use-context "kind-$CLUSTER"

kubectl create namespace "$DB_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$APP_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$APP_NS" pod-security.kubernetes.io/enforce=restricted --overwrite

if ! kubectl -n "$DB_NS" get secret postgres >/dev/null 2>&1; then
  password="$(openssl rand -hex 16)"
  kubectl -n "$DB_NS" create secret generic postgres \
    --from-literal=username=powerauth --from-literal=password="$password"
  kubectl -n "$APP_NS" create secret generic powerauth-test-server-db \
    --from-literal=username=powerauth --from-literal=password="$password"
fi

kubectl apply -f "$ROOT/local/postgres.yaml"
kubectl -n "$DB_NS" rollout status statefulset/postgres --timeout=180s

case "$MODE" in
  helm)
    helm upgrade --install powerauth-test-server "$ROOT/gitops/charts/powerauth-test-server" \
      --namespace "$APP_NS" -f "$ROOT/local/values-kind.yaml"
    kubectl -n "$APP_NS" wait --for=condition=complete job/powerauth-test-server-migration --timeout=300s
    ;;
  argocd)
    helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm \
      --version "$ARGOCD_CHART_VERSION" --namespace argocd --create-namespace \
      -f "$ROOT/infra/terraform/argocd-values.yaml" --wait
    kubectl apply -f "$ROOT/local/argocd-app.yaml"
    echo "Waiting for Argo CD to create the Deployment..."
    until kubectl -n "$APP_NS" get deployment/powerauth-test-server >/dev/null 2>&1; do sleep 5; done
    ;;
  *)
    echo "Usage: $0 [helm|argocd]" >&2
    exit 1
    ;;
esac

kubectl -n "$APP_NS" rollout status deployment/powerauth-test-server --timeout=300s

echo "Run: kubectl -n $APP_NS port-forward svc/powerauth-test-server 8080:80"
echo "Then open http://localhost:8080/powerauth-test-server/"
