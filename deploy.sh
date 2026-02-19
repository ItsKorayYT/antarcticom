#!/bin/bash

# Antarcticom Deployment Script
#
# Usage:
#   ./deploy.sh community                    # recommended (uses official Auth Hub)
#   ./deploy.sh community https://custom.com # use a custom Auth Hub
#   ./deploy.sh standalone                   # all-in-one (private user pool)
#   ./deploy.sh                              # auto-detect from running containers

set -e

# --- Determine mode ---
MODE="${1:-}"
AUTH_HUB_URL="${2:-${AUTH_HUB_URL:-https://antarctis.xyz}}"

if [ -z "$MODE" ]; then
    # Auto-detect from running containers
    if docker compose -f docker/docker-compose.community.yml ps --status running 2>/dev/null | grep -q "server"; then
        MODE="community"
        echo "auto-detected mode: community (from running containers)"
    elif docker compose -f docker/docker-compose.yml ps --status running 2>/dev/null | grep -q "server"; then
        MODE="standalone"
        echo "auto-detected mode: standalone (from running containers)"
    else
        echo "no running containers found — please specify a mode:"
        echo ""
        echo "  ./deploy.sh community                            # recommended (uses official Auth Hub)"
        echo "  ./deploy.sh community https://custom-hub.com      # use a custom Auth Hub"
        echo "  ./deploy.sh standalone                            # advanced (private user pool)"
        exit 1
    fi
fi

case "$MODE" in
    community)
        COMPOSE_FILE="docker/docker-compose.community.yml"
        export AUTH_HUB_URL
        echo "using Auth Hub: $AUTH_HUB_URL"
        ;;
    standalone)
        COMPOSE_FILE="docker/docker-compose.yml"
        ;;
    *)
        echo "error: unknown mode '$MODE' (use 'community' or 'standalone')"
        exit 1
        ;;
esac

echo "deploying antarcticom ($MODE mode)..."

# --- Pull latest changes ---
echo "pulling latest changes..."
git pull

# --- Build and restart ---
echo "building and restarting containers..."
docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans

echo "pruning unused images..."
docker image prune -f

# --- Wait for healthy server ---
echo "waiting for server to start..."
for i in $(seq 1 120); do
    if curl -sf -o /dev/null http://localhost:8443/health 2>/dev/null; then
        echo "server is healthy! (took ${i}s)"
        break
    fi
    if [ "$i" -eq 120 ]; then
        echo "warning: server did not respond within 120s"
        echo "check logs: docker compose -f $COMPOSE_FILE logs -f server"
    fi
    sleep 1
done

# --- Status ---
echo ""
echo "deployment complete! active containers:"
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "view logs: docker compose -f $COMPOSE_FILE logs -f server"
