# GamePanel

**Open Source Gameserver Interface** — eine moderne, selbst gehostete Verwaltungsplattform für dedizierte Game-Server.

GamePanel trennt bewusst **Control Plane** (Panel in Docker) und **Data Plane** (Game-Server bare-metal auf Nodes mit systemd). Spiele laufen nicht im Panel-Container, sondern als isolierte systemd-Units auf dedizierten Hosts. Der Go-basierte **Node Agent** übernimmt Installation, Updates, Backups und Prozesssteuerung vor Ort.

## Architektur auf einen Blick

```
┌─────────────────────────────────────────────────────────────┐
│  Panel-Server (Docker Compose)                              │
│  Nginx → Vue 3 Frontend + Laravel 12 API + Worker/Scheduler │
│  PostgreSQL 16 · Redis 7 · Laravel Reverb (Live-Konsole)    │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTPS (API, Jobs, Heartbeat)
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
   ┌───────────┐    ┌─────────────┐   ┌──────────────┐
   │ Game Node │    │ Game Node   │   │ Image Server │
   │ + Agent   │    │ + Agent     │   │ SFTP/FTPS    │
   │ systemd   │    │ systemd     │   │ (kein S3)    │
   └───────────┘    └─────────────┘   └──────────────┘
```

## Features

- **Web-UI** (Vue 3) — Server erstellen, Konsole, Dateien, Backups, DBs, SFTP-Accounts
- **Live-Konsole** via Laravel Reverb (WebSocket) + Agent-Events
- **REST-API** (Laravel 12 + Sanctum) inkl. 2FA (TOTP) und Reseller-Scope
- **Bare-Metal Game Nodes** — kein Docker für Spieleprozesse, systemd-Hardening
- **Go Node Agent** — Jobs inkl. Files/DB/FTP/Backup/Install end-to-end
- **Image-System** — Teklab-ähnliche `.tar.zst`-Archive mit `.lst`, `.sha256` und Manifest
- **Image-Transfer per SFTP/FTPS/FTP** — bewusst **kein MinIO/S3**
- **Game Templates** — YAML-basierte Definitionen (Minecraft, CS2, Rust, Valheim, ARK, …)
- **Easy-WI-inspirierter Installer** — interaktiv oder non-interactive für Panel, Node und Image-Server
- **Image Builder CLI** — SteamCMD-Updates, Archivierung, Veröffentlichung

## Repository-Struktur

| Pfad | Beschreibung |
|------|--------------|
| `backend/` | Laravel 12 API, Queues, Reverb, Datenmodell |
| `frontend/` | Vue 3 SPA |
| `agent/` | Go Node Agent für Game Nodes |
| `image-builder/` | CLI zum Erstellen und Publizieren von Images |
| `installer/` | Bash-Installer (Panel, Node, Image-Server, Standalone) |
| `templates/games/` | Game-Template-Definitionen (YAML) |
| `scripts/` | Install-/Update-Skripte für einzelne Spiele |
| `deploy/nginx/` | Nginx Reverse-Proxy-Konfiguration |
| `docs/` | Projekt-Dokumentation (Deutsch) |

## Schnellstart (Entwicklung)

### Voraussetzungen

- Docker & Docker Compose v2
- Make
- Optional: Go 1.22+ (Agent/Image-Builder lokal bauen)

### Panel starten

```bash
git clone https://github.com/gamepanel/gamepanel.git
cd gamepanel
cp .env.example .env
# Secrets setzen: APP_KEY, POSTGRES_PASSWORD, REDIS_PASSWORD
make build
make up
make migrate
```

Panel erreichbar unter `https://127.0.0.1:8443` (Nginx + SSL) bzw. `http://127.0.0.1:8080`.

Live-Konsole nutzt Reverb (Standard im Compose-Stack):

```bash
./install.sh --role panel-local
# oder: docker compose up -d
```

### Node Agent bauen

```bash
make agent-build
# Binary: agent/bin/gamepanel-agent
```

### Image Builder bauen

```bash
make image-build
# Binary: image-builder/bin/gamepanel-image
```

## Schnellstart Panel (jetzt)

Mit laufendem Docker:

```bash
./install.sh --role panel-local
```

Danach:

- UI: http://127.0.0.1:8080/
- Login: `admin@gamepanel.local` / `ChangeMe!2026`

Stoppen: `docker compose down`

## Production-Deployment (3 VMs)

Panel-first wie Pterodactyl — **kein Datei-Kopieren zwischen VMs**.

| VM | Rolle | Beispiel |
|----|--------|----------|
| VM1 | Panel (Docker) | `10.0.0.10` / `panel.example.com` |
| VM2 | Image-Server (SFTP) | `10.0.0.11` |
| VM3 | Game-Node (Agent + systemd) | `10.0.0.12` |

```bash
# 1) Nur Panel
sudo ./install.sh --role panel --non-interactive \
  --domain panel.example.com --ssl-mode selfsigned \
  --admin-email admin@example.com --admin-password 'StrongPass!2026'

# 2) Im Panel: Image-Server anlegen → curl-Befehl auf VM2 ausführen
# 3) Im Panel: Node anlegen → curl-Befehl auf VM3 ausführen
```

**Vollständige Anleitung:** [docs/deploy-3vm.md](docs/deploy-3vm.md)

Weitere Details: [docs/installation.md](docs/installation.md) und [docs/installer.md](docs/installer.md).

## Dokumentation

| Dokument | Inhalt |
|----------|--------|
| [deploy-3vm.md](docs/deploy-3vm.md) | **3-VM Installation (Panel / Image / Node)** |
| [architecture.md](docs/architecture.md) | Systemarchitektur und Datenflüsse |
| [installation.md](docs/installation.md) | Manuelle Installation Panel/Node/Image-Server |
| [installer.md](docs/installer.md) | Easy-WI-ähnlicher Installer |
| [image-server.md](docs/image-server.md) | SFTP/FTPS Image-Server einrichten |
| [image-system.md](docs/image-system.md) | Archive, Manifeste, Checksummen |
| [node-agent.md](docs/node-agent.md) | Go Agent Konfiguration und Betrieb |
| [game-templates.md](docs/game-templates.md) | Spiele-Templates definieren |
| [security.md](docs/security.md) | Hardening, Auth, Netzwerk |
| [api.md](docs/api.md) | REST-API Übersicht |
| [development.md](docs/development.md) | Lokale Entwicklung |
| [troubleshooting.md](docs/troubleshooting.md) | Fehlerbehebung |

## Makefile-Targets

```bash
make up            # Stack starten
make down          # Stack stoppen
make build         # Docker-Images bauen
make migrate       # DB-Migrationen
make test          # Tests (Backend, Frontend, Go)
make agent-build   # Node Agent kompilieren
make image-build   # Image Builder kompilieren
make doctor        # System- und Stack-Prüfung
```

## Technologie-Stack

| Komponente | Technologie |
|------------|-------------|
| Backend | PHP 8.2+, Laravel 12, Sanctum, Spatie Permission |
| Frontend | Vue 3, Vite, TypeScript |
| Datenbank | PostgreSQL 16 |
| Cache/Queue | Redis 7 |
| Reverse Proxy | Nginx |
| Node Agent | Go (systemd, SFTP, nftables) |
| Image Builder | Go (SteamCMD, tar.zst, Ed25519-Signatur) |
| Game Runtime | systemd auf Linux (bare-metal) |

## Lizenz

MIT License — Copyright 2026 GamePanel Contributors. Siehe [LICENSE](LICENSE).

## Mitwirken

Issues und Pull Requests sind willkommen. Bitte zuerst [docs/development.md](docs/development.md) lesen.
