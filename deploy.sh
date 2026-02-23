#!/bin/bash

# ArgoCD-based deployment script for Plateforme Electronique
# Usage: ./deploy.sh (run from project root)

set -e

ARGOCD_NAMESPACE="argocd"
APP_NAMESPACE="plateforme-electronique"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Deploying Plateforme Electronique via ArgoCD"
echo "=========================================="

# ---------------------------------------------------------
# Step 1: Check/start Minikube
# ---------------------------------------------------------
echo ""
echo "[1/6] Checking Minikube..."
if ! minikube status > /dev/null 2>&1; then
    echo "Starting Minikube..."
    minikube start --cpus=4 --memory=8192 --driver=docker
else
    echo "Minikube is already running."
fi

MINIKUBE_IP=$(minikube ip)
echo "Minikube IP: ${MINIKUBE_IP}"

# ---------------------------------------------------------
# Step 2: Install ArgoCD if not present
# ---------------------------------------------------------
echo ""
echo "[2/6] Setting up ArgoCD..."
if ! kubectl get namespace "${ARGOCD_NAMESPACE}" > /dev/null 2>&1; then
    echo "Creating namespace ${ARGOCD_NAMESPACE}..."
    kubectl create namespace "${ARGOCD_NAMESPACE}"
else
    echo "Namespace ${ARGOCD_NAMESPACE} already exists."
fi

if ! kubectl get deployment argocd-server -n "${ARGOCD_NAMESPACE}" > /dev/null 2>&1; then
    echo "Installing ArgoCD (this may take a minute)..."
    kubectl apply -n "${ARGOCD_NAMESPACE}" \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    echo "Waiting for ArgoCD server to be ready..."
    kubectl wait --for=condition=available deployment/argocd-server \
        -n "${ARGOCD_NAMESPACE}" --timeout=300s
else
    echo "ArgoCD is already installed."
    echo "Ensuring ArgoCD server is ready..."
    kubectl wait --for=condition=available deployment/argocd-server \
        -n "${ARGOCD_NAMESPACE}" --timeout=300s
fi

# ---------------------------------------------------------
# Step 3: Expose ArgoCD server via NodePort
# ---------------------------------------------------------
echo ""
echo "[3/6] Exposing ArgoCD server via NodePort..."
# NodePort 30443 (HTTPS) and 30090 (HTTP)
# Avoids conflicts with: frontend (30080), api-gateway (30808), keycloak (30880)
kubectl patch svc argocd-server -n "${ARGOCD_NAMESPACE}" -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {"port": 443, "targetPort": 8080, "nodePort": 30443, "name": "https"},
      {"port": 80, "targetPort": 8080, "nodePort": 30090, "name": "http"}
    ]
  }
}'
echo "ArgoCD server exposed on NodePort 30443 (HTTPS) and 30090 (HTTP)."

# ---------------------------------------------------------
# Step 4: Apply the ArgoCD Application manifest
# ---------------------------------------------------------
echo ""
echo "[4/6] Applying ArgoCD Application manifest..."
kubectl apply -f "${SCRIPT_DIR}/argocd-application.yaml"
echo "Application 'plateforme-electronique' created/updated in ArgoCD."

# ---------------------------------------------------------
# Step 5: Wait for sync completion
# ---------------------------------------------------------
echo ""
echo "[5/6] Waiting for ArgoCD to sync the application..."
echo "(This may take several minutes on first deployment)"

MAX_ATTEMPTS=60
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    SYNC_STATUS=$(kubectl get application plateforme-electronique \
        -n "${ARGOCD_NAMESPACE}" \
        -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH_STATUS=$(kubectl get application plateforme-electronique \
        -n "${ARGOCD_NAMESPACE}" \
        -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

    echo "  Sync: ${SYNC_STATUS} | Health: ${HEALTH_STATUS} (attempt $((ATTEMPT+1))/${MAX_ATTEMPTS})"

    if [ "${SYNC_STATUS}" = "Synced" ] && [ "${HEALTH_STATUS}" = "Healthy" ]; then
        echo "Application is synced and healthy!"
        break
    fi

    ATTEMPT=$((ATTEMPT+1))
    sleep 10
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo ""
    echo "WARNING: Application did not reach Synced/Healthy state within the timeout."
    echo "Check the ArgoCD UI for details. The deployment may still be in progress."
fi

# ---------------------------------------------------------
# Step 6: Retrieve ArgoCD admin password and display URLs
# ---------------------------------------------------------
echo ""
echo "[6/6] Retrieving access information..."

ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "N/A (secret may have been deleted)")

echo ""
echo "=========================================="
echo "  Deployment Complete!"
echo "=========================================="
echo ""
echo "--- ArgoCD Dashboard ---"
echo "  URL:      https://${MINIKUBE_IP}:30443"
echo "  HTTP:     http://${MINIKUBE_IP}:30090"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "--- Application URLs ---"
echo "  Frontend:     http://${MINIKUBE_IP}:30080"
echo "  API Gateway:  http://${MINIKUBE_IP}:30808"
echo "  Keycloak:     http://${MINIKUBE_IP}:30880"
echo ""
echo "--- Useful Commands ---"
echo "  kubectl get all -n ${APP_NAMESPACE}"
echo "  kubectl get applications -n ${ARGOCD_NAMESPACE}"
echo "  kubectl logs -n ${ARGOCD_NAMESPACE} deployment/argocd-server"
echo ""
