#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  Script : Nettoyage k3d registry + Pull & Push images
#  Conserve les mêmes tags que Docker Hub (yassmineg/)
#  ISET Sousse — Plateforme Electronique
# ═══════════════════════════════════════════════════════════

set -e
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

# ── Configuration ──────────────────────────────────────────
K3D_REGISTRY="k3d-registry.localhost:5111"

# ── Liste complète des images Docker Hub → à charger dans k3d
# Format : "image_dockerhub:tag"
# Le tag dans k3d sera identique
IMAGES=(
  "yassmineg/plateforme_electronique_k8s-api-gateway:latest"
  "yassmineg/plateforme_electronique_k8s-eureka-server:latest"
  "yassmineg/plateforme_electronique_k8s-frontend:latest"
  "yassmineg/plateforme_electronique_k8s-invoice-service:latest"
  "yassmineg/plateforme_electronique_k8s-notification-service:latest"
  "yassmineg/plateforme_electronique_k8s-payment-service:latest"
  "yassmineg/plateforme_electronique_k8s-signature-service:latest"
  "yassmineg/plateforme_electronique_k8s-subscription-service:latest"
  "yassmineg/plateforme_electronique_k8s-user-auth-service:latest"
  "yassmineg/keycloak:latest"
  "yassmineg/postgres:latest"
  "yassmineg/redis:latest"
)

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Clean k3d Registry + Reload images (même tag)         ║"
echo "║   Registry : k3d-registry.localhost:5111                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ══════════════════════════════════════════════════════════
#  ÉTAPE 1 — Supprimer TOUTES les images du registry k3d
# ══════════════════════════════════════════════════════════
echo -e "${YELLOW}╔══ ÉTAPE 1 : Nettoyage du registry k3d ══╗${NC}"

