# Node Agent

Der **GamePanel Node Agent** ist ein Go-Daemon, der auf jedem Game Node läuft und die Kommunikation zwischen Panel und bare-metal Game-Servern übernimmt. Er ersetzt Docker auf den Nodes — Spiele laufen als **systemd-Units** unter dedizierten Linux-Usern.

## Aufgaben

| Funktion | Beschreibung |
|----------|-------------|
| Registrierung | Node beim Panel anmelden, Token speichern |
| Heartbeat | Alle 30s Metriken senden (CPU, RAM, Load, Disk) |
| Job-Polling | Jobs abholen: install, start, stop, restart, update, backup, restore, kill |
| Image-Download | SFTP/FTPS/FTP vom Image Server |
| Extraktion | Sichere `.tar.zst`-Entpackung mit SHA256-Prüfung |
| systemd | Unit-Generierung, Start/Stop/Restart |
| Firewall | Port-Allocations via nftables/iptables |
| Backups | Server-Verzeichnisse archivieren und wiederherstellen |
| Skripte | Template-Skripte mit Timeout und Sandbox ausführen |

## Installation

### Via Installer

```bash
sudo ./installer/install.sh --role node --config installer/installer.env
```

### Manuell

```bash
cd agent
make build
sudo make install
sudo cp config.example.yaml /opt/gamepanel/agent/config.yaml
sudo cp gamepanel-agent.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now gamepanel-agent
```

## Registrierung

1. Im Panel: **Nodes → Neuer Node** → Registrierungs-Token kopieren
2. Auf dem Node:

```bash
sudo /opt/gamepanel/agent/gamepanel-agent register --token eyJ...
```

Token und Node-ID werden in `config.yaml` persistiert.

## Konfiguration

Datei: `/opt/gamepanel/agent/config.yaml`

```yaml
panel:
  url: "https://panel.example.com"
  timeout: 30s
  tls_insecure: false          # nur für Development

node:
  id: "uuid-vom-panel"
  token: "secret-token"
  name: "node-fra-01"
  fqdn: "node01.example.com"

paths:
  agent_dir: "/opt/gamepanel/agent"
  servers_dir: "/srv/gamepanel/servers"
  images_dir: "/srv/gamepanel/images"
  backups_dir: "/srv/gamepanel/backups"
  steamcmd_dir: "/opt/gamepanel/steamcmd"
  logs_dir: "/var/log/gamepanel"

agent:
  heartbeat_interval: 30s
  job_poll_interval: 10s

systemd:
  unit_prefix: "gamepanel-server"
  slice: "gamepanel.slice"

sftp:
  enabled: true
  host: "10.0.0.10"
  port: 22
  username: "gamepanel-images"
  private_key_path: "/opt/gamepanel/agent/keys/image-server"
  remote_base: "/images"

firewall:
  backend: "nftables"
  table: "gamepanel"
  chain: "allocations"
```

Nach Änderungen:

```bash
sudo systemctl restart gamepanel-agent
```

## CLI-Befehle

```bash
# Daemon starten (normalerweise via systemd)
gamepanel-agent run

# Status anzeigen
gamepanel-agent status

# Systemdiagnose
gamepanel-agent doctor

# Image-Download testen
gamepanel-agent test-image-download \
  --remote games/cs2/versions/1.0.0/cs2-1.0.0.tar.zst \
  --manifest cs2-1.0.0.manifest.yaml

# Server manuell steuern (Debug)
gamepanel-agent server start 42
gamepanel-agent server stop 42
gamepanel-agent server restart 42

# Logs eines Servers
gamepanel-agent logs 42 -n 200 -f
```

## Job-Typen

| Job | Aktion |
|-----|--------|
| `install` | Image laden, extrahieren, systemd Unit erstellen, starten |
| `start` | `systemctl start gamepanel-server-{id}` |
| `stop` | Graceful stop, dann kill nach Timeout |
| `restart` | stop + start |
| `update` | Neues Image laden, Server stoppen, extrahieren, Config behalten |
| `backup` | Server-Verzeichnis als `.tar.zst` archivieren |
| `restore` | Backup entpacken, Server neu starten |
| `kill` | Sofortiger Prozessabbruch (SIGKILL) |
| `reinstall` | Server-Verzeichnis löschen, neu installieren |

