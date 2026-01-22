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
helm repo add strimzi https://strimzi.io/charts/ || true
helm repo add lakefs https://charts.lakefs.io || true
helm repo update

echo "Deploying services..."

# Ingress controller (deploy first)
echo "[1/15] Deploying Traefik..."
helm upgrade --install traefik traefik/traefik \
  -f "$SCRIPT_DIR/helm/traefik.yml" \
  -n kube-system --create-namespace

# Databases
echo "[2/15] Deploying MongoDB..."
helm upgrade --install mongodb bitnami/mongodb \
  -f "$SCRIPT_DIR/helm/mongo.yml" \
  -n mlops-db --create-namespace

echo "[3/15] Deploying MySQL..."
helm upgrade --install mysql bitnami/mysql \
  -f "$SCRIPT_DIR/helm/mysql.yml" \
  -n mlops-db --create-namespace

echo "[4/15] Deploying Redis..."
helm upgrade --install redis bitnami/redis \
  -f "$SCRIPT_DIR/helm/redis.yml" \
  -n mlops-db --create-namespace

# Monitoring
echo "[5/15] Deploying Prometheus..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -f "$SCRIPT_DIR/helm/prometheus.yml" \
  -n mlops-mon --create-namespace

echo "[6/15] Deploying Grafana..."
helm upgrade --install grafana bitnami/grafana \
  -f "$SCRIPT_DIR/helm/grafana.yml" \
  -n mlops-mon --create-namespace

# CI/CD
echo "[7/15] Deploying Jenkins..."
helm upgrade --install jenkins jenkins/jenkins \
  -f "$SCRIPT_DIR/helm/jenkins.yml" \
  -n argocd --create-namespace

# ArgoCD (GitOps)
echo "[8/15] Deploying ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  -f "$SCRIPT_DIR/helm/argocd.yml" \
  -n argocd

# Container Registry
echo "[9/15] Deploying Registry..."
kubectl create namespace container-registry --dry-run=client -o yaml | kubectl apply -f -

# Apply S3 credentials secret
kubectl apply -f "$SCRIPT_DIR/secrets.yml"

# Create htpasswd auth secret
htpasswd -B -b -c /tmp/htpasswd admin 4k0pYu4JMcZlG8KP
kubectl create secret generic registry-auth \
  --from-file=htpasswd=/tmp/htpasswd \
  -n container-registry --dry-run=client -o yaml | kubectl apply -f -
rm -f /tmp/htpasswd

helm upgrade --install registry twuni/docker-registry \
  -f "$SCRIPT_DIR/helm/registry.yml" \
  -n container-registry --create-namespace

# MLflow
echo "[10/15] Deploying MLflow..."
kubectl create namespace mlops-ml --dry-run=client -o yaml | kubectl apply -f -

# Create MLflow S3 credentials secret (reuse same S3 credentials)
kubectl create secret generic mlflow-s3-credentials \
  --from-literal=accessKeyID="$(echo MjJiMGY0NmQwNmU2ZTNiNjg0MjgyNzJhZTk0NjdlNmM= | base64 -d)" \
  --from-literal=secretAccessKey="$(echo Y2VmNTNhYjIwNThhMjlmYjc2ZGU0NzY1ZTcxY2VjZTE= | base64 -d)" \
  -n mlops-ml --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install mlflow bitnami/mlflow \
  -f "$SCRIPT_DIR/helm/mlflow.yml" \
  -n mlops-ml --create-namespace

# LakeFS (data versioning)
echo "[11/15] Deploying LakeFS..."
helm upgrade --install lakefs lakefs/lakefs \
  -f "$SCRIPT_DIR/helm/lakefs.yml" \
  -n mlops-ml

# Kubeflow Pipelines
echo "[12/15] Deploying Kubeflow Pipelines..."
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

# Apply manifests with --server-side to handle conflicts
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic-emissary?ref=$KUBEFLOW_PIPELINES_VERSION" -n kubeflow --server-side --force-conflicts || true

# Patch MinIO to use official image (Kubeflow's gcr.io image is unavailable)
kubectl set image deployment/minio minio=minio/minio:RELEASE.2023-09-04T19-57-37Z -n kubeflow 2>/dev/null || true

