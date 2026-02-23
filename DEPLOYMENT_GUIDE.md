# Kubernetes Deployment Guide for Plateforme Électronique

## Overview

This directory contains production-ready Kubernetes manifests for deploying the Plateforme Électronique to Minikube or any Kubernetes cluster, optimized for ArgoCD GitOps workflow.

## Directory Structure

```
k8s2/
├── namespace.yaml                    # Namespace definition
├── secrets.yaml                      # Secrets (credentials, passwords)
├── postgres-init-configmap.yaml      # Database initialization script
├── postgres-storage.yaml             # PostgreSQL PV/PVC
├── redis-storage.yaml                # Redis PV/PVC
├── postgresql.yaml                   # PostgreSQL Deployment & Service
├── redis.yaml                        # Redis Deployment & Service
├── keycloak.yaml                     # Keycloak IAM Deployment & Service
├── eureka-server.yaml                # Service Discovery
├── api-gateway.yaml                  # API Gateway (LoadBalancer)
├── invoice-service.yaml              # Invoice microservice
├── payment-service.yaml              # Payment microservice
├── subscription-service.yaml         # Subscription microservice
├── notification-service.yaml         # Notification microservice
├── user-auth-service.yaml            # User Auth microservice
├── signature-service.yaml            # Signature microservice
├── frontend.yaml                     # React Frontend (LoadBalancer)
├── kustomization.yaml                # Kustomize configuration
├── argocd-application.yaml           # ArgoCD Application manifest
├── build-and-push.sh                 # Build & push images to Docker Hub
├── deploy.sh                         # Quick deployment script
├── README.md                         # Complete documentation
└── DEPLOYMENT_GUIDE.md               # This file
```

## Deployment Methods

### Method 1: Direct kubectl Deployment

**Step 1: Build and push Docker images**
```bash
# Login to Docker Hub
docker login

# Build and push all images
cd /home/osboxes/plateforme_electronique_k8s
./k8s2/build-and-push.sh
```

**Step 2: Deploy to Minikube**
```bash
# Start Minikube (if not running)
minikube start --cpus=4 --memory=8192

# Deploy everything
./k8s2/deploy.sh

# Or manually:
kubectl apply -k k8s2/
```

**Step 3: Access services**
```bash
# Get LoadBalancer URLs
minikube service api-gateway -n plateforme-electronique --url
minikube service frontend -n plateforme-electronique --url

# Or use port forwarding
kubectl port-forward -n plateforme-electronique svc/frontend 3000:80
kubectl port-forward -n plateforme-electronique svc/api-gateway 8080:8080
```

### Method 2: ArgoCD GitOps Deployment

**Step 1: Install ArgoCD**
```bash
# Create namespace and install
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Step 2: Push code to Git repository**
```bash
# Initialize git (if not already)
cd /home/osboxes/plateforme_electronique_k8s
git add k8s2/
git commit -m "Add Kubernetes manifests for ArgoCD"
git push origin main
```

**Step 3: Update ArgoCD application manifest**

Edit `k8s2/argocd-application.yaml` and replace:
```yaml
repoURL: https://github.com/YOUR-USERNAME/plateforme_electronique_k8s.git
```

**Step 4: Deploy via ArgoCD**
```bash
# Apply the ArgoCD application
kubectl apply -f k8s2/argocd-application.yaml

# Or use ArgoCD CLI
argocd login localhost:8080
argocd app create plateforme-electronique \
  --repo https://github.com/YOUR-USERNAME/plateforme_electronique_k8s.git \
  --path k8s2 \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace plateforme-electronique \
  --sync-policy automated

# Sync the application
argocd app sync plateforme-electronique
```

## Docker Hub Images Required

The following images must be available on Docker Hub with the `yassmineg/` prefix:

```
yassmineg/eureka-server:latest
yassmineg/api-gateway:latest
yassmineg/invoice-service:latest
yassmineg/payment-service:latest
yassmineg/subscription-service:latest
yassmineg/notification-service:latest
yassmineg/user-auth-service:latest
yassmineg/signature-service:latest
yassmineg/frontend:latest
```

## Configuration Updates

### Before Deployment

1. **Update secrets** in `k8s2/secrets.yaml`:
   - Change `POSTGRES_PASSWORD`
   - Change `KEYCLOAK_ADMIN_PASSWORD`
   - Add your Gmail App Password for `MAIL_PASSWORD`

2. **Update ArgoCD application** in `k8s2/argocd-application.yaml`:
   - Set your Git repository URL

### After Deployment

1. **Configure Keycloak**:
   - Access: http://localhost:8081/admin
   - Create realm: `plateforme-electronique`
   - Create client: `plateforme-frontend`
   - Configure users and roles

2. **Test the application**:
   - Frontend: http://localhost:3000
   - API Gateway: http://localhost:8080
   - Eureka Dashboard: http://localhost:8761

## Monitoring

### Check Deployment Status

```bash
# All resources
kubectl get all -n plateforme-electronique

# Pods with details
kubectl get pods -n plateforme-electronique -o wide

# Check logs
kubectl logs -n plateforme-electronique -l app=invoice-service --tail=50

# Follow logs
kubectl logs -n plateforme-electronique -l app=api-gateway -f
```

### ArgoCD Monitoring

```bash
# Check application status
argocd app get plateforme-electronique

