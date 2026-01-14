#!/bin/bash
set -e

echo "Removing Helm releases..."

# MLflow
echo "[1/9] Removing MLflow..."
helm uninstall mlflow -n mlops-ml 2>/dev/null || true
kubectl delete secret mlflow-s3-credentials -n mlops-ml 2>/dev/null || true
kubectl delete pvc -n mlops-ml --all --force 2>/dev/null || true

# Container Registry
echo "[2/9] Removing Registry..."
helm uninstall registry -n container-registry 2>/dev/null || true
kubectl delete secret registry-auth -n container-registry 2>/dev/null || true
kubectl delete secret registry-s3-credentials -n container-registry 2>/dev/null || true
kubectl delete pvc -n container-registry --all --force 2>/dev/null || true

# CI/CD
echo "[3/9] Removing Jenkins..."
helm uninstall jenkins -n mlops-ci 2>/dev/null || true
kubectl delete pvc -n mlops-ci --all --force 2>/dev/null || true

# Monitoring
echo "[4/9] Removing Grafana..."
helm uninstall grafana -n mlops-mon 2>/dev/null || true
kubectl delete secret grafana-admin -n mlops-mon 2>/dev/null || true
kubectl delete pvc -l app.kubernetes.io/name=grafana -n mlops-mon --force 2>/dev/null || true

echo "[5/9] Removing Prometheus..."
helm uninstall prometheus -n mlops-mon 2>/dev/null || true
kubectl delete pvc -n mlops-mon --all --force 2>/dev/null || true

# Databases
echo "[6/9] Removing Redis..."
helm uninstall redis -n mlops-db 2>/dev/null || true

echo "[7/9] Removing MySQL..."
helm uninstall mysql -n mlops-db 2>/dev/null || true

echo "[8/9] Removing MongoDB..."
helm uninstall mongodb -n mlops-db 2>/dev/null || true

kubectl delete pvc -n mlops-db --all --force 2>/dev/null || true

# Ingress controller
echo "[9/9] Removing Traefik..."
helm uninstall traefik -n kube-system 2>/dev/null || true

echo ""
echo "Removing namespaces..."
kubectl delete namespace mlops-ml 2>/dev/null || true
kubectl delete namespace container-registry 2>/dev/null || true
kubectl delete namespace mlops-ci 2>/dev/null || true
kubectl delete namespace mlops-mon 2>/dev/null || true
kubectl delete namespace mlops-db 2>/dev/null || true

echo ""
echo "All services removed successfully!"
