# ArgoCD GitOps Configuration

This directory contains the ArgoCD configuration for managing the MLOps infrastructure using GitOps principles.

## Directory Structure

```
argocd/
├── apps/                    # Individual ArgoCD Application manifests
│   ├── namespaces.yml       # Kubernetes namespaces
│   ├── sealed-secrets.yml   # Secret encryption controller
│   ├── traefik.yml          # Ingress controller
│   ├── mongodb.yml          # MongoDB database
│   ├── mysql.yml            # MySQL database
│   ├── redis.yml            # Redis cache
│   ├── prometheus.yml       # Prometheus monitoring
│   ├── grafana.yml          # Grafana dashboards
│   ├── jenkins.yml          # Jenkins CI
│   ├── registry.yml         # Docker registry
│   ├── mlflow.yml           # MLflow tracking
│   ├── lakefs.yml           # LakeFS data versioning
│   ├── strimzi-operator.yml # Kafka operator
│   ├── kafka-cluster.yml    # Kafka cluster (Strimzi CRD)
│   ├── kafka-ui.yml         # Kafka UI
│   ├── timescaledb.yml      # TimescaleDB
│   ├── argo-workflows.yml   # Argo Workflows
│   ├── kubeflow-crds.yml    # Kubeflow CRDs
│   ├── kubeflow-pipelines.yml # Kubeflow Pipelines
│   └── services-stream-consumer.yml # Custom app
├── appsets/                 # ApplicationSets for grouped management
│   ├── databases.yml        # Database services group
│   ├── monitoring.yml       # Monitoring services group
│   ├── streaming.yml        # Streaming platform group
│   └── ml-platform.yml      # ML platform group
├── projects/                # ArgoCD Project definitions
│   ├── mlops-infrastructure.yml
│   └── mlops-applications.yml
├── bootstrap/               # App-of-apps bootstrap
│   ├── root-app.yml         # Root application
│   ├── argocd-self.yml      # ArgoCD self-management
│   └── apps/
│       └── kustomization.yml
└── secrets/                 # Sealed Secrets documentation
    └── README.md
```

## Quick Start

### Prerequisites

1. ArgoCD is already installed in your cluster (via `deploy.sh`)
2. You have `kubectl` access to the cluster
3. Your repository is accessible (public or with credentials configured)

### Step 1: Update Repository URLs

Before deploying, update all occurrences of `MosesDastmard/maine-mlops-infra` with your actual GitHub repository URL:

```bash
# Find all files that need updating
grep -r "MosesDastmard/maine-mlops-infra" argocd/

# Update them (example using sed)
find argocd/ -type f -name "*.yml" -exec sed -i 's|MosesDastmard/maine-mlops-infra|your-actual-username/your-actual-repo|g' {} \;
```

### Step 2: Configure Repository Access (if private)

If your repository is private, you need to configure credentials:

**Option A: Via ArgoCD UI**
1. Go to Settings → Repositories
2. Click "Connect Repo"
3. Enter your repository URL and credentials

**Option B: Via CLI**
```bash
argocd repo add https://github.com/MosesDastmard/maine-mlops-infra.git \
  --username your-username \
  --password your-github-token
```

**Option C: Via Secret**
```bash
kubectl create secret generic repo-creds \
  -n argocd \
  --from-literal=url=https://github.com/MosesDastmard/maine-mlops-infra.git \
  --from-literal=username=your-username \
  --from-literal=password=your-github-token
kubectl label secret repo-creds -n argocd argocd.argoproj.io/secret-type=repository
```

### Step 3: Deploy Projects First

```bash
kubectl apply -f argocd/projects/
```

### Step 4: Bootstrap with App-of-Apps

```bash
kubectl apply -f argocd/bootstrap/root-app.yml
```

This single command will deploy all applications defined in the bootstrap kustomization.

### Step 5: Verify Deployment

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Or via ArgoCD CLI
argocd app list
```

## Migration from deploy.sh

### Before Migration (Current State)
- Services deployed imperatively via `deploy.sh`
- Secrets created inline during deployment
- Manual updates require re-running scripts

### After Migration (GitOps)
- Services deployed declaratively via Git commits
- Secrets managed via Sealed Secrets
- Updates triggered automatically on Git push

### Migration Steps

1. **Seal existing secrets** (see `secrets/README.md`)
2. **Push ArgoCD config to Git**
3. **Apply root application**
4. **Verify all services sync successfully**
5. **Deprecate deploy.sh** (keep for reference/disaster recovery)

## Sync Waves

Applications are deployed in order using sync waves:

| Wave | Applications |
|------|-------------|
| 0 | Namespaces, Projects |
| 1 | Sealed Secrets, Strimzi Operator, Kubeflow CRDs |
| 2 | Databases, TimescaleDB, MLflow, LakeFS, Argo Workflows |
| 3 | Kubeflow Pipelines, Kafka Cluster |
| 4 | Kafka UI |
| 5 | Custom Applications |

## Common Operations

### Sync an Application
```bash
argocd app sync <app-name>
```

### Check Application Status
```bash
argocd app get <app-name>
```

### View Application Logs
```bash
argocd app logs <app-name>
```

### Force Refresh
```bash
argocd app get <app-name> --refresh
```

### Rollback
```bash
argocd app rollback <app-name> <revision>
```

## Troubleshooting

### Application Stuck in "Progressing"
```bash
# Check events
kubectl describe application <app-name> -n argocd

# Check pods
kubectl get pods -n <target-namespace>
kubectl describe pod <pod-name> -n <target-namespace>
```

### Sync Failed
```bash
# Get detailed error
argocd app get <app-name> --show-operation

# Check repo server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server
```

### Secret Not Found
Ensure secrets are created before the application syncs:
1. Check if Sealed Secrets controller is running
2. Verify SealedSecret is applied
3. Check the target namespace

## Security Notes

1. **Secrets**: Never commit plain secrets to Git. Use Sealed Secrets.
2. **Repository Access**: Use GitHub tokens with minimal permissions (repo read only)
3. **ArgoCD Access**: Configure RBAC for production use
4. **Network Policies**: Consider adding network policies for production

## Customization

### Adding a New Application

1. Create a new Application manifest in `argocd/apps/`
2. Add it to `argocd/bootstrap/apps/kustomization.yml`
3. Commit and push
4. ArgoCD will automatically deploy it

### Using ApplicationSets

For multiple similar applications, use ApplicationSets in `argocd/appsets/`.
They support generators like:
- List generator (static list)
- Git generator (from repo structure)
- Cluster generator (multi-cluster)

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