# Check sync status
argocd app sync plateforme-electronique --dry-run

# View application in UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
```

## Troubleshooting

### Pods not starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n plateforme-electronique

# Check events
kubectl get events -n plateforme-electronique --sort-by='.lastTimestamp'

# Check logs
kubectl logs <pod-name> -n plateforme-electronique
```

### Database connection issues

```bash
# Check PostgreSQL pod
kubectl logs -n plateforme-electronique -l app=postgresql

# Verify databases were created
kubectl exec -it -n plateforme-electronique <postgres-pod> -- psql -U plateforme_user -c '\l'

# Test connectivity from a service
kubectl exec -it -n plateforme-electronique <invoice-service-pod> -- ping postgresql
```

### Image pull errors

```bash
# Verify images exist on Docker Hub
docker pull yassmineg/invoice-service:latest

# Check image pull policy
kubectl get deployment invoice-service -n plateforme-electronique -o yaml | grep imagePullPolicy

# Force re-pull
kubectl rollout restart deployment/invoice-service -n plateforme-electronique
```

## Scaling

### Manual Scaling

```bash
# Scale specific service
kubectl scale deployment invoice-service -n plateforme-electronique --replicas=3

# Check replica status
kubectl get deployment invoice-service -n plateforme-electronique
```

### Auto-scaling

```bash
# Enable metrics-server (Minikube)
minikube addons enable metrics-server

# Create HPA
kubectl autoscale deployment invoice-service -n plateforme-electronique \
  --min=2 --max=5 --cpu-percent=80

# Check HPA status
kubectl get hpa -n plateforme-electronique
```

## Updates and Rollbacks

### Rolling Updates

```bash
# Update image tag in kustomization.yaml or deployment
kubectl set image deployment/invoice-service \
  invoice-service=yassmineg/invoice-service:v2 \
  -n plateforme-electronique

# Check rollout status
kubectl rollout status deployment/invoice-service -n plateforme-electronique

# Check rollout history
kubectl rollout history deployment/invoice-service -n plateforme-electronique
```

### Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/invoice-service -n plateforme-electronique

# Rollback to specific revision
kubectl rollout undo deployment/invoice-service -n plateforme-electronique --to-revision=2
```

## Cleanup

```bash
# Delete all resources
kubectl delete -k k8s2/

# Or delete namespace (removes everything)
kubectl delete namespace plateforme-electronique

# Stop Minikube
minikube stop

# Delete Minikube cluster
minikube delete
```

## Production Considerations

### Security
- [ ] Use Sealed Secrets or external secret management (Vault, AWS Secrets Manager)
- [ ] Enable RBAC and NetworkPolicies
- [ ] Implement Pod Security Standards
- [ ] Use TLS for all external communications
- [ ] Rotate secrets regularly

### High Availability
- [ ] Run multiple replicas (at least 3 for critical services)
- [ ] Configure Pod Anti-Affinity rules
- [ ] Use StatefulSets for databases
- [ ] Implement proper liveness/readiness probes

### Storage
- [ ] Use cloud-native storage (AWS EBS, GCP Persistent Disk, Azure Disk)
- [ ] Configure backup and restore procedures
- [ ] Set up database replication
- [ ] Implement disaster recovery plan

### Monitoring & Observability
- [ ] Install Prometheus and Grafana
- [ ] Configure alerting rules
- [ ] Implement distributed tracing (Jaeger, Zipkin)
- [ ] Set up centralized logging (ELK, Loki)

### Performance
- [ ] Define resource requests and limits
- [ ] Enable Horizontal Pod Autoscaler
- [ ] Configure ingress with proper caching
- [ ] Use CDN for static assets

### CI/CD
- [ ] Automate image builds with GitHub Actions/GitLab CI
- [ ] Implement automated testing
- [ ] Use semantic versioning for images
- [ ] Set up staging and production environments

## Support

For questions and issues:
- Check logs: `kubectl logs -n plateforme-electronique <pod-name>`
- Check documentation: See `README.md`
- Report bugs: Create an issue in the Git repository

## Useful Commands

```bash
# Quick status check
kubectl get all -n plateforme-electronique

# Watch pod status
kubectl get pods -n plateforme-electronique -w

# Get service URLs (Minikube)
minikube service list -n plateforme-electronique

# Shell into a pod
kubectl exec -it <pod-name> -n plateforme-electronique -- /bin/sh

# Copy files from pod
kubectl cp plateforme-electronique/<pod-name>:/path/to/file ./local-file

# Test service connectivity
kubectl run -it --rm debug --image=busybox -n plateforme-electronique -- wget -O- http://api-gateway:8080

# Get resource usage
kubectl top pods -n plateforme-electronique
kubectl top nodes
```

## Next Steps

1. Build and push your Docker images
2. Update configuration in `secrets.yaml`
3. Deploy using `kubectl apply -k k8s2/` or ArgoCD
4. Configure Keycloak realm and clients
5. Test all endpoints
6. Set up monitoring and logging
7. Implement backup strategy
8. Configure ingress for external access

---

**Note**: This deployment is configured for development/testing on Minikube. For production deployment, review and implement the production considerations listed above.
