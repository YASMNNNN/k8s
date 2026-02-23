# Kubernetes Architecture - Plateforme Électronique

## Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster (Minikube)                     │
│                     Namespace: plateforme-electronique                   │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                              External Access                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────┐              ┌────────────────────┐             │
│  │  LoadBalancer:80   │              │  LoadBalancer:8080 │             │
│  │     Frontend       │              │    API Gateway     │             │
│  └────────────────────┘              └────────────────────┘             │
│           │                                    │                         │
└───────────┼────────────────────────────────────┼─────────────────────────┘
            │                                    │
            ▼                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Frontend & Gateway Layer                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────┐                ┌───────────────────┐              │
│  │   Frontend Pod   │                │  API Gateway Pod  │              │
│  │  React + Nginx   │                │  Spring Gateway   │              │
│  │  Port: 80        │◄───────────────┤  Port: 8080       │              │
│  └──────────────────┘                └───────────────────┘              │
│                                              │                           │
│                                              │ Routes requests           │
└──────────────────────────────────────────────┼───────────────────────────┘
                                               │
                                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Service Discovery Layer                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                      ┌─────────────────────┐                            │
│                      │  Eureka Server Pod  │                            │
│                      │  Service Registry   │                            │
│                      │  Port: 8761         │                            │
│                      └─────────────────────┘                            │
│                               ▲                                          │
│                               │ Service Registration                    │
└───────────────────────────────┼──────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Microservices Layer                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐│
│  │Invoice       │  │Payment       │  │Subscription  │  │Notification ││
│  │Service       │  │Service       │  │Service       │  │Service      ││
│  │Port: 8082    │  │Port: 8083    │  │Port: 8084    │  │Port: 8085   ││
│  │              │  │              │  │              │  │             ││
│  │DB: invoice_db│  │DB: payment_db│  │DB: subscr_db │  │DB: notif_db ││
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬──────┘│
│         │                 │                 │                 │        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                 │
│  │User Auth     │  │Signature     │  │              │                 │
│  │Service       │  │Service       │  │   Redis      │                 │
│  │Port: 8086    │  │Port: 8087    │  │   Cache      │                 │
│  │              │  │              │  │   Port: 6379 │                 │
│  │DB: userauth  │  │              │  │              │                 │
│  └──────┬───────┘  └──────────────┘  └──────┬───────┘                 │
└─────────┼────────────────────────────────────┼──────────────────────────┘
          │                                    │
          │                                    │
          ▼                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        Infrastructure Layer                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────┐    ┌────────────────────────────┐  │
│  │     PostgreSQL Database        │    │      Keycloak IAM          │  │
│  │     Port: 5432                 │    │      Port: 8080            │  │
│  │                                │    │                            │  │
│  │  Databases:                    │◄───┤  OAuth2/OpenID Connect     │  │
│  │  - invoice_db                  │    │  Realm: plateforme-elect.  │  │
│  │  - payment_db                  │    │  Admin: admin/admin        │  │
│  │  - subscription_db             │    │                            │  │
│  │  - notification_db             │    └────────────────────────────┘  │
│  │  - user_auth_db (Keycloak)     │                                    │
│  │                                │                                    │
│  │  PVC: postgres-pvc (10Gi)      │                                    │
│  └────────────────────────────────┘                                    │
│                                                                          │
│  ┌────────────────────────────────┐                                    │
│  │         Redis Cache            │                                    │
│  │         Port: 6379             │                                    │
│  │         PVC: redis-pvc (5Gi)   │                                    │
│  └────────────────────────────────┘                                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                           Persistent Storage                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────────┐              ┌──────────────────────┐        │
│  │  postgres-pv (10Gi)  │              │   redis-pv (5Gi)     │        │
│  │  HostPath: /data/pg  │              │  HostPath: /data/redis│       │
│  └──────────────────────┘              └──────────────────────┘        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Service Communication Flow

