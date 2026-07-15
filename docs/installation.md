# Installation

Dieses Dokument beschreibt die manuelle Installation aller GamePanel-Komponenten. Für automatisierte Setups siehe [installer.md](installer.md).

## Übersicht der Rollen

| Rolle | Host | Deployment |
|-------|------|------------|
| Panel | Dedizierter Server oder VM | Docker Compose |
| Game Node | Dedizierter Server pro Standort | bare-metal + systemd |
| Image Server | Dedizierter Server (oder kombiniert) | bare-metal + OpenSSH/vsftpd |

**Minimales Setup:** 1 Panel-Server + 1 Game Node + 1 Image Server (Image Server kann auf dem Node liegen).

**Empfohlenes Setup:** Panel separat, Image Server separat, mehrere Nodes.

## Systemanforderungen

### Panel-Server

- Ubuntu 22.04/24.04 LTS oder Debian 12
- 2 vCPU, 4 GB RAM, 40 GB SSD
- Docker Engine 24+ und Docker Compose v2
- Öffentliche Domain mit DNS A/AAAA-Record (Production)

### Game Node

- Ubuntu 22.04/24.04 LTS (empfohlen)
- 4+ vCPU, 8+ GB RAM (spielabhängig)
- systemd, nftables oder iptables
- Ausgehende HTTPS-Verbindung zum Panel
- Ausgehende SFTP zum Image Server

### Image Server

- Ubuntu/Debian, 20+ GB freier Speicher (spielabhängig)
- OpenSSH Server
- Optional: vsftpd (FTPS) oder ProFTPd

## Panel installieren (Docker Compose)

### 1. Repository klonen

```bash
git clone https://github.com/gamepanel/gamepanel.git /opt/gamepanel-src
cd /opt/gamepanel-src
```

### 2. Umgebung konfigurieren

```bash
cp .env.example .env
```

Pflichtwerte setzen:

```bash
# Starke Secrets generieren
openssl rand -base64 32   # für POSTGRES_PASSWORD
openssl rand -base64 32   # für REDIS_PASSWORD

# Laravel App Key
docker compose run --rm backend php artisan key:generate --show
# Wert in APP_KEY eintragen
```

Weitere wichtige Variablen:

| Variable | Beispiel | Beschreibung |
|----------|----------|-------------|
| `PANEL_DOMAIN` | `panel.example.com` | Öffentliche Domain |
| `PANEL_TLS` | `acme` | Let's Encrypt (Production) |
| `APP_URL` | `https://panel.example.com` | Laravel Base URL |
| `GAMEPANEL_IMAGE_SERVER_HOST` | `10.0.0.10` | Image-Server IP/Hostname |

### 3. Stack starten

**Entwicklung:**

```bash
make build
make up
make migrate
```

**Production:**

```bash
export BACKEND_IMAGE=ghcr.io/gamepanel/backend:latest
export FRONTEND_IMAGE=ghcr.io/gamepanel/frontend:latest
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
docker compose exec backend php artisan migrate --force
```

### 4. Admin-Benutzer anlegen

```bash
docker compose exec backend php artisan gamepanel:admin:create \
  --email=admin@example.com \
  --password='SicheresPasswort!' \
  --name=Administrator
```

Falls der Artisan-Command noch nicht existiert, über Tinker:

```bash
docker compose exec backend php artisan tinker
# User::create([...]) mit is_admin=true
```

### 5. Firewall (Panel-Server)

```bash
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

PostgreSQL und Redis sind in Production **nicht** nach außen exposed (`docker-compose.prod.yml`).

## Image Server installieren

Siehe [image-server.md](image-server.md) für Details. Kurzform:

```bash
sudo ./installer/install.sh --role image-server --config installer/installer.env
```

Oder manuell:

1. Benutzer `gamepanel-images` anlegen
2. `/srv/gamepanel-images/games/` Verzeichnisstruktur erstellen
3. SFTP-Chroot für den Benutzer konfigurieren (OpenSSH `internal-sftp`)
4. SSH Public Key des Panel/Agents autorisieren

## Game Node installieren

```bash
sudo ./installer/install.sh --role node --config installer/installer.env
```

Nach der Installation:

1. Im Panel einen neuen Node anlegen → Registrierungs-Token erhalten
2. Auf dem Node registrieren:

```bash
sudo /opt/gamepanel/agent/gamepanel-agent register --token <REGISTRATION_TOKEN>
sudo systemctl enable --now gamepanel-agent
```

3. Node-Status im Panel prüfen (Heartbeat grün)

## Standalone-Installation (All-in-One)

Für Homelab oder kleine Setups:

```bash
# installer.env anpassen:
# GP_ROLE=standalone
# STANDALONE_INSTALL_NODE=yes
sudo ./installer/install.sh --role standalone --config installer/installer.env
```

Installiert Panel (Docker), optional Node Agent und optional Image Server auf einem Host.

## WebSocket (Reverb) aktivieren

In `.env`:

```env
REVERB_ENABLED=true
REVERB_APP_KEY=<generiert>
REVERB_APP_SECRET=<generiert>
BROADCAST_CONNECTION=reverb
```

Stack mit Profil starten:

```bash
docker compose --profile reverb up -d
```

Frontend-Build-Args müssen `VITE_REVERB_*` enthalten (siehe `.env.example`).

## Post-Installation Checkliste

- [ ] Panel unter `https://panel.example.com` erreichbar
- [ ] Admin-Login funktioniert
- [ ] Node zeigt Heartbeat im Panel
- [ ] Test-Image auf Image Server hochgeladen
- [ ] Test-Server Installation erfolgreich
- [ ] Backup-Job getestet
- [ ] `make doctor` / `installer/doctor.sh` ohne kritische Fehler

## Upgrade

Panel:

```bash
cd /opt/gamepanel-src
git pull
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
docker compose exec backend php artisan migrate --force
```

Node Agent:

```bash
sudo ./installer/upgrade.sh --component agent
```

## Weiterführend

- [installer.md](installer.md) — Automatisierter Installer
- [node-agent.md](node-agent.md) — Agent-Konfiguration
- [troubleshooting.md](troubleshooting.md) — Fehlerbehebung
