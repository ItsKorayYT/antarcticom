#!/bin/bash

# Antarcticom Deployment Script
# Usage: ./deploy.sh

set -e

echo "deploying antarcticom..."

# 1. Pull latest changes
echo "pulling latest changes..."
git pull

# 2. Build and restart containers
echo "building and restarting containers..."
# Use docker compose if available, otherwise docker-compose
if command -v docker >/dev/null 2>&1; then
    docker compose -f docker/docker-compose.yml up -d --build --remove-orphans
else
    docker-compose -f docker/docker-compose.yml up -d --build --remove-orphans
fi

echo "pruning unused images..."
docker image prune -f

echo "deployment complete! active containers:"
if command -v docker >/dev/null 2>&1; then
    docker compose -f docker/docker-compose.yml ps
else
    docker-compose -f docker/docker-compose.yml ps
fi

echo "logs can be viewed with: docker compose -f docker/docker-compose.yml logs -f"
