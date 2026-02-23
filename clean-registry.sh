#!/bin/bash
REGISTRY="k3d-registry.localhost:5111"

REPOS=$(curl -s "http://${REGISTRY}/v2/_catalog" | python3 -c "
import sys,json
for r in json.load(sys.stdin).get('repositories',[]):
    print(r)
")

while IFS= read -r REPO; do
    [ -z "$REPO" ] && continue
    TAGS=$(curl -s "http://${REGISTRY}/v2/${REPO}/tags/list" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for t in (data.get('tags') or []):
    print(t)
")
    while IFS= read -r TAG; do
        [ -z "$TAG" ] && continue
        DIGEST=$(curl -s -I \
            -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
            "http://${REGISTRY}/v2/${REPO}/manifests/${TAG}" \
            | grep -i "docker-content-digest" | awk '{print $2}' | tr -d '\r')
        if [ -n "$DIGEST" ]; then
            CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
                "http://${REGISTRY}/v2/${REPO}/manifests/${DIGEST}")
            echo "$CODE — supprimé : ${REPO}:${TAG}"
        fi
    done <<< "$TAGS"
done <<< "$REPOS"

echo ""
echo "Contenu restant :"
curl -s "http://${REGISTRY}/v2/_catalog"
