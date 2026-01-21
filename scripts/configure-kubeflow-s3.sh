#!/bin/bash
# Post-installation configuration script for Kubeflow Pipelines
# This script configures Kubeflow to use Contabo S3 instead of minio
#
# Run this after Kubeflow Pipelines is deployed

set -e

NAMESPACE="${KUBEFLOW_NAMESPACE:-kubeflow}"
S3_ENDPOINT="${S3_ENDPOINT:-eu2.contabostorage.com}"
S3_BUCKET="${S3_BUCKET:-kubeflow-pipelines}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-22b0f46d06e6e3b68428272ae9467e6c}"
S3_SECRET_KEY="${S3_SECRET_KEY:-cef53ab2058a29fb76de4765e71cece1}"

echo "Configuring Kubeflow Pipelines to use Contabo S3..."

# 1. Scale down minio deployment (we use external S3)
echo "Scaling down minio deployment..."
kubectl scale deployment minio -n "$NAMESPACE" --replicas=0 2>/dev/null || echo "Minio deployment not found, skipping"

# 2. Update S3 credentials secret
echo "Updating S3 credentials..."
kubectl patch secret mlpipeline-minio-artifact -n "$NAMESPACE" \
  -p "{\"stringData\":{\"accesskey\":\"$S3_ACCESS_KEY\",\"secretkey\":\"$S3_SECRET_KEY\"}}" \
  2>/dev/null || \
kubectl create secret generic mlpipeline-minio-artifact -n "$NAMESPACE" \
  --from-literal=accesskey="$S3_ACCESS_KEY" \
  --from-literal=secretkey="$S3_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Configure ml-pipeline deployment to use external S3
echo "Configuring ml-pipeline for external S3..."
kubectl set env deployment/ml-pipeline -n "$NAMESPACE" \
  OBJECTSTORECONFIG_HOST="$S3_ENDPOINT" \
  OBJECTSTORECONFIG_PORT=443 \
  OBJECTSTORECONFIG_SECURE=true \
  OBJECTSTORECONFIG_BUCKETNAME="$S3_BUCKET" \
  OBJECTSTORECONFIG_REGION=eu2

# 4. Wait for ml-pipeline to be ready
echo "Waiting for ml-pipeline to be ready..."
kubectl rollout status deployment/ml-pipeline -n "$NAMESPACE" --timeout=120s

echo "Kubeflow Pipelines configured successfully!"
