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
helm repo update

echo "Deploying services..."

# Ingress controller (deploy first)
echo "[1/10] Deploying Traefik..."
helm upgrade --install traefik traefik/traefik \
  -f "$SCRIPT_DIR/helm/traefik.yml" \
  -n kube-system --create-namespace

# Databases
echo "[2/10] Deploying MongoDB..."
helm upgrade --install mongodb bitnami/mongodb \
  -f "$SCRIPT_DIR/helm/mongo.yml" \
  -n mlops-db --create-namespace

echo "[3/10] Deploying MySQL..."
helm upgrade --install mysql bitnami/mysql \
  -f "$SCRIPT_DIR/helm/mysql.yml" \
  -n mlops-db --create-namespace

echo "[4/10] Deploying Redis..."
helm upgrade --install redis bitnami/redis \
  -f "$SCRIPT_DIR/helm/redis.yml" \
  -n mlops-db --create-namespace

# Monitoring
echo "[5/10] Deploying Prometheus..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -f "$SCRIPT_DIR/helm/prometheus.yml" \
  -n mlops-mon --create-namespace

echo "[6/10] Deploying Grafana..."
helm upgrade --install grafana bitnami/grafana \
  -f "$SCRIPT_DIR/helm/grafana.yml" \
  -n mlops-mon --create-namespace

# CI/CD
echo "[7/10] Deploying Jenkins..."
helm upgrade --install jenkins jenkins/jenkins \
  -f "$SCRIPT_DIR/helm/jenkins.yml" \
  -n mlops-ci --create-namespace

# Container Registry
echo "[8/10] Deploying Registry..."
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
echo "[9/10] Deploying MLflow..."
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
echo "[10/10] Deploying Kubeflow Pipelines..."
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
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$KUBEFLOW_PIPELINES_VERSION" || true
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io || true
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic-emissary?ref=$KUBEFLOW_PIPELINES_VERSION" -n kubeflow

# Fix MinIO image (gcr.io image is deprecated, use official minio image)
echo "Patching MinIO deployment with official image..."
kubectl set image deployment/minio minio=minio/minio:RELEASE.2023-09-04T19-57-37Z -n kubeflow || true
kubectl set env deployment/minio -n kubeflow MINIO_ACCESS_KEY=minio MINIO_SECRET_KEY=minio123 || true

# Wait for Kubeflow Pipelines to be ready
echo "Waiting for Kubeflow Pipelines pods to be ready..."
kubectl wait --for=condition=ready pod -l app=ml-pipeline -n kubeflow --timeout=300s || true

# Expose Kubeflow Pipelines UI via NodePort
kubectl patch svc ml-pipeline-ui -n kubeflow -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "nodePort": 30030, "targetPort": 3000}]}}' || true

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
echo ""
echo "External Access (NodePort):"
echo "  - Grafana:   http://<SERVER_IP>:30000"
echo "  - Kubeflow:  http://<SERVER_IP>:30030"
echo "  - MLflow:    http://<SERVER_IP>:30050"
echo "  - Jenkins:   http://<SERVER_IP>:30080"
echo "  - Registry:  http://<SERVER_IP>:30500"
echo "  - MySQL:     <SERVER_IP>:30306"
echo "  - MongoDB:   <SERVER_IP>:30017"
