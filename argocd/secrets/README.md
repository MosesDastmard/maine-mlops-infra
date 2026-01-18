# Secrets Management with Sealed Secrets

This directory contains templates and instructions for managing secrets with Bitnami Sealed Secrets.

## How It Works

1. **Sealed Secrets Controller** runs in the cluster and holds a private key
2. You encrypt secrets locally using `kubeseal` CLI with the controller's public key
3. Encrypted secrets (SealedSecrets) are safe to commit to Git
4. The controller decrypts them in-cluster to create regular Kubernetes Secrets

## Setup

### 1. Install kubeseal CLI

```bash
# macOS
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.1/kubeseal-0.27.1-linux-amd64.tar.gz
tar -xvzf kubeseal-0.27.1-linux-amd64.tar.gz
sudo mv kubeseal /usr/local/bin/
```

### 2. Fetch the public key (after sealed-secrets is deployed)

```bash
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  > sealed-secrets-pub.pem
```

## Creating Sealed Secrets

### Example: S3 Credentials

```bash
# Create a regular secret YAML (don't commit this!)
cat <<EOF > /tmp/s3-secret.yml
apiVersion: v1
kind: Secret
metadata:
  name: s3-credentials
  namespace: container-registry
type: Opaque
stringData:
  s3AccessKey: "your-access-key"
  s3SecretKey: "your-secret-key"
EOF

# Seal it
kubeseal --format yaml \
  --cert sealed-secrets-pub.pem \
  < /tmp/s3-secret.yml \
  > argocd/secrets/sealed-s3-credentials.yml

# Clean up the plain secret
rm /tmp/s3-secret.yml
```

### Example: Database Credentials

```bash
cat <<EOF > /tmp/db-secret.yml
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-credentials
  namespace: mlops-db
type: Opaque
stringData:
  mongodb-root-password: "your-password"
  mongodb-password: "your-password"
EOF

kubeseal --format yaml \
  --cert sealed-secrets-pub.pem \
  < /tmp/db-secret.yml \
  > argocd/secrets/sealed-mongodb-credentials.yml

rm /tmp/db-secret.yml
```

## Secrets Required for This Infrastructure

| Secret Name | Namespace | Keys | Used By |
|-------------|-----------|------|---------|
| registry-s3-credentials | container-registry | s3AccessKey, s3SecretKey | Docker Registry |
| registry-auth | container-registry | htpasswd | Docker Registry |
| mlflow-s3-credentials | mlops-ml | accessKeyID, secretAccessKey | MLflow |
| kubeflow-s3-credentials | kubeflow | accessKeyID, secretAccessKey | Kubeflow |
| mlpipeline-minio-artifact | kubeflow | accesskey, secretkey | Kubeflow Pipelines |

## Important Notes

- **Never commit plain secrets** to Git
- **Sealed Secrets are cluster-specific** - re-seal if you change clusters
- **Back up the controller's private key** for disaster recovery:
  ```bash
  kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-master.key
  ```
- Secrets can be scoped to specific namespaces (default) or cluster-wide

## Migration from Existing Secrets

To migrate existing secrets from deploy.sh:

```bash
# Export existing secret
kubectl get secret registry-s3-credentials -n container-registry -o yaml > /tmp/secret.yml

# Remove cluster-specific metadata
yq 'del(.metadata.creationTimestamp, .metadata.resourceVersion, .metadata.uid, .metadata.annotations)' /tmp/secret.yml > /tmp/clean-secret.yml

# Seal it
kubeseal --format yaml --cert sealed-secrets-pub.pem < /tmp/clean-secret.yml > sealed-secret.yml
```
