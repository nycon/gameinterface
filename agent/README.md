# GamePanel Node Agent

Produktionsnaher Go-Agent für Bare-Metal Game Nodes. Kommuniziert mit dem Laravel GamePanel über HTTP (Heartbeat, Job-Polling) und verwaltet Game-Server via systemd – ohne Docker.

## Features

- Node-Registrierung und Token-Authentifizierung
- Heartbeat alle 30 Sekunden mit CPU/RAM/Load-Metriken
- Job-Polling: install, start, stop, restart, update, backup, restore, kill
- Linux-User pro Server (`gp-s{serverId}`) – Game-Prozesse laufen nicht als root
- systemd Unit-Generator mit Hardening (NoNewPrivileges, ProtectSystem, cgroups)
- Sichere tar.zst-Extraktion (Path-Traversal-Schutz)
- SFTP (bevorzugt) und FTPS/FTP für Image-Downloads
- SteamCMD-Wrapper, Firewall-Allocations, Backup/Restore
- Script-Runner mit Timeout und Sandbox-Regeln

## Pfade

| Pfad | Zweck |
|------|-------|
| `/opt/gamepanel/agent` | Agent-Binary und Konfiguration |
| `/srv/gamepanel/servers` | Game-Server-Daten |
| `/srv/gamepanel/images` | Heruntergeladene Images |
| `/srv/gamepanel/backups` | Server-Backups |

## Installation

```bash
make build
sudo make install
sudo cp config.example.yaml /opt/gamepanel/agent/config.yaml
# config.yaml anpassen
sudo cp gamepanel-agent.service /etc/systemd/system/
sudo systemctl enable --now gamepanel-agent
```

## CLI

```bash
gamepanel-agent register --token <REGISTRATION_TOKEN>
gamepanel-agent run
gamepanel-agent status
gamepanel-agent doctor
gamepanel-agent test-image-download --remote images/game.tar.zst --manifest manifest.yaml
gamepanel-agent server start <server-id>
gamepanel-agent server stop <server-id>
gamepanel-agent logs <server-id> -n 200
```

## Konfiguration

Siehe `config.example.yaml`. Wichtige Einstellungen:

- `panel.url` – Laravel Panel URL
- `node.token` – wird bei `register` gesetzt
- `agent.heartbeat_interval` – Standard 30s
- `sftp.*` – bevorzugter Image-Transfer

## Entwicklung

```bash
go mod tidy
make test
make build
```

## API-Endpunkte (Panel)

Der Agent erwartet folgende Laravel-API-Routen:

- `POST /api/nodes/register`
- `POST /api/nodes/{id}/heartbeat`
- `GET /api/nodes/{id}/jobs/poll`
- `POST /api/nodes/{id}/jobs/{jobId}/complete`
- `POST /api/nodes/{id}/jobs/{jobId}/fail`

## Lizenz

Proprietär – GamePanel
