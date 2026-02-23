# Plateforme Electronique - Deploiement Kubernetes avec ArgoCD

Ce repertoire contient les manifestes Kubernetes pour deployer l'application Plateforme Electronique sur Minikube via ArgoCD. Toutes les images Docker sont hebergees sur Docker Hub sous le compte `yassmineg/`.

## Prerequisites

1. **Minikube** installe et demarre
2. **kubectl** configure pour se connecter a Minikube
3. **ArgoCD CLI** installe (`argocd`)
4. **Docker Hub** - les images doivent etre poussees sous `yassmineg/`

## Architecture

### Infrastructure
| Composant    | Image                          | Port |
|--------------|--------------------------------|------|
| PostgreSQL   | `yassmineg/postgres:15-alpine` | 5432 |
| Redis        | `yassmineg/redis:7-alpine`     | 6379 |
| Keycloak     | `yassmineg/keycloak:22.0`      | 8080 |

### Microservices
| Service              | Image                                    | Port |
|----------------------|------------------------------------------|------|
| Eureka Server        | `yassmineg/eureka-server:latest`         | 8761 |
| API Gateway          | `yassmineg/api-gateway:latest`           | 8080 |
| Invoice Service      | `yassmineg/invoice-service:latest`       | 8082 |
| Payment Service      | `yassmineg/payment-service:latest`       | 8080 |
| Subscription Service | `yassmineg/subscription-service:latest`  | 8083 |
| Notification Service | `yassmineg/notification-service:latest`  | 8085 |
| User Auth Service    | `yassmineg/user-auth-service:latest`     | 8081 |
| Signature Service    | `yassmineg/signature-service:latest`     | 8086 |

### Frontend
| Composant | Image                            | Port |
|-----------|----------------------------------|------|
| Frontend  | `yassmineg/frontend:latest`      | 80   |

## Etape 1 : Demarrer Minikube

```bash
minikube start --cpus=4 --memory=8192 --driver=docker
```

## Etape 2 : Construire et pousser les images Docker

```bash
# Se placer a la racine du projet
cd plateforme_electronique_k8s

# Se connecter a Docker Hub
docker login -u yassmineg

# Construire et pousser toutes les images (script automatise)
chmod +x k8s/build-and-push.sh
./k8s/build-and-push.sh

# Pousser aussi les images d'infrastructure
docker tag postgres:15-alpine yassmineg/postgres:15-alpine
docker push yassmineg/postgres:15-alpine

docker tag redis:7-alpine yassmineg/redis:7-alpine
docker push yassmineg/redis:7-alpine

docker tag quay.io/keycloak/keycloak:22.0 yassmineg/keycloak:22.0
docker push yassmineg/keycloak:22.0
```

## Etape 3 : Installer ArgoCD sur Minikube

```bash
# Creer le namespace ArgoCD
kubectl create namespace argocd

# Installer ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Attendre que les pods ArgoCD soient prets
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s
```

## Etape 4 : Acceder a ArgoCD

```bash
# Exposer le serveur ArgoCD (laisser tourner dans un terminal)
kubectl port-forward svc/argocd-server -n argocd 8443:443
```

Recuperer le mot de passe admin :

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

Se connecter via CLI :

```bash
argocd login localhost:8443 --username admin --password <mot-de-passe> --insecure
```

Ou acceder a l'interface web : https://localhost:8443 (login: `admin` / mot de passe recupere ci-dessus)

## Etape 5 : Deployer avec ArgoCD

### Option A : Via le manifeste ArgoCD (recommande)

```bash
# Appliquer le manifeste ArgoCD Application
kubectl apply -f k8s/argocd-application.yaml
```

Le fichier `argocd-application.yaml` est configure pour :
- Pointer vers le repo `https://github.com/yassmineg/plateforme_electronique_k8s.git`
- Utiliser le repertoire `k8s/` comme source des manifestes
- Synchronisation automatique avec auto-prune et self-heal
- Creation automatique du namespace `plateforme-electronique`

### Option B : Via la CLI ArgoCD

```bash
argocd app create plateforme-electronique \
  --repo https://github.com/yassmineg/plateforme_electronique_k8s.git \
  --path k8s \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace plateforme-electronique \
  --sync-policy automated \
  --auto-prune \
  --self-heal \
  --sync-option CreateNamespace=true
```

### Option C : Via l'interface web ArgoCD