# Récupérer la liste des repos existants
REPOS=$(curl -s "http://${K3D_REGISTRY}/v2/_catalog" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for r in data.get('repositories', []):
    print(r)
")

if [ -z "$REPOS" ]; then
    echo -e "${GREEN}  Registry déjà vide.${NC}"
else
    echo -e "${YELLOW}  Repos trouvés dans le registry :${NC}"
    echo "$REPOS"
    echo ""

    while IFS= read -r REPO; do
        [ -z "$REPO" ] && continue

        # Récupérer tous les tags du repo
        TAGS=$(curl -s "http://${K3D_REGISTRY}/v2/${REPO}/tags/list" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tags = data.get('tags') or []
for t in tags:
    print(t)
" 2>/dev/null)

        if [ -z "$TAGS" ]; then
            echo -e "  ${CYAN}${REPO}${NC} : aucun tag trouvé, ignoré"
            continue
        fi

        while IFS= read -r TAG; do
            [ -z "$TAG" ] && continue

            # Récupérer le digest de l'image
            DIGEST=$(curl -s -I \
                -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
                "http://${K3D_REGISTRY}/v2/${REPO}/manifests/${TAG}" \
                | grep -i "Docker-Content-Digest" \
                | awk '{print $2}' \
                | tr -d '\r')

            if [ -n "$DIGEST" ]; then
                # Supprimer via l'API registry
                HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
                    "http://${K3D_REGISTRY}/v2/${REPO}/manifests/${DIGEST}")

                if [ "$HTTP_CODE" = "202" ]; then
                    echo -e "  ${GREEN}✓ Supprimé : ${REPO}:${TAG}${NC}"
                else
                    echo -e "  ${YELLOW}⚠ ${REPO}:${TAG} — code HTTP: ${HTTP_CODE} (peut nécessiter garbage collect)${NC}"
                fi
            fi
        done <<< "$TAGS"

    done <<< "$REPOS"
fi

# Supprimer aussi les images locales Docker qui traînent
echo ""
echo -e "${YELLOW}  Suppression des images Docker locales taguées k3d...${NC}"
docker images "${K3D_REGISTRY}/*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | \
    xargs -r docker rmi -f 2>/dev/null || true
echo -e "${GREEN}  ✓ Nettoyage local terminé${NC}"

# ══════════════════════════════════════════════════════════
#  ÉTAPE 2 — Pull + Tag + Push toutes les images
# ══════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}╔══ ÉTAPE 2 : Pull → Tag → Push vers k3d ══╗${NC}"

SUCCESS=0
FAILED=0
FAILED_LIST=()
TOTAL=${#IMAGES[@]}
COUNT=0

for IMAGE in "${IMAGES[@]}"; do
    COUNT=$((COUNT + 1))

    # Extraire : repo/name:tag  (sans le "yassmineg/" du début)
    # Le tag dans k3d = même nom complet sans "yassmineg/"
    NAME_TAG="${IMAGE#yassmineg/}"          # ex: plateforme_electronique_k8s-api-gateway:latest
    TARGET="${K3D_REGISTRY}/${NAME_TAG}"    # ex: k3d-registry.localhost:5111/plateforme_electronique_k8s-api-gateway:latest

    echo ""
    echo -e "${BLUE}[$COUNT/$TOTAL] ${IMAGE}${NC}"
    echo -e "         → ${TARGET}"
    echo -e "  ──────────────────────────────────────────"

    # 1. Pull depuis Docker Hub
    echo -e "  ${YELLOW}[1/3] Pull...${NC}"
    if docker pull "${IMAGE}" 2>&1 | tail -1; then
        echo -e "  ${GREEN}✓ Pull OK${NC}"
    else
        echo -e "  ${RED}✗ Pull FAILED — ignoré${NC}"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${IMAGE}")
        continue
    fi

    # 2. Tag
    echo -e "  ${YELLOW}[2/3] Tag...${NC}"
    if docker tag "${IMAGE}" "${TARGET}"; then
        echo -e "  ${GREEN}✓ Tag OK${NC}"
    else
        echo -e "  ${RED}✗ Tag FAILED${NC}"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${IMAGE}")
        continue
    fi

    # 3. Push vers k3d
    echo -e "  ${YELLOW}[3/3] Push...${NC}"
    if docker push "${TARGET}" 2>&1 | tail -3; then
        echo -e "  ${GREEN}✓ Push OK → ${TARGET}${NC}"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "  ${RED}✗ Push FAILED${NC}"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${IMAGE}")
    fi

done

# ══════════════════════════════════════════════════════════
#  ÉTAPE 3 — Vérification finale
# ══════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}╔══ ÉTAPE 3 : Vérification du registry ══╗${NC}"
echo -e "${CYAN}Images disponibles dans ${K3D_REGISTRY} :${NC}"
curl -s "http://${K3D_REGISTRY}/v2/_catalog" | python3 -m json.tool

# ── Résumé ─────────────────────────────────────────────────
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ Succès  : ${SUCCESS} / ${TOTAL}${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}  ✗ Échecs  : ${FAILED} / ${TOTAL}${NC}"
    for img in "${FAILED_LIST[@]}"; do
        echo -e "${RED}    - ${img}${NC}"
    done
fi
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

if [ $SUCCESS -gt 0 ]; then
    echo -e "${GREEN}Les YAML doivent utiliser :${NC}"
    echo -e "${CYAN}  image: ${K3D_REGISTRY}/plateforme_electronique_k8s-api-gateway:latest${NC}"
    echo -e "${CYAN}  image: ${K3D_REGISTRY}/plateforme_electronique_k8s-eureka-server:latest${NC}"
    echo -e "${CYAN}  image: ${K3D_REGISTRY}/plateforme_electronique_k8s-frontend:latest${NC}"
    echo -e "${CYAN}  ... etc${NC}"
    echo ""
    echo -e "${YELLOW}Pour mettre à jour les YAML du repo k8s :${NC}"
    echo -e "  cd ~/k8s"
    echo -e "  find . -name '*.yaml' -exec sed -i 's|yassmineg/|${K3D_REGISTRY}/|g' {} \\;"
    echo -e "  git add . && git commit -m 'fix: use k3d registry' && git push"
    echo -e "  argocd app sync plateforme-electronique"
fi