```
┌─────────┐        ┌──────────────┐        ┌────────────┐
│ Browser │───────>│  Frontend    │───────>│ API Gateway│
└─────────┘        │  (React)     │        │ (Port 8080)│
                   └──────────────┘        └────────────┘
                                                   │
                                                   │ Route Resolution
                                                   ▼
                                           ┌────────────┐
                                           │   Eureka   │
                                           │  Registry  │
                                           └────────────┘
                                                   │
                   ┌───────────────────────────────┴───────────────┐
                   │                                               │
                   ▼                                               ▼
          ┌─────────────────┐                            ┌─────────────────┐
          │ Invoice Service │                            │ Payment Service │
          │ /api/invoices/* │                            │ /api/payments/* │
          └─────────────────┘                            └─────────────────┘
                   │                                               │
                   ▼                                               ▼
          ┌─────────────────┐                            ┌─────────────────┐
          │  invoice_db     │                            │   payment_db    │
          │  (PostgreSQL)   │                            │   (PostgreSQL)  │
          └─────────────────┘                            └─────────────────┘
```

## ArgoCD GitOps Workflow

```
┌────────────────────────────────────────────────────────────────┐
│                     GitOps Deployment Flow                      │
└────────────────────────────────────────────────────────────────┘

  ┌──────────────┐         ┌──────────────┐         ┌──────────────┐
  │   Developer  │         │     Git      │         │    ArgoCD    │
  │              │         │  Repository  │         │    Server    │
  └──────┬───────┘         └──────┬───────┘         └──────┬───────┘
         │                        │                        │
         │ 1. Push k8s2/         │                        │
         │    manifests          │                        │
         ├───────────────────────>│                        │
         │                        │                        │
         │                        │ 2. Detect changes      │
         │                        │<───────────────────────┤
         │                        │                        │
         │                        │ 3. Pull manifests      │
         │                        ├───────────────────────>│
         │                        │                        │
         │                        │                        │ 4. Compare
         │                        │                        │    desired vs
         │                        │                        │    actual state
         │                        │                        │
         │                        │                        ▼
         │                        │                 ┌──────────────┐
         │                        │                 │  Kubernetes  │
         │                        │                 │   Cluster    │
         │                        │                 └──────┬───────┘
         │                        │                        │
         │                        │ 5. Auto-sync           │
         │                        │    (if enabled)        │
         │                        │<───────────────────────┤
         │                        │                        │
         │  6. Deployment status  │                        │
         │<───────────────────────┴───────────────────────>│
         │                                                 │
         ▼                                                 ▼
   ┌────────────────────────────────────────────────────────┐
   │  Application Running in plateforme-electronique ns     │
   └────────────────────────────────────────────────────────┘
```

## Docker Hub Image Repository

```
Docker Hub (yassmineg/)
├── eureka-server:latest
├── api-gateway:latest
├── invoice-service:latest
├── payment-service:latest
├── subscription-service:latest
├── notification-service:latest
├── user-auth-service:latest
├── signature-service:latest
└── frontend:latest

External Images:
├── postgres:15-alpine
├── redis:7-alpine
└── quay.io/keycloak/keycloak:22.0
```

## Resource Definitions

| Resource Type | Count | Purpose |
|--------------|-------|---------|
| Namespace | 1 | Logical isolation |
| Secret | 1 | Credentials storage |
| ConfigMap | 2 | Configuration data |
| PersistentVolume | 2 | Storage resources |
| PersistentVolumeClaim | 2 | Storage requests |
| Deployment | 12 | Application workloads |
| Service | 12 | Network access |
| **Total Resources** | **32** | |

## Network Architecture