### Job-Lebenszyklus

```
Panel erstellt Job → Redis Queue
Agent: GET /api/nodes/{id}/jobs/poll → Job erhalten
Agent führt aus → POST .../jobs/{jobId}/complete oder .../fail
Panel aktualisiert Server-Status
```

## systemd-Integration

Pro Server wird eine Unit generiert:

```ini
[Unit]
Description=GamePanel Server 42 (CS2)
PartOf=gamepanel.slice
After=network-online.target

[Service]
Type=simple
User=gp-s42
Group=gp-s42
WorkingDirectory=/srv/gamepanel/servers/42
ExecStart=/srv/gamepanel/servers/42/start.sh
Restart=on-failure
RestartSec=10

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/srv/gamepanel/servers/42
PrivateTmp=true
LimitNOFILE=65535

[Install]
WantedBy=gamepanel.slice
```

Alle Server-Units gehören zur Slice `gamepanel.slice` — Ressourcenlimits können zentral gesetzt werden.

## Linux-User

Jeder Server erhält einen isolierten User `gp-s{serverId}`:

- Kein Login-Shell (`/usr/sbin/nologin`)
- Zugriff nur auf eigenes Server-Verzeichnis
- Prozesse laufen nie als root

## Firewall (Allocations)

Bei Server-Installation öffnet der Agent automatisch konfigurierte Ports:

```bash
# nftables Regel (Beispiel)
nft add rule gamepanel allocations \
  iifname "eth0" udp dport 27015 counter accept \
  comment "gp-server-42-cs2"
```

Bei Server-Löschung werden Regeln entfernt.

## Image-Download

Priorität: **SFTP → FTPS → FTP**

```yaml
sftp:
  enabled: true
  private_key_path: "/opt/gamepanel/agent/keys/image-server"

ftp:
  enabled: false   # Fallback
  use_tls: true
```

Download mit Resume-Unterstützung und lokalem Cache.

## Backups

Backup-Job:

1. Server stoppen (graceful)
2. `/srv/gamepanel/servers/{id}/` als `.tar.zst` archivieren
3. Nach `/srv/gamepanel/backups/{id}/{timestamp}.tar.zst` speichern
4. Optional: Metadaten an Panel melden
5. Server starten

Restore:

1. Server stoppen
2. Aktuelles Verzeichnis sichern
3. Backup extrahieren
4. Server starten

## Metriken (Heartbeat)

```json
{
  "cpu_percent": 23.5,
  "memory_total": 17179869184,
  "memory_used": 8589934592,
  "load_1": 1.2,
  "load_5": 0.9,
  "load_15": 0.7,
  "disk_total": 500107862016,
  "disk_used": 107374182400,
  "running_servers": 8,
  "agent_version": "1.0.0"
}
```

## Logging

```yaml
logging:
  level: "info"
  format: "json"
  file: "/var/log/gamepanel/agent.log"
```

```bash
journalctl -u gamepanel-agent -f
tail -f /var/log/gamepanel/agent.log
```

## API-Endpunkte (Panel-Seite)

Der Agent erwartet diese Laravel-Routen:

| Methode | Pfad | Beschreibung |
|---------|------|-------------|
| POST | `/api/nodes/register` | Erstregistrierung |
| POST | `/api/nodes/{id}/heartbeat` | Metriken |
| GET | `/api/nodes/{id}/jobs/poll` | Job abholen |
| POST | `/api/nodes/{id}/jobs/{jobId}/complete` | Erfolg melden |
| POST | `/api/nodes/{id}/jobs/{jobId}/fail` | Fehler melden |

Details: [api.md](api.md)

## Troubleshooting

```bash
gamepanel-agent doctor
```

Prüft: Panel-Erreichbarkeit, Token-Gültigkeit, Verzeichnisberechtigungen, systemd, SFTP-Verbindung, nftables, Speicherplatz.

Siehe auch [troubleshooting.md](troubleshooting.md).

## Entwicklung

```bash
cd agent
go mod tidy
make test
make build
make run   # mit config.example.yaml
```

## Weiterführend

- [architecture.md](architecture.md) — Gesamtarchitektur
- [image-system.md](image-system.md) — Image-Format
- [security.md](security.md) — Hardening
