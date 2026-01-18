#!/bin/bash
# ArgoCD GitOps Setup Script
# This script helps configure ArgoCD for GitOps management of the MLOps infrastructure

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_NAMESPACE="mlops-ci"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== ArgoCD GitOps Setup ===${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

if ! command -v argocd &> /dev/null; then
    echo -e "${YELLOW}ArgoCD CLI not found. Installing...${NC}"
    curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x /tmp/argocd
    sudo mv /tmp/argocd /usr/local/bin/argocd
fi

# Check if ArgoCD is running
if ! kubectl get deployment argocd-server -n $ARGOCD_NAMESPACE &> /dev/null; then
    echo -e "${RED}Error: ArgoCD is not deployed. Run deploy.sh first.${NC}"
    exit 1
fi

echo -e "${GREEN}Prerequisites OK${NC}"
echo ""

# Get ArgoCD password
echo -e "${YELLOW}Getting ArgoCD admin password...${NC}"
ARGOCD_PASSWORD=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo -e "${GREEN}Admin password: ${ARGOCD_PASSWORD}${NC}"
echo ""

# Get ArgoCD server address
ARGOCD_SERVER=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'):30200
echo -e "${GREEN}ArgoCD Server: http://${ARGOCD_SERVER}${NC}"
echo ""

# Login to ArgoCD
echo -e "${YELLOW}Logging into ArgoCD...${NC}"
argocd login $ARGOCD_SERVER --username admin --password "$ARGOCD_PASSWORD" --insecure

echo ""
echo -e "${YELLOW}=== Configuration Steps ===${NC}"
echo ""
echo "1. Update repository URL in ArgoCD manifests:"
echo "   Replace 'YOUR_USERNAME/YOUR_REPO' with your actual repository URL"
echo ""
echo "   Run: grep -r 'YOUR_USERNAME/YOUR_REPO' $SCRIPT_DIR/"
echo ""

read -p "Enter your GitHub repository URL (e.g., https://github.com/user/repo.git): " REPO_URL

if [ -n "$REPO_URL" ]; then
    echo -e "${YELLOW}Updating repository URLs...${NC}"
    find "$SCRIPT_DIR" -type f -name "*.yml" -exec sed -i "s|https://github.com/YOUR_USERNAME/YOUR_REPO.git|$REPO_URL|g" {} \;
    echo -e "${GREEN}Repository URLs updated${NC}"
fi

echo ""
read -p "Is your repository private? (y/n): " IS_PRIVATE

if [ "$IS_PRIVATE" = "y" ]; then
    echo ""
    read -p "Enter your GitHub username: " GH_USERNAME
    read -sp "Enter your GitHub token (PAT): " GH_TOKEN
    echo ""

    echo -e "${YELLOW}Adding repository to ArgoCD...${NC}"
    argocd repo add "$REPO_URL" --username "$GH_USERNAME" --password "$GH_TOKEN"
    echo -e "${GREEN}Repository added${NC}"
fi

echo ""
echo -e "${YELLOW}=== Deploying ArgoCD Projects ===${NC}"
kubectl apply -f "$SCRIPT_DIR/projects/"
echo -e "${GREEN}Projects deployed${NC}"

echo ""
read -p "Deploy all applications via app-of-apps? (y/n): " DEPLOY_ALL

if [ "$DEPLOY_ALL" = "y" ]; then
    echo -e "${YELLOW}Deploying root application...${NC}"
    kubectl apply -f "$SCRIPT_DIR/bootstrap/root-app.yml"
    echo -e "${GREEN}Root application deployed${NC}"

    echo ""
    echo -e "${YELLOW}Waiting for applications to sync...${NC}"
    sleep 10

    argocd app list
fi

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "Access ArgoCD UI at: http://${ARGOCD_SERVER}"
echo "Username: admin"
echo "Password: ${ARGOCD_PASSWORD}"
echo ""
echo "Next steps:"
echo "1. Review applications in ArgoCD UI"
echo "2. Set up Sealed Secrets for secret management (see secrets/README.md)"
echo "3. Push changes to Git repository"
echo "4. ArgoCD will automatically sync changes"
