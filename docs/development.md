# Entwicklung

Anleitung für lokale Entwicklung am GamePanel-Monorepo.

## Repository-Struktur

```
gamepanel/
├── backend/          # Laravel 12 API
├── frontend/         # Vue 3 SPA
├── agent/            # Go Node Agent
├── image-builder/    # Go Image Builder CLI
├── installer/        # Bash Installer
├── templates/games/  # Game Templates
├── scripts/          # Install/Update Skripte
├── deploy/caddy/     # Reverse Proxy
└── docs/             # Dokumentation
```

## Voraussetzungen

| Tool | Version | Für |
|------|---------|-----|
| Docker & Compose | 24+ / v2 | Panel Stack |
| PHP | 8.2+ | Backend (optional lokal) |
| Composer | 2.x | Backend Dependencies |
| Node.js | 20 LTS | Frontend |
| Go | 1.22+ | Agent, Image Builder |
| Make | — | Shortcut-Targets |

## Schnellstart

```bash
git clone https://github.com/gamepanel/gamepanel.git
cd gamepanel
cp .env.example .env

# Secrets setzen (mindestens POSTGRES_PASSWORD, REDIS_PASSWORD)
# APP_KEY generieren:
docker compose run --rm backend php artisan key:generate

make build
make up
make migrate
```

Panel: `http://localhost`  
API: `http://localhost/api`  
Swagger: `http://localhost/docs`

## Backend (Laravel 12)

### Mit Docker (empfohlen)

```bash
# Shell im Container
make shell-backend

# Migrationen
make migrate

# Tests
make test-backend

# Artisan
docker compose exec backend php artisan <command>

# Queue manuell (wenn Worker nicht läuft)
docker compose exec backend php artisan queue:work

# Code Style
docker compose exec backend ./vendor/bin/pint
```

### Lokal ohne Docker

```bash
cd backend
composer install
cp .env.example .env
php artisan key:generate

# DB/Redis auf localhost zeigen (Ports aus docker-compose.yml)
php artisan migrate
php artisan serve --port=8000
```

Wichtige Packages:

- `laravel/sanctum` — API Auth
- `spatie/laravel-permission` — RBAC
- `darkaonline/l5-swagger` — OpenAPI

Neue Migration:

```bash
docker compose exec backend php artisan make:migration create_example_table
```

Neuen Artisan Command:

```bash
docker compose exec backend php artisan make:command GamepanelExample
```

## Frontend (Vue 3)

```bash
cd frontend
npm install
npm run dev        # Vite Dev Server (Port 5173)
npm run build      # Production Build
npm run lint       # ESLint
```

Entwicklung mit Hot Reload (ohne Docker-Frontend):

```env
# frontend/.env.development
VITE_API_URL=http://localhost:8000/api
VITE_REVERB_HOST=localhost
VITE_REVERB_PORT=8080
```

Für Integration mit Docker-Stack Frontend-Build in Compose nutzen oder Vite-Proxy konfigurieren.

## Go Agent

```bash
cd agent
go mod tidy
make test
make build
# Binary: bin/gamepanel-agent

# Lokal gegen Dev-Panel testen
cp config.example.yaml config.yaml
# panel.url auf localhost zeigen, tls_insecure: true
make run
```

Cross-Compile:

```bash
GOOS=linux GOARCH=amd64 make build
```

systemd Unit generieren:

```bash
make systemd-unit
```

## Image Builder

```bash
cd image-builder
make build
# Binary: bin/gamepanel-image

# Template auflisten
./bin/gamepanel-image list

# Dry-Run Build (benötigt SteamCMD lokal)
GAMEPANEL_TEMPLATES_DIR=../templates/games \
  ./bin/gamepanel-image build minecraft --version dev
```

## Docker Compose Profile

```bash
# Standard Stack
docker compose up -d

# Mit WebSocket (Reverb)
docker compose --profile reverb up -d

# Production Overrides
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Logs
make logs

# Alles stoppen und Volumes löschen
make clean
```

## Tests

```bash
# Alle Tests
make test

# Einzeln
make test-backend
make test-frontend
make test-agent
make test-image-builder
```

Backend-Test einzeln:

```bash
docker compose exec backend php artisan test --filter=ServerTest
```

Agent-Test einzeln:

```bash
cd agent && go test ./internal/images/... -v
```

## Game Templates entwickeln

1. Template in `templates/games/neues-spiel.yaml` anlegen
2. Install-Skript in `scripts/modern/` schreiben
3. Image lokal bauen:

```bash
gamepanel-image build neues-spiel --version dev
gamepanel-image verify neues-spiel --version dev
```

4. Auf Test-Node installieren (Agent `test-image-download`)

Siehe [game-templates.md](game-templates.md).

## API testen

### curl

```bash
# CSRF + Login
curl -c cookies.txt http://localhost/sanctum/csrf-cookie
curl -b cookies.txt -X POST http://localhost/api/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"secret"}'

# Server auflisten
curl -b cookies.txt http://localhost/api/servers
```

### Swagger UI

`http://localhost/docs` — interaktiv testen.

## Git Workflow

```bash
# Feature Branch
git checkout -b feature/mein-feature

# Vor Commit
make test
docker compose exec backend ./vendor/bin/pint

# Commit Message Stil (Conventional Commits empfohlen)
# feat: neue Server-API Endpunkte
# fix: Heartbeat Timeout bei langsamen Nodes
# docs: Installation aktualisiert
```

## Umgebungsvariablen (Entwicklung)

Wichtige `.env`-Werte für lokale Entwicklung:

```env
APP_ENV=local
APP_DEBUG=true
PANEL_DOMAIN=localhost
PANEL_TLS=internal
LOG_LEVEL=debug

# Image Server (optional, für Integrationstests)
GAMEPANEL_IMAGE_SERVER_HOST=10.0.0.10
```

## Debugging

### Laravel

```bash
docker compose exec backend php artisan pail   # Live Logs
docker compose exec backend php artisan tinker
```

### Agent

```yaml
logging:
  level: "debug"
  format: "text"
```

### Docker

```bash
docker compose ps
docker compose logs backend --tail=50
docker stats
```

## Häufige Entwicklungsaufgaben

| Aufgabe | Befehl |
|---------|--------|
| DB zurücksetzen | `docker compose exec backend php artisan migrate:fresh --seed` |
| Cache leeren | `docker compose exec backend php artisan optimize:clear` |
| OpenAPI regenerieren | `docker compose exec backend php artisan l5-swagger:generate` |
| Agent neu bauen | `make agent-build` |
| Stack neu bauen | `make rebuild` |
| System prüfen | `make doctor` |

## Weiterführend

- [architecture.md](architecture.md)
- [api.md](api.md)
- [troubleshooting.md](troubleshooting.md)
