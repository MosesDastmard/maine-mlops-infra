#!/bin/bash
set -e

echo "Removing Helm releases..."

# Kubeflow Pipelines (remove first - newest addition)
echo "[1/10] Removing Kubeflow Pipelines..."
KUBEFLOW_PIPELINES_VERSION="2.4.0"
kubectl delete -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic-emissary?ref=$KUBEFLOW_PIPELINES_VERSION" -n kubeflow 2>/dev/null || true
kubectl delete -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$KUBEFLOW_PIPELINES_VERSION" 2>/dev/null || true
helm uninstall argo-workflows -n kubeflow 2>/dev/null || true
kubectl delete secret kubeflow-s3-credentials -n kubeflow 2>/dev/null || true
kubectl delete pvc -n kubeflow --all --force 2>/dev/null || true

# MLflow
echo "[2/10] Removing MLflow..."
helm uninstall mlflow -n mlops-ml 2>/dev/null || true
kubectl delete secret mlflow-s3-credentials -n mlops-ml 2>/dev/null || true
kubectl delete pvc -n mlops-ml --all --force 2>/dev/null || true

# Container Registry
echo "[3/10] Removing Registry..."
helm uninstall registry -n container-registry 2>/dev/null || true
kubectl delete secret registry-auth -n container-registry 2>/dev/null || true
kubectl delete secret registry-s3-credentials -n container-registry 2>/dev/null || true
kubectl delete pvc -n container-registry --all --force 2>/dev/null || true

# CI/CD
echo "[4/10] Removing Jenkins..."
helm uninstall jenkins -n mlops-ci 2>/dev/null || true
kubectl delete pvc -n mlops-ci --all --force 2>/dev/null || true

# Monitoring
echo "[5/10] Removing Grafana..."
helm uninstall grafana -n mlops-mon 2>/dev/null || true
kubectl delete secret grafana-admin -n mlops-mon 2>/dev/null || true
kubectl delete pvc -l app.kubernetes.io/name=grafana -n mlops-mon --force 2>/dev/null || true

echo "[6/10] Removing Prometheus..."
helm uninstall prometheus -n mlops-mon 2>/dev/null || true
kubectl delete pvc -n mlops-mon --all --force 2>/dev/null || true

# Databases
echo "[7/10] Removing Redis..."
helm uninstall redis -n mlops-db 2>/dev/null || true

echo "[8/10] Removing MySQL..."
helm uninstall mysql -n mlops-db 2>/dev/null || true

echo "[9/10] Removing MongoDB..."
helm uninstall mongodb -n mlops-db 2>/dev/null || true

kubectl delete pvc -n mlops-db --all --force 2>/dev/null || true

# Ingress controller
echo "[10/10] Removing Traefik..."
helm uninstall traefik -n kube-system 2>/dev/null || true

echo ""
echo "Removing namespaces..."
kubectl delete namespace kubeflow 2>/dev/null || true
kubectl delete namespace mlops-ml 2>/dev/null || true
kubectl delete namespace container-registry 2>/dev/null || true
kubectl delete namespace mlops-ci 2>/dev/null || true
kubectl delete namespace mlops-mon 2>/dev/null || true
kubectl delete namespace mlops-db 2>/dev/null || true

echo ""
echo "All services removed successfully!"
