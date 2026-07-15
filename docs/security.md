# Sicherheit

GamePanel folgt dem Prinzip **Defense in Depth**: Panel, Nodes und Image Server haben unterschiedliche Angriffsflächen und werden entsprechend gehärtet.

## Architektur-Sicherheit

### Trennung der Rollen

| Komponente | Angriffsfläche | Maßnahmen |
|------------|---------------|-----------|
| Panel (Docker) | Web, API | TLS, Auth, Rate Limiting |
| Game Node | Spieleprozesse, Agent | User-Isolation, systemd Hardening |
| Image Server | SFTP/FTP | Chroot, Key-Auth, internes Netz |

### Netzwerk

- Panel nur über HTTPS (Nginx + Zertifikate vom Installer: Self-Signed oder Let's Encrypt)
- **2FA (TOTP)** optional pro Benutzer (Login-Challenge)
- Rolle **Reseller** mit Scope auf eigene Kunden/Server
- Nodes initiieren **ausgehende** Verbindungen zum Panel — kein eingehender Agent-Port nötig
- Image Server nur im internen Netz erreichbar
- PostgreSQL/Redis in Production **nicht** nach außen exposed
- Game-Ports (UDP/TCP) nur für Spieler-Traffic geöffnet

```
Internet → Nginx:443 → Panel (internes Docker-Netz)
Nodes → HTTPS → Panel API (ausgehend)
Nodes → SFTP → Image Server (ausgehend)
Spieler → UDP/TCP → Game Ports (nftables Allocations)
```

## Panel-Sicherheit

### Authentifizierung

- **Laravel Sanctum** für SPA-Auth (Session + CSRF)
- API-Token für externe Integrationen (scoped, expiring)
- Passwort-Policy konfigurierbar (min. Länge, Komplexität)
- Optional: 2FA (geplant)

### Autorisierung

- **Spatie Laravel Permission** — Rollen und Permissions
- Standard-Rollen: Admin, Reseller, User
- Server-Zugriff nur für Besitzer und explizit Berechtigte
- Node-Verwaltung nur für Admins

### Laravel Hardening

```env
APP_DEBUG=false          # Production
APP_ENV=production
SESSION_SECURE_COOKIE=true
SESSION_SAME_SITE=lax
SANCTUM_STATEFUL_DOMAINS=panel.example.com
```

- CSRF-Schutz für Web-Routen
- SQL Injection: Eloquent ORM + Prepared Statements
- XSS: Vue 3 Auto-Escaping + CSP Header (Caddy)
- Mass Assignment: `$fillable` / `$guarded` auf allen Models

### Docker

- Non-root User im Backend-Container
- Read-only Filesystem wo möglich
- Secrets über `.env`, nicht in Images
- Regelmäßige Base-Image Updates

### Rate Limiting

Laravel Throttle Middleware auf:

- Login: 5 Versuche/Minute
- API: 60 Requests/Minute (authentifiziert)
- Node Register: 3/Stunde pro IP

## Node Agent Sicherheit

### Prozess-Isolation

- Jeder Game-Server als eigener Linux-User (`gp-s{id}`)
- systemd Hardening:

```ini
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
RestrictSUIDSGID=true
RestrictNamespaces=true
```

- Alle Server in `gamepanel.slice` — zentrale Ressourcenlimits

### Agent-Privilegien

Der Agent läuft als **root** (systemd Unit-Management, User-Erstellung, Firewall). Minimale Privilegien:

- Kein Shell-Zugang für Game-User
- Skript-Ausführung mit Sandbox:

```yaml
scripts:
  timeout: 5m
  allowed_interpreters:
    - "/bin/bash"
    - "/bin/sh"
  sandbox:
    drop_capabilities: true
    no_new_privileges: true
```

### Image-Integrität

1. **SHA256** — Archive werden vor Extraktion geprüft
2. **Path-Traversal-Schutz** — `../` in tar-Entries wird abgelehnt
3. **Ed25519-Signatur** — optionale Manifest-Signatur
4. **Kein S3/MinIO** — reduziert Angriffsvektor Object-Storage-Misconfiguration

### Token-Sicherheit

- Node-Token bei Registrierung generiert (256-bit random)
- Token in `config.yaml` mit `0600` Permissions
- Registrierungs-Token im Panel: TTL (Standard 1h), einmalig verwendbar
- Token-Rotation über Panel-UI möglich

### Firewall

nftables/iptables Allocations:

- Nur explizit konfigurierte Ports geöffnet
- Regeln mit Kommentar (`gp-server-{id}`) für Audit
- Automatische Bereinigung bei Server-Löschung

## Image Server Sicherheit

### SFTP (empfohlen)

- `internal-sftp` Chroot — kein Shell-Zugang
- SSH Key-Auth only (`PasswordAuthentication no`)
- Separater Systembenutzer ohne sudo
- Chroot auf `/srv/gamepanel-images`

### FTPS/FTP (Fallback)

- Nur im internen Netz
- TLS erzwungen (FTPS)
- Passive Ports eingeschränkt
- Separate Credentials pro Node (empfohlen)

### Kein Object Storage

MinIO/S3 wird bewusst **nicht** verwendet:

- Keine Bucket-Policy-Fehlkonfiguration
- Keine öffentlich zugänglichen S3-Endpoints
- Einfacheres Audit (Dateisystem + SSH-Logs)

## Datenschutz & Backups

- Backups lokal auf Nodes (`/srv/gamepanel/backups/`)
- Panel speichert nur Metadaten (Pfad, Größe, Timestamp)
- Keine Spieler-IPs dauerhaft geloggt (konfigurierbar)
- DSGVO: Server-Löschung entfernt Panel-Daten; Node-Daten manuell oder via Agent-Job

## Empfohlene Production-Checkliste

- [ ] TLS mit gültigem Zertifikat (Let's Encrypt)
- [ ] `APP_DEBUG=false`
- [ ] Starke DB/Redis-Passwörter
- [ ] Admin-Passwort > 16 Zeichen
- [ ] PostgreSQL/Redis nicht exposed
- [ ] Image Server nur intern erreichbar
- [ ] SSH Key-Auth für Image Server
- [ ] Node-Token rotiert nach Setup
- [ ] Firewall auf allen Hosts aktiv
- [ ] Automatische OS-Updates (unattended-upgrades)
- [ ] Log-Rotation konfiguriert
- [ ] Backup-Strategie dokumentiert

## Incident Response

Bei kompromittiertem Node:

1. Node im Panel deaktivieren
2. Token rotieren
3. Agent stoppen: `systemctl stop gamepanel-agent`
4. Forensik: `/var/log/gamepanel/`, `journalctl`
5. Node neu aufsetzen, Agent neu registrieren

Bei kompromittiertem Panel:

1. Panel offline nehmen
2. DB-Passwörter rotieren
3. Alle Node-Tokens invalidieren
4. Container neu deployen mit frischen Secrets
5. Audit-Log prüfen

## Weiterführend

- [architecture.md](architecture.md) — Netzwerkmodell
- [node-agent.md](node-agent.md) — Agent Hardening
- [image-server.md](image-server.md) — SFTP Setup