```
External Access (LoadBalancer)
    │
    ├─── frontend (Port 80) ──────────► Nginx serving React
    │
    └─── api-gateway (Port 8080) ─────► Spring Cloud Gateway
              │
              ├─── /api/invoices/** ──────► invoice-service:8082
              ├─── /api/payments/** ──────► payment-service:8083
              ├─── /api/subscriptions/** ─► subscription-service:8084
              ├─── /api/notifications/** ─► notification-service:8085
              └─── /api/users/** ─────────► user-auth-service:8086

Internal Services (ClusterIP)
    │
    ├─── postgresql:5432 ──────────────► PostgreSQL Database
    ├─── redis:6379 ───────────────────► Redis Cache
    ├─── keycloak:8080 ────────────────► Keycloak IAM
    ├─── eureka-server:8761 ───────────► Service Discovery
    └─── signature-service:8087 ───────► Signature Service
```

## Data Flow Example: Creating an Invoice

```
1. User → Frontend (React)
   POST /invoices

2. Frontend → API Gateway
   POST http://api-gateway:8080/api/invoices

3. API Gateway → Eureka Server
   Lookup: invoice-service location

4. API Gateway → Invoice Service
   POST http://invoice-service:8082/invoices

5. Invoice Service → PostgreSQL
   INSERT INTO invoices (invoice_db)

6. Invoice Service → Response
   Return invoice data with ID

7. Invoice Service → Notification Service
   Send email notification (async)

8. Notification Service → SMTP
   Email via Gmail SMTP

9. Response → Frontend
   Display success message
```

## Security Layers

```
┌─────────────────────────────────────────────────┐
│  External Access Control                        │
│  - LoadBalancer services only                   │
│  - Network policies (optional)                  │
└─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│  API Gateway Security                           │
│  - CORS configuration                           │
│  - Rate limiting (Redis)                        │
│  - Request validation                           │
└─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│  Authentication & Authorization                 │
│  - Keycloak OAuth2/OIDC                         │
│  - JWT token validation                         │
│  - Role-based access control                    │
└─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│  Service-Level Security                         │
│  - Spring Security                              │
│  - Database credentials from secrets            │
│  - Service-to-service auth                      │
└─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│  Data Layer Security                            │
│  - Encrypted secrets                            │
│  - Database user isolation                      │
│  - TLS for database connections (optional)      │
└─────────────────────────────────────────────────┘
```

## Deployment States

```
Initial Deployment:
  namespace → secrets → configmaps → storage →
  postgresql → redis → keycloak → eureka-server →
  microservices → frontend

Update Deployment (ArgoCD):
  Git commit → ArgoCD detects change →
  Compare manifests → Apply changes →
  Rolling update → Health checks → Complete

Rollback:
  Detect failure → ArgoCD rollback →
  Restore previous version → Verify health
```

## Monitoring & Observability (To Be Added)

```
┌─────────────────────────────────────────────────┐
│             Observability Stack                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌────────────┐  ┌────────────┐  ┌───────────┐│
│  │ Prometheus │  │  Grafana   │  │   Jaeger  ││
│  │  (Metrics) │→ │ (Dashboard)│  │ (Tracing) ││
│  └────────────┘  └────────────┘  └───────────┘│
│         ▲               ▲                ▲      │
│         └───────────────┴────────────────┘      │
│                         │                       │
└─────────────────────────┼───────────────────────┘
                          │
                          ▼
              ┌──────────────────────┐
              │  Microservices       │
              │  /actuator/metrics   │
              │  /actuator/health    │
              └──────────────────────┘
```

## High Availability Configuration (Production)

```
Replicas for HA:
├── eureka-server: 3 replicas
├── api-gateway: 3 replicas
├── invoice-service: 3 replicas
├── payment-service: 3 replicas
├── subscription-service: 2 replicas
├── notification-service: 2 replicas
├── user-auth-service: 2 replicas
├── signature-service: 2 replicas
├── frontend: 3 replicas
├── postgresql: 1 master + 2 replicas (StatefulSet)
└── redis: 1 master + 2 replicas (Sentinel mode)
```

---

This architecture provides a complete, production-ready Kubernetes deployment for the Plateforme Électronique with GitOps support via ArgoCD.
