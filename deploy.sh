#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install Helm if not present
if ! command -v helm &> /dev/null; then
  echo "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Install apache2-utils for htpasswd if not present
if ! command -v htpasswd &> /dev/null; then
  echo "Installing htpasswd..."
  apt-get update && apt-get install -y apache2-utils
fi

echo "Adding Helm repositories..."
helm repo add bitnami https://charts.bitnami.com/bitnami || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add traefik https://traefik.github.io/charts || true
helm repo add twuni https://twuni.github.io/docker-registry.helm || true
helm repo add jenkins https://charts.jenkins.io || true
helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo add kafka-ui https://provectus.github.io/kafka-ui-charts || true
helm repo update

echo "Deploying services..."

# Ingress controller (deploy first)
echo "[1/13] Deploying Traefik..."
helm upgrade --install traefik traefik/traefik \
  -f "$SCRIPT_DIR/helm/traefik.yml" \
  -n kube-system --create-namespace

# Databases
echo "[2/13] Deploying MongoDB..."
helm upgrade --install mongodb bitnami/mongodb \
  -f "$SCRIPT_DIR/helm/mongo.yml" \
  -n mlops-db --create-namespace

echo "[3/13] Deploying MySQL..."
helm upgrade --install mysql bitnami/mysql \
  -f "$SCRIPT_DIR/helm/mysql.yml" \
  -n mlops-db --create-namespace

echo "[4/13] Deploying Redis..."
helm upgrade --install redis bitnami/redis \
  -f "$SCRIPT_DIR/helm/redis.yml" \
  -n mlops-db --create-namespace

# Monitoring
echo "[5/13] Deploying Prometheus..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -f "$SCRIPT_DIR/helm/prometheus.yml" \
  -n mlops-mon --create-namespace

echo "[6/13] Deploying Grafana..."
helm upgrade --install grafana bitnami/grafana \
  -f "$SCRIPT_DIR/helm/grafana.yml" \
  -n mlops-mon --create-namespace

# CI/CD
echo "[7/13] Deploying Jenkins..."
helm upgrade --install jenkins jenkins/jenkins \
  -f "$SCRIPT_DIR/helm/jenkins.yml" \
  -n mlops-ci --create-namespace

# Container Registry
echo "[8/13] Deploying Registry..."
kubectl create namespace container-registry --dry-run=client -o yaml | kubectl apply -f -

# Apply S3 credentials secret
kubectl apply -f "$SCRIPT_DIR/secrets.yml"

# Create htpasswd auth secret
htpasswd -B -b -c /tmp/htpasswd admin Moses1749
kubectl create secret generic registry-auth \
  --from-file=htpasswd=/tmp/htpasswd \
  -n container-registry --dry-run=client -o yaml | kubectl apply -f -
rm -f /tmp/htpasswd

helm upgrade --install registry twuni/docker-registry \
  -f "$SCRIPT_DIR/helm/registry.yml" \
  -n container-registry --create-namespace

# MLflow
echo "[9/13] Deploying MLflow..."
kubectl create namespace mlops-ml --dry-run=client -o yaml | kubectl apply -f -

# Create MLflow S3 credentials secret (reuse same S3 credentials)
kubectl create secret generic mlflow-s3-credentials \
  --from-literal=accessKeyID="$(echo MjJiMGY0NmQwNmU2ZTNiNjg0MjgyNzJhZTk0NjdlNmM= | base64 -d)" \
  --from-literal=secretAccessKey="$(echo Y2VmNTNhYjIwNThhMjlmYjc2ZGU0NzY1ZTcxY2VjZTE= | base64 -d)" \
  -n mlops-ml --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install mlflow bitnami/mlflow \
  -f "$SCRIPT_DIR/helm/mlflow.yml" \
  -n mlops-ml --create-namespace

# Kubeflow Pipelines
echo "[10/13] Deploying Kubeflow Pipelines..."
kubectl create namespace kubeflow --dry-run=client -o yaml | kubectl apply -f -

# Create Kubeflow S3 credentials secret (reuse same S3 credentials)
kubectl create secret generic kubeflow-s3-credentials \
  --from-literal=accessKeyID="$(echo MjJiMGY0NmQwNmU2ZTNiNjg0MjgyNzJhZTk0NjdlNmM= | base64 -d)" \
  --from-literal=secretAccessKey="$(echo Y2VmNTNhYjIwNThhMjlmYjc2ZGU0NzY1ZTcxY2VjZTE= | base64 -d)" \
  -n kubeflow --dry-run=client -o yaml | kubectl apply -f -

# Deploy Argo Workflows (required for Kubeflow Pipelines)
helm upgrade --install argo-workflows argo/argo-workflows \
  -n kubeflow \
  --set server.extraArgs="{--auth-mode=server}" \
  --set controller.workflowNamespaces="{kubeflow}" \
  --set workflow.serviceAccount.create=true \
  --set workflow.rbac.create=true \
  --set controller.resources.requests.memory="256Mi" \
  --set controller.resources.requests.cpu="100m" \
  --set controller.resources.limits.memory="512Mi" \
  --set controller.resources.limits.cpu="500m"

