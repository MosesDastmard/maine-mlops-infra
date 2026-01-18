#!/bin/bash
set -e

echo "Removing Helm releases..."

# Streaming (remove first - newest additions)
echo "[1/15] Removing TimescaleDB..."
helm uninstall timescaledb -n mlops-stream 2>/dev/null || true

echo "[2/15] Removing Kafka UI..."
helm uninstall kafka-ui -n mlops-stream 2>/dev/null || true

echo "[3/15] Removing Kafka (Strimzi)..."
# Delete Kafka cluster CR first
kubectl delete kafka kafka -n mlops-stream 2>/dev/null || true
kubectl delete kafkanodepool dual-role -n mlops-stream 2>/dev/null || true
# Uninstall Strimzi operator
helm uninstall strimzi-operator -n mlops-stream 2>/dev/null || true
# Also try removing Bitnami kafka if it exists (for backwards compatibility)
helm uninstall kafka -n mlops-stream 2>/dev/null || true
kubectl delete pvc -n mlops-stream --all --force 2>/dev/null || true

# Kubeflow Pipelines
echo "[4/15] Removing Kubeflow Pipelines..."
KUBEFLOW_PIPELINES_VERSION="2.4.0"
kubectl delete -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic-emissary?ref=$KUBEFLOW_PIPELINES_VERSION" -n kubeflow 2>/dev/null || true
kubectl delete -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$KUBEFLOW_PIPELINES_VERSION" 2>/dev/null || true
helm uninstall argo-workflows -n kubeflow 2>/dev/null || true
kubectl delete secret kubeflow-s3-credentials -n kubeflow 2>/dev/null || true
kubectl delete pvc -n kubeflow --all --force 2>/dev/null || true

# LakeFS
echo "[5/15] Removing LakeFS..."
helm uninstall lakefs -n mlops-ml 2>/dev/null || true

# MLflow
echo "[6/15] Removing MLflow..."
helm uninstall mlflow -n mlops-ml 2>/dev/null || true
kubectl delete secret mlflow-s3-credentials -n mlops-ml 2>/dev/null || true
kubectl delete pvc -n mlops-ml --all --force 2>/dev/null || true

# Container Registry
echo "[7/15] Removing Registry..."
helm uninstall registry -n container-registry 2>/dev/null || true
kubectl delete secret registry-auth -n container-registry 2>/dev/null || true
kubectl delete secret registry-s3-credentials -n container-registry 2>/dev/null || true
kubectl delete pvc -n container-registry --all --force 2>/dev/null || true

# CI/CD
echo "[8/15] Removing ArgoCD..."
helm uninstall argocd -n mlops-ci 2>/dev/null || true

echo "[9/15] Removing Jenkins..."
helm uninstall jenkins -n mlops-ci 2>/dev/null || true
kubectl delete pvc -n mlops-ci --all --force 2>/dev/null || true

# Monitoring
echo "[10/15] Removing Grafana..."
helm uninstall grafana -n mlops-mon 2>/dev/null || true
kubectl delete secret grafana-admin -n mlops-mon 2>/dev/null || true
kubectl delete pvc -l app.kubernetes.io/name=grafana -n mlops-mon --force 2>/dev/null || true

echo "[11/15] Removing Prometheus..."
helm uninstall prometheus -n mlops-mon 2>/dev/null || true
kubectl delete pvc -n mlops-mon --all --force 2>/dev/null || true

# Databases
echo "[12/15] Removing Redis..."
helm uninstall redis -n mlops-db 2>/dev/null || true

echo "[13/15] Removing MySQL..."
helm uninstall mysql -n mlops-db 2>/dev/null || true

echo "[14/15] Removing MongoDB..."
helm uninstall mongodb -n mlops-db 2>/dev/null || true

kubectl delete pvc -n mlops-db --all --force 2>/dev/null || true

# Ingress controller
echo "[15/15] Removing Traefik..."
helm uninstall traefik -n kube-system 2>/dev/null || true

echo ""
echo "Removing namespaces..."
kubectl delete namespace mlops-stream 2>/dev/null || true
kubectl delete namespace kubeflow 2>/dev/null || true
kubectl delete namespace mlops-ml 2>/dev/null || true
kubectl delete namespace container-registry 2>/dev/null || true
kubectl delete namespace mlops-ci 2>/dev/null || true
kubectl delete namespace mlops-mon 2>/dev/null || true
kubectl delete namespace mlops-db 2>/dev/null || true

echo ""
echo "All services removed successfully!"
