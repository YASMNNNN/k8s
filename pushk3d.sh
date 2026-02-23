#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  Script : Pull → Tag → Push vers registry k3d local
#  Plateforme Electronique — ISET Sousse
# ═══════════════════════════════════════════════════════════

set -e
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# ── Configuration ──────────────────────────────────────────
# Nom du registry k3d (vérifier avec : k3d registry list)
K3D_REGISTRY="k3d-registry.localhost:5111"

# Liste des images source Docker Hub
IMAGES=(
  "yassmineg/api-gateway:latest"
  "yassmineg/eureka-server:latest"
  "yassmineg/frontend:latest"
  "yassmineg/invoice-service:latest"
  "yassmineg/keycloak:22.0"
  "yassmineg/notification-service:latest"
  "yassmineg/payment-service:latest"
  "yassmineg/postgres:15-alpine"
  "yassmineg/redis:7-alpine"
  "yassmineg/signature-service:latest"
  "yassmineg/subscription-service:latest"
  "yassmineg/user-auth-service:latest"
)

# ── Vérifier le nom réel du registry k3d ──────────────────
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║   Pull → Tag → Push vers registry k3d               ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}Registries k3d disponibles :${NC}"
k3d registry list
echo ""

# Détecter automatiquement le registry k3d si possible
DETECTED=$(k3d registry list -o json 2>/dev/null | grep -o '"k3d-[^"]*"' | head -1 | tr -d '"' || true)
if [ -n "$DETECTED" ]; then
    # Récupérer le port
    PORT=$(k3d registry list -o json 2>/dev/null | python3 -c "
import sys,json
data=json.load(sys.stdin)
for r in data:
    if 'k3d-' in r.get('name',''):
        ports=r.get('portMappings',{})
        for k,v in ports.items():
            print(v[0]['HostPort'] if isinstance(v,list) else v)
            break
" 2>/dev/null || echo "5000")
    K3D_REGISTRY="k3d-registry.localhost:5111"
    echo -e "${GREEN}Registry détecté automatiquement : ${K3D_REGISTRY}${NC}"
else
    echo -e "${YELLOW}Registry utilisé (défaut) : ${K3D_REGISTRY}${NC}"
    echo -e "${YELLOW}Si incorrect, modifiez la variable K3D_REGISTRY en haut du script${NC}"
fi

echo ""
echo -e "${YELLOW}Démarrage dans 3 secondes... (Ctrl+C pour annuler)${NC}"
sleep 3

# ── Compteurs ──────────────────────────────────────────────
SUCCESS=0
FAILED=0
FAILED_IMAGES=()

# ── Boucle principale ──────────────────────────────────────
TOTAL=${#IMAGES[@]}
COUNT=0

for IMAGE in "${IMAGES[@]}"; do
    COUNT=$((COUNT + 1))
    # Extraire le nom:tag sans le préfixe yassmineg/
    NAME_TAG="${IMAGE#yassmineg/}"

    echo ""
    echo -e "${BLUE}[$COUNT/$TOTAL] Traitement de : ${IMAGE}${NC}"
    echo -e "  ─────────────────────────────────────────"

    # ── 1. Pull depuis Docker Hub ──────────────────────────
    echo -e "  ${YELLOW}[1/3] Pull Docker Hub...${NC}"
    if docker pull "$IMAGE"; then
        echo -e "  ${GREEN}✓ Pull OK${NC}"
    else
        echo -e "  ${RED}✗ Pull FAILED — image ignorée${NC}"
        FAILED=$((FAILED + 1))
        FAILED_IMAGES+=("$IMAGE")
        continue
    fi

    # ── 2. Tag vers le registry k3d ───────────────────────
    TARGET="${K3D_REGISTRY}/${NAME_TAG}"
    echo -e "  ${YELLOW}[2/3] Tag : ${IMAGE} → ${TARGET}${NC}"
    if docker tag "$IMAGE" "$TARGET"; then
        echo -e "  ${GREEN}✓ Tag OK${NC}"
    else
        echo -e "  ${RED}✗ Tag FAILED${NC}"
        FAILED=$((FAILED + 1))
        FAILED_IMAGES+=("$IMAGE")
        continue
    fi

    # ── 3. Push vers le registry k3d ──────────────────────
    echo -e "  ${YELLOW}[3/3] Push → ${TARGET}${NC}"
    if docker push "$TARGET"; then
        echo -e "  ${GREEN}✓ Push OK${NC}"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "  ${RED}✗ Push FAILED${NC}"
        FAILED=$((FAILED + 1))
        FAILED_IMAGES+=("$IMAGE")
    fi

done

# ── Résumé final ───────────────────────────────────────────
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Succès  : $SUCCESS / $TOTAL images${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}✗ Échecs  : $FAILED / $TOTAL images${NC}"
    echo -e "${RED}  Images en erreur :${NC}"
    for img in "${FAILED_IMAGES[@]}"; do
        echo -e "${RED}    - $img${NC}"
    done
fi
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

# ── Vérifier le contenu du registry ───────────────────────
if [ $SUCCESS -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Images disponibles dans le registry k3d :${NC}"
    curl -s "http://${K3D_REGISTRY}/v2/_catalog" 2>/dev/null | python3 -m json.tool || \
    curl -s "http://${K3D_REGISTRY}/v2/_catalog" || \
    echo "(impossible de lister — vérifiez manuellement)"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗"
    echo -e "║  Prochaine étape : mettre à jour les manifestes      ║"
    echo -e "║  Remplacer dans les YAML :                            ║"
    echo -e "║    yassmineg/<service>:<tag>                          ║"
    echo -e "║  Par :                                                ║"
    echo -e "║    ${K3D_REGISTRY}/<service>:<tag>         ║"
    echo -e "╚══════════════════════════════════════════════════════╝${NC}"
fi