# Deploy Kubeflow Pipelines using official manifests (2.4.0+ uses ghcr.io images)
KUBEFLOW_PIPELINES_VERSION="2.4.0"

# Delete MinIO first if it exists (we use Contabo S3 instead)
echo "Removing MinIO if exists (using Contabo S3 instead)..."
kubectl delete deployment minio -n kubeflow 2>/dev/null || true
kubectl delete service minio-service -n kubeflow 2>/dev/null || true

kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$KUBEFLOW_PIPELINES_VERSION" || true
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io || true

# Apply manifests with --server-side to handle conflicts, skip minio errors
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic-emissary?ref=$KUBEFLOW_PIPELINES_VERSION" -n kubeflow --server-side --force-conflicts 2>&1 | grep -v "minio" || true

# Remove MinIO deployment - we use Contabo S3
echo "Removing MinIO deployment..."
kubectl delete deployment minio -n kubeflow --ignore-not-found=true
kubectl delete service minio-service -n kubeflow --ignore-not-found=true

# Create mlpipeline-minio-artifact secret for Contabo S3
kubectl create secret generic mlpipeline-minio-artifact \
  --from-literal=accesskey="$(echo MjJiMGY0NmQwNmU2ZTNiNjg0MjgyNzJhZTk0NjdlNmM= | base64 -d)" \
  --from-literal=secretkey="$(echo Y2VmNTNhYjIwNThhMjlmYjc2ZGU0NzY1ZTcxY2VjZTE= | base64 -d)" \
  -n kubeflow --dry-run=client -o yaml | kubectl apply -f -

# Configure ml-pipeline to use Contabo S3
kubectl set env deployment/ml-pipeline -n kubeflow \
  MINIO_SERVICE_SERVICE_HOST=eu2.contabostorage.com \
  MINIO_SERVICE_SERVICE_PORT=443 \
  MINIO_SERVICE_REGION="" \
  MINIO_SERVICE_SECURE=true \
  OBJECTSTORECONFIG_BUCKETNAME=kubeflow-pipelines || true

kubectl set env deployment/ml-pipeline-ui -n kubeflow \
  MINIO_HOST=eu2.contabostorage.com \
  MINIO_PORT=443 \
  MINIO_SSL=true \
  MINIO_NAMESPACE=kubeflow-pipelines || true

# Wait for Kubeflow Pipelines to be ready
echo "Waiting for Kubeflow Pipelines pods to be ready..."
kubectl wait --for=condition=ready pod -l app=ml-pipeline -n kubeflow --timeout=300s || true

# Expose Kubeflow Pipelines UI via NodePort
kubectl patch svc ml-pipeline-ui -n kubeflow -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "nodePort": 30030, "targetPort": 3000}]}}' || true

# Kafka (streaming platform)
echo "[11/13] Deploying Kafka..."
helm upgrade --install kafka bitnami/kafka \
  -f "$SCRIPT_DIR/helm/kafka.yml" \
  -n mlops-stream --create-namespace

# Wait for Kafka to be ready before deploying UI
echo "Waiting for Kafka to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kafka -n mlops-stream --timeout=300s || true

# Kafka UI
echo "[12/13] Deploying Kafka UI..."
helm upgrade --install kafka-ui kafka-ui/kafka-ui \
  -f "$SCRIPT_DIR/helm/kafka-ui.yml" \
  -n mlops-stream

# TimescaleDB (time-series database)
echo "[13/13] Deploying TimescaleDB..."
helm upgrade --install timescaledb bitnami/postgresql \
  -f "$SCRIPT_DIR/helm/timescaledb.yml" \
  -n mlops-stream

echo ""
echo "All services deployed successfully!"
echo ""
echo "Namespaces:"
echo "  - kube-system:        Traefik"
echo "  - mlops-db:           MongoDB, MySQL, Redis"
echo "  - mlops-mon:          Prometheus, Grafana"
echo "  - mlops-ci:           Jenkins"
echo "  - mlops-ml:           MLflow"
echo "  - kubeflow:           Kubeflow Pipelines"
echo "  - container-registry: Docker Registry"
echo "  - mlops-stream:       Kafka, Kafka UI, TimescaleDB"
echo ""
echo "External Access (NodePort):"
echo "  - Grafana:      http://<SERVER_IP>:30000"
echo "  - Kubeflow:     http://<SERVER_IP>:30030"
echo "  - MLflow:       http://<SERVER_IP>:30050"
echo "  - Jenkins:      http://<SERVER_IP>:30080"
echo "  - Kafka UI:     http://<SERVER_IP>:30091"
echo "  - Registry:     http://<SERVER_IP>:30500"
echo "  - Kafka:        <SERVER_IP>:30092"
echo "  - TimescaleDB:  <SERVER_IP>:30432"
echo "  - MySQL:        <SERVER_IP>:30306"
echo "  - MongoDB:      <SERVER_IP>:30017"