# Create mlpipeline-minio-artifact secret (overwrite with our credentials if needed)
kubectl create secret generic mlpipeline-minio-artifact \
  --from-literal=accesskey="$(echo MjJiMGY0NmQwNmU2ZTNiNjg0MjgyNzJhZTk0NjdlNmM= | base64 -d)" \
  --from-literal=secretkey="$(echo Y2VmNTNhYjIwNThhMjlmYjc2ZGU0NzY1ZTcxY2VjZTE= | base64 -d)" \
  -n kubeflow --dry-run=client -o yaml | kubectl apply -f -

# Wait for Kubeflow Pipelines to be ready (use default MinIO config from manifests)
# Note: For external S3 (Contabo), you would need to patch the configmap and secrets
# but that requires more extensive changes. Using built-in MinIO for now.
echo "Waiting for Kubeflow Pipelines pods to be ready..."
kubectl wait --for=condition=ready pod -l app=ml-pipeline -n kubeflow --timeout=300s || true

# Expose Kubeflow Pipelines UI via NodePort
kubectl patch svc ml-pipeline-ui -n kubeflow -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "nodePort": 30030, "targetPort": 3000}]}}' || true

# Kafka (streaming platform) - Using Strimzi operator (Bitnami images unavailable)
echo "[13/15] Deploying Kafka (Strimzi)..."
kubectl create namespace mlops-stream --dry-run=client -o yaml | kubectl apply -f -

# Install Strimzi operator
helm upgrade --install strimzi-operator strimzi/strimzi-kafka-operator \
  -n mlops-stream \
  --set watchAnyNamespace=false

# Wait for Strimzi operator to be ready
echo "Waiting for Strimzi operator..."
kubectl wait --for=condition=ready pod -l strimzi.io/kind=cluster-operator -n mlops-stream --timeout=120s || true

# Deploy Kafka cluster using Strimzi CRD
kubectl apply -f "$SCRIPT_DIR/helm/kafka-strimzi.yml"

# Wait for Kafka to be ready
echo "Waiting for Kafka cluster to be ready..."
kubectl wait kafka/kafka --for=condition=Ready -n mlops-stream --timeout=300s || true

# Deploy Kafka Connect (Strimzi)
echo "[13b/15] Deploying Kafka Connect..."
kubectl apply -f "$SCRIPT_DIR/data/ingestion/consumer/kafka-connect.yml"

# Wait for Kafka Connect to be ready (build takes time)
echo "Waiting for Kafka Connect to build and start..."
kubectl wait kafkaconnect/kafka-connect --for=condition=Ready -n mlops-stream --timeout=600s || true

# Kafka UI
echo "[14/15] Deploying Kafka UI..."
helm upgrade --install kafka-ui kafka-ui/kafka-ui \
  -f "$SCRIPT_DIR/helm/kafka-ui.yml" \
  -n mlops-stream

# TimescaleDB (time-series database)
echo "[15/15] Deploying TimescaleDB..."
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
echo "  - argocd:           Jenkins, ArgoCD"
echo "  - mlops-ml:           MLflow, LakeFS"
echo "  - kubeflow:           Kubeflow Pipelines"
echo "  - container-registry: Docker Registry"
echo "  - mlops-stream:       Kafka, Kafka UI, TimescaleDB"
echo ""
echo "External Access (NodePort):"
echo "  - Grafana:      http://<SERVER_IP>:30000"
echo "  - Kubeflow:     http://<SERVER_IP>:30030"
echo "  - MLflow:       http://<SERVER_IP>:30050"
echo "  - Jenkins:      http://<SERVER_IP>:30080"
echo "  - ArgoCD:       http://<SERVER_IP>:30200"
echo "  - Kafka UI:     http://<SERVER_IP>:30091"
echo "  - LakeFS:       http://<SERVER_IP>:30100"
echo "  - Registry:     http://<SERVER_IP>:30500"
echo "  - Kafka:        <SERVER_IP>:30092"
echo "  - TimescaleDB:  <SERVER_IP>:30432"
echo "  - MySQL:        <SERVER_IP>:30306"
echo "  - MongoDB:      <SERVER_IP>:30017"
