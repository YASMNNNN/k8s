#!/bin/bash

# Script to build and push all Docker images to Docker Hub
# Usage: ./build-and-push.sh

set -e

DOCKER_USERNAME="yassmineg"
TAG="latest"

echo "=========================================="
echo "Building and pushing Docker images"
echo "Docker Hub username: ${DOCKER_USERNAME}"
echo "Tag: ${TAG}"
echo "=========================================="

# Array of services to build
SERVICES=(
    "eureka-server"
    "api-gateway"
    "invoice-service"
    "payment-service"
    "subscription-service"
    "notification-service"
    "user-auth-service"
    "signature-service"
)

# Build and push backend services
for service in "${SERVICES[@]}"; do
    echo ""
    echo "Building ${service}..."
    docker build -t ${DOCKER_USERNAME}/${service}:${TAG} ./services/${service}

    echo "Pushing ${service} to Docker Hub..."
    docker push ${DOCKER_USERNAME}/${service}:${TAG}

    echo "✓ ${service} completed"
done

# Build and push frontend
echo ""
echo "Building frontend..."
docker build -t ${DOCKER_USERNAME}/frontend:${TAG} ./frontend

echo "Pushing frontend to Docker Hub..."
docker push ${DOCKER_USERNAME}/frontend:${TAG}

echo "✓ frontend completed"

echo ""
echo "=========================================="
echo "All images built and pushed successfully!"
echo "=========================================="
echo ""
echo "Images pushed:"
for service in "${SERVICES[@]}"; do
    echo "  - ${DOCKER_USERNAME}/${service}:${TAG}"
done
echo "  - ${DOCKER_USERNAME}/frontend:${TAG}"
echo ""
echo "You can now deploy to Kubernetes with:"
echo "  kubectl apply -k k8s/"
echo "Or sync with ArgoCD"