1. Ouvrir https://localhost:8443
2. Cliquer sur **+ NEW APP**
3. Remplir :
   - **Application Name** : `plateforme-electronique`
   - **Project** : `default`
   - **Sync Policy** : `Automatic`
   - Cocher **PRUNE RESOURCES** et **SELF HEAL**
   - **Repository URL** : `https://github.com/yassmineg/plateforme_electronique_k8s.git`
   - **Path** : `k8s`
   - **Cluster URL** : `https://kubernetes.default.svc`
   - **Namespace** : `plateforme-electronique`
4. Cliquer sur **CREATE**

## Etape 6 : Verifier le deploiement

```bash
# Verifier le statut dans ArgoCD
argocd app get plateforme-electronique

# Verifier les pods Kubernetes
kubectl get pods -n plateforme-electronique

# Attendre que tous les pods soient prets
kubectl wait --for=condition=ready pod --all -n plateforme-electronique --timeout=600s

# Voir tous les resources deployes
kubectl get all -n plateforme-electronique
```

## Etape 7 : Acceder a l'application

```bash
# Frontend (ouvrir dans un autre terminal)
kubectl port-forward -n plateforme-electronique svc/frontend 3000:80

# API Gateway
kubectl port-forward -n plateforme-electronique svc/api-gateway 8080:8080

# Keycloak Admin Console
kubectl port-forward -n plateforme-electronique svc/keycloak 8081:8080

# Eureka Dashboard
kubectl port-forward -n plateforme-electronique svc/eureka-server 8761:8761
```

| Service          | URL                                    | Identifiants      |
|------------------|----------------------------------------|--------------------|
| Frontend         | http://localhost:3000                  | -                  |
| API Gateway      | http://localhost:8080                  | -                  |
| Keycloak Admin   | http://localhost:8081/admin            | admin / admin      |
| Eureka Dashboard | http://localhost:8761                  | -                  |

## Deploiement alternatif sans ArgoCD

```bash
# Appliquer directement avec Kustomize
kubectl apply -k k8s/

# Verifier
kubectl get all -n plateforme-electronique

# Ou utiliser le script de deploiement
chmod +x k8s/deploy.sh
./k8s/deploy.sh
```

## Synchroniser manuellement (ArgoCD)

```bash
# Forcer une synchronisation
argocd app sync plateforme-electronique

# Voir l'historique des syncs
argocd app history plateforme-electronique
```

## Depannage

```bash
# Voir les logs d'un service
kubectl logs -n plateforme-electronique -l app=invoice-service --tail=100 -f

# Decrire un pod en erreur
kubectl describe pod -n plateforme-electronique <nom-du-pod>

# Verifier les events du namespace
kubectl get events -n plateforme-electronique --sort-by='.lastTimestamp'

# Se connecter a PostgreSQL
kubectl exec -it -n plateforme-electronique deploy/postgresql -- psql -U plateforme_user -d invoice_db

# Verifier le statut ArgoCD
argocd app get plateforme-electronique
```

## Nettoyage

```bash
# Supprimer l'application ArgoCD (supprime aussi les ressources Kubernetes)
argocd app delete plateforme-electronique --cascade

# Ou supprimer manuellement
kubectl delete -k k8s/
kubectl delete namespace plateforme-electronique
```

## Structure des fichiers

```
k8s/
  namespace.yaml              # Namespace plateforme-electronique
  secrets.yaml                # Secrets (credentials DB, Keycloak, mail)
  postgres-init-configmap.yaml # Script d'initialisation des bases
  postgres-storage.yaml       # PV et PVC pour PostgreSQL
  redis-storage.yaml          # PV et PVC pour Redis
  postgresql.yaml             # Deployment + Service PostgreSQL
  redis.yaml                  # Deployment + Service Redis
  keycloak.yaml               # Deployment + Service Keycloak
  eureka-server.yaml          # Deployment + Service Eureka
  api-gateway.yaml            # Deployment + Service API Gateway
  invoice-service.yaml        # Deployment + Service Invoice
  payment-service.yaml        # Deployment + Service Payment
  subscription-service.yaml   # Deployment + Service Subscription
  notification-service.yaml   # Deployment + Service Notification
  user-auth-service.yaml      # Deployment + Service User Auth
  signature-service.yaml      # Deployment + Service Signature
  frontend.yaml               # ConfigMap + Deployment + Service Frontend
  kustomization.yaml          # Configuration Kustomize
  argocd-application.yaml     # Manifeste ArgoCD Application
  build-and-push.sh           # Script pour construire et pousser les images
  deploy.sh                   # Script de deploiement direct
```
