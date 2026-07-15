.PHONY: help up down build rebuild logs migrate test agent-build image-build doctor \
        shell-backend shell-postgres ps clean env

COMPOSE ?= docker compose
COMPOSE_FILES ?= -f docker-compose.yml
COMPOSE_PROD ?= $(COMPOSE) $(COMPOSE_FILES) -f docker-compose.prod.yml
COMPOSE_DEV ?= $(COMPOSE) $(COMPOSE_FILES)

help:
	@echo "GamePanel — verfügbare Targets"
	@echo ""
	@echo "  make up            Stack starten (Development)"
	@echo "  make down          Stack stoppen"
	@echo "  make build         Docker-Images bauen"
	@echo "  make rebuild       Images ohne Cache neu bauen"
	@echo "  make migrate       Laravel-Migrationen ausführen"
	@echo "  make test          Backend-, Frontend- und Go-Tests"
	@echo "  make agent-build   Go Node-Agent kompilieren"
	@echo "  make image-build   Image-Builder CLI kompilieren"
	@echo "  make doctor        System- und Stack-Prüfung"
	@echo "  make logs          Container-Logs folgen"
	@echo "  make env           .env aus .env.example erzeugen (falls fehlend)"
	@echo ""
	@echo "Production: COMPOSE=\"docker compose -f docker-compose.yml -f docker-compose.prod.yml\" make up"

env:
	@test -f .env || cp .env.example .env
	@echo ".env bereit — bitte Secrets anpassen (APP_KEY, POSTGRES_PASSWORD, REDIS_PASSWORD)."

up: env
	$(COMPOSE_DEV) up -d

down:
	$(COMPOSE_DEV) down

build:
	$(COMPOSE_DEV) build

rebuild:
	$(COMPOSE_DEV) build --no-cache

logs:
	$(COMPOSE_DEV) logs -f --tail=100

migrate:
	$(COMPOSE_DEV) exec backend php artisan migrate --force

test: test-backend test-frontend test-agent test-image-builder

test-backend:
	$(COMPOSE_DEV) exec -T backend php artisan test || (cd backend && php artisan test)

test-frontend:
	@if [ -f frontend/package.json ]; then cd frontend && npm test --if-present; else echo "Frontend-Tests übersprungen (noch nicht eingerichtet)"; fi

test-agent:
	cd agent && go test ./...

test-image-builder:
	cd image-builder && go test ./...

agent-build:
	$(MAKE) -C agent build

image-build:
	$(MAKE) -C image-builder build

# Image-Builder auf Linux-Host (Image-Server) inkl. Go/SteamCMD
image-builder-install:
	sudo bash installer/install-image-builder.sh


doctor:
	@echo "=== GamePanel Doctor ==="
	@command -v docker >/dev/null 2>&1 && echo "[OK] docker" || echo "[FEHLER] docker nicht gefunden"
	@command -v docker compose >/dev/null 2>&1 && echo "[OK] docker compose" || echo "[FEHLER] docker compose nicht gefunden"
	@command -v go >/dev/null 2>&1 && echo "[OK] go $$(go version | awk '{print $$3}')" || echo "[WARN] go nicht gefunden (Agent-Build lokal nicht möglich)"
	@test -f .env && echo "[OK] .env vorhanden" || echo "[WARN] .env fehlt — 'make env' ausführen"
	@test -f deploy/nginx/nginx.conf && echo "[OK] nginx.conf vorhanden" || echo "[FEHLER] deploy/nginx/nginx.conf fehlt"
	@$(COMPOSE_DEV) ps 2>/dev/null || true
	@test -x installer/doctor.sh && sudo installer/doctor.sh || echo "[INFO] installer/doctor.sh für Node/Image-Server-Checks"

shell-backend:
	$(COMPOSE_DEV) exec backend sh

shell-postgres:
	$(COMPOSE_DEV) exec postgres psql -U $${POSTGRES_USER:-gamepanel} -d $${POSTGRES_DB:-gamepanel}

ps:
	$(COMPOSE_DEV) ps

clean:
	$(COMPOSE_DEV) down -v --remove-orphans
