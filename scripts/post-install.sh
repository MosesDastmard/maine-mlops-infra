#!/bin/bash
# Post-installation configuration script
# Run this after all ArgoCD applications are synced
#
# Usage: ./post-install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Running post-installation configurations"
echo "=========================================="

# Wait for critical pods to be ready
echo ""
echo "Waiting for critical services to be ready..."

# TimescaleDB
echo "Checking TimescaleDB..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n mlops-timescaledb --timeout=300s 2>/dev/null || \
  echo "Warning: TimescaleDB not ready"

# Kubeflow
echo "Checking Kubeflow..."
kubectl wait --for=condition=ready pod -l app=ml-pipeline -n kubeflow --timeout=300s 2>/dev/null || \
  echo "Warning: Kubeflow ml-pipeline not ready"

# Run configuration scripts
echo ""
echo "Running TimescaleDB configuration..."
bash "$SCRIPT_DIR/configure-timescaledb.sh" || echo "TimescaleDB configuration failed or already done"

echo ""
echo "Running Kubeflow S3 configuration..."
bash "$SCRIPT_DIR/configure-kubeflow-s3.sh" || echo "Kubeflow S3 configuration failed or already done"

echo ""
echo "=========================================="
echo "Post-installation completed!"
echo "=========================================="
echo ""
echo "Service URLs:"
echo "  - ArgoCD:      http://<node-ip>:30200"
echo "  - MLflow:      http://<node-ip>:30500"
echo "  - Jenkins:     http://<node-ip>:30800"
echo "  - Grafana:     http://<node-ip>:30000"
echo "  - LakeFS:      http://<node-ip>:32756"
echo "  - Kafka UI:    http://<node-ip>:30900"
echo "  - Registry:    http://<node-ip>:30005"
