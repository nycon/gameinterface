# Architektur

GamePanel ist ein **Open Source Gameserver Interface** mit klarer Trennung zwischen zentraler Verwaltung (Panel) und dezentraler Ausführung (Game Nodes). Dieses Dokument beschreibt Komponenten, Datenflüsse und Designentscheidungen.

## Designprinzipien

1. **Panel containerisiert, Spiele nicht** — Laravel, Vue, PostgreSQL und Redis laufen in Docker. Game-Prozesse laufen nativ auf Nodes unter systemd, weil Spiele niedrige Latenz, direkten Hardwarezugriff und stabile Prozess-Isolation benötigen.
2. **Pull-basierte Node-Steuerung** — Der Go Agent pollt Jobs vom Panel; eingehende Verbindungen auf Nodes sind nicht erforderlich (Firewall-freundlich).
3. **Dateibasierte Images statt Object Storage** — Game-Images werden als `.tar.zst`-Archive über SFTP/FTPS/FTP bereitgestellt. MinIO/S3 wird bewusst nicht verwendet; ein einfacher Linux-Host mit SSH genügt.
4. **Teklab-kompatibles Image-Format** — Archive mit `.lst` (Dateiliste), `.sha256` (Checksumme) und YAML-Manifest für reproduzierbare Installationen.
5. **Template-getriebene Spiele** — Jedes Spiel wird über YAML-Templates (`templates/games/`) definiert; der Image Builder und Agent interpretieren diese einheitlich.

## Komponentenübersicht

### Panel Stack (Docker Compose)

| Service | Rolle |
|---------|-------|
| **proxy (Nginx)** | Reverse Proxy, Routing zu Frontend/API/Reverb |
| **frontend** | Vue 3 SPA (nginx) |
| **backend** | Laravel 12 REST-API, Auth, Business-Logik |
| **postgres** | PostgreSQL 16 — persistente Daten |
| **redis** | Cache, Sessions, Queues |
| **worker** | `queue:work` — asynchrone Jobs (Image-Build-Anfragen, Benachrichtigungen) |
| **scheduler** | `schedule:work` — Cron-ähnliche Panel-Aufgaben |
| **reverb** (optional) | Laravel Reverb WebSocket-Server für Live-Events |

### Game Node (bare-metal)

Jeder Node hostet:

- **gamepanel-agent** — Go-Daemon unter systemd
- **systemd Units** pro Game-Server (`gamepanel-server-{id}.service`)
- **Linux-User** pro Server (`gp-s{serverId}`) — Prozesse laufen nicht als root
- **Verzeichnisstruktur** unter `/srv/gamepanel/`

| Pfad | Inhalt |
|------|--------|
| `/opt/gamepanel/agent` | Agent-Binary, Konfiguration |
| `/srv/gamepanel/servers/{id}` | Server-Daten, Konfiguration, Welten |
| `/srv/gamepanel/images` | Heruntergeladene Image-Archive (Cache) |
| `/srv/gamepanel/backups` | Lokale Backups |

### Image Server (bare-metal)

Dedizierter Host (kann mit einem Node kombiniert werden in kleinen Setups):

- **SFTP** (bevorzugt, `internal-sftp` via OpenSSH)
- optional **FTPS** (vsftpd) oder **FTP** (ProFTPd)
- Verzeichnisbaum unter `/srv/gamepanel-images/games/{slug}/versions/{version}/`
- zentraler `index.json` für verfügbare Images

### Image Builder (CLI)

Entwickler-/Admin-Tool zum Erstellen von Images:

1. Template laden (`templates/games/*.yaml`)
2. SteamCMD oder Custom-Skript ausführen
3. `.tar.zst` archivieren mit `.lst` und `.sha256`
4. Manifest generieren (optional Ed25519-signiert)
5. per FTP/SFTP publizieren

## Datenflüsse

### Server-Installation

```
Benutzer (UI) → Laravel API → Job in Redis Queue
                                    ↓
                              Worker persistiert Job
                                    ↓
Node Agent pollt GET /api/nodes/{id}/jobs/poll
                                    ↓
Agent: Image von SFTP laden → SHA256 prüfen → tar.zst extrahieren
                                    ↓
systemd Unit generieren → Server-User anlegen → Firewall-Port öffnen
                                    ↓
POST /api/nodes/{id}/jobs/{jobId}/complete
```

### Heartbeat & Metriken

Alle 30 Sekunden (konfigurierbar):

```
Agent → POST /api/nodes/{id}/heartbeat
  { cpu, memory, load, disk, running_servers, agent_version }
Panel aktualisiert Node-Status in PostgreSQL
```

### Image-Update

```
Admin triggert Update → Panel erstellt Job "update"
Agent lädt neue Version vom Image-Server
Stoppt Server → extrahiert neues Image → startet Server neu
```

## Netzwerkmodell

```
Internet
   │
   ▼
[Caddy :443] ──► Frontend (Vue)
              └──► Backend API (/api/*)
              └──► Reverb WS (/app/*) [optional]

Panel ──HTTPS──► Node Agent (ausgehend, Poll + Heartbeat)
Node Agent ──SFTP──► Image Server (ausgehend, Image-Download)
Spieler ──UDP/TCP──► Game Node (Spiel-Ports, nftables Allocations)
```

**Wichtig:** Nodes initiieren Verbindungen zum Panel. Kein eingehender Agent-Port zum Internet nötig (optionaler Debug-Port 9100 nur intern).

## Authentifizierung

| Beziehung | Mechanismus |
|-----------|-------------|
| Benutzer → Panel | Laravel Sanctum (Session/Token) |
| Agent → Panel | Node-Token (bei Registrierung ausgestellt) |
| Agent → Image Server | SSH-Key (SFTP) oder FTP-Credentials |
| API-Dokumentation | OpenAPI/Swagger (`/docs`) |

## Skalierung

- **Horizontal:** Mehrere Game Nodes; Panel verteilt Server per Allocation-Algorithmus (Auslastung, Standort, Tags).
- **Panel-HA:** PostgreSQL Replikation + mehrere Backend-Instanzen hinter Load Balancer (manuell; Compose-Stack ist Single-Node).
- **Image-Server:** Ein zentraler Server reicht für die meisten Setups; große Anbieter können mehrere Mirror per DNS Round-Robin betreiben.

## Was bewusst nicht verwendet wird

- **Docker für Game-Server** — Overhead, cgroups-Konflikte, schlechtere Performance bei UDP-lastigen Spielen.
- **MinIO/S3** — unnötige Komplexität; SFTP auf einem Linux-Host ist ausreichend und in der Hosting-Branche etabliert (Teklab, Easy-WI-Tradition).
- **Kubernetes für Panel** — Docker Compose + Installer decken Zielgruppe (Game-Hoster, Homelab) ab.

## Weiterführende Dokumente

- [installation.md](installation.md) — Deployment-Schritte
- [node-agent.md](node-agent.md) — Agent-Details
- [image-system.md](image-system.md) — Image-Format
- [security.md](security.md) — Hardening
