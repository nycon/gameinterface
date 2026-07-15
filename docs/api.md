# API

GamePanel stellt eine **REST-API** auf Basis von Laravel 12 bereit. Authentifizierung erfolgt über **Laravel Sanctum** (Session für SPA, Bearer Token für externe Clients). Die OpenAPI-Dokumentation ist unter `/docs` erreichbar (l5-swagger).

## Base URL

```
https://panel.example.com/api
```

Lokale Entwicklung:

```
http://localhost/api
```

## Authentifizierung

### SPA (Vue Frontend)

Cookie-basierte Session via Sanctum. CSRF-Token erforderlich:

```http
GET /sanctum/csrf-cookie
POST /api/login
Content-Type: application/json

{"email": "admin@example.com", "password": "secret"}
```

### API Token

```http
GET /api/servers
Authorization: Bearer {token}
Accept: application/json
```

Token erstellen (authentifiziert):

```http
POST /api/tokens
{"name": "monitoring", "abilities": ["servers:read"]}
```

## Antwortformat

Erfolg:

```json
{
  "data": { ... },
  "meta": { "page": 1, "total": 42 }
}
```

Fehler:

```json
{
  "message": "Validation failed.",
  "errors": {
    "name": ["The name field is required."]
  }
}
```

HTTP-Statuscodes: 200, 201, 204, 400, 401, 403, 404, 422, 429, 500.

## Endpunkte

### Auth

| Methode | Pfad | Beschreibung |
|---------|------|-------------|
| POST | `/login` | Anmelden |
| POST | `/logout` | Abmelden |
| GET | `/user` | Aktueller Benutzer |

### Nodes (Admin)

| Methode | Pfad | Beschreibung |
|---------|------|-------------|
| GET | `/nodes` | Alle Nodes auflisten |
| POST | `/nodes` | Node anlegen (liefert Registration Token) |
| GET | `/nodes/{id}` | Node-Details |
| PATCH | `/nodes/{id}` | Node bearbeiten |
| DELETE | `/nodes/{id}` | Node entfernen |
| POST | `/nodes/{id}/rotate-token` | Agent-Token rotieren |

### Node Agent (Agent-Auth via Node-Token)

| Methode | Pfad | Beschreibung |
|---------|------|-------------|
| POST | `/nodes/register` | Erstregistrierung mit Registration Token |
| POST | `/nodes/{id}/heartbeat` | Metriken senden |
| GET | `/nodes/{id}/jobs/poll` | Nächsten Job abholen |
| POST | `/nodes/{id}/jobs/{jobId}/complete` | Job erfolgreich |
| POST | `/nodes/{id}/jobs/{jobId}/fail` | Job fehlgeschlagen |

#### Heartbeat Request

```json
POST /api/nodes/{id}/heartbeat
Authorization: Bearer {node-token}

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

#### Job Poll Response

```json
GET /api/nodes/{id}/jobs/poll

{
  "data": {
    "id": "job-uuid",
    "type": "install",
    "server_id": 42,
    "payload": {
      "image_slug": "cs2",
      "image_version": "1.0.0",
      "variables": {
        "START_MAP": "de_dust2",
        "TICKRATE": "128"
      },
      "ports": {
        "game": 27015
      }
    }
  }
}
```

Leere Antwort (204) wenn kein Job pending.

#### Job Complete

```json
POST /api/nodes/{id}/jobs/{jobId}/complete

{
  "result": {
    "pid": 12345,
    "installed_version": "1.0.0"
  }
}
```

### Servers

| Methode | Pfad | Beschreibung |
|---------|------|-------------|
| GET | `/servers` | Eigene Server auflisten |
| POST | `/servers` | Server erstellen |
| GET | `/servers/{id}` | Server-Details |
| PATCH | `/servers/{id}` | Konfiguration ändern |
| DELETE | `/servers/{id}` | Server löschen |
| POST | `/servers/{id}/start` | Start-Job erstellen |
| POST | `/servers/{id}/stop` | Stop-Job erstellen |
| POST | `/servers/{id}/restart` | Restart-Job |
| POST | `/servers/{id}/kill` | Kill-Job |
| POST | `/servers/{id}/reinstall` | Reinstall-Job |
| GET | `/servers/{id}/logs` | Server-Logs (letzte N Zeilen) |

#### Server erstellen

```json
POST /api/servers

{
  "name": "Mein CS2 Server",
  "game": "cs2",
  "node_id": "node-uuid",
  "variables": {
    "START_MAP": "de_inferno",
    "TICKRATE": "128"
  },
  "memory": 4096
}
```

Antwort (201):

```json
{
  "data": {
    "id": 42,
    "name": "Mein CS2 Server",
    "status": "installing",
    "game": "cs2",
    "node_id": "node-uuid",
    "ports": { "game": 27015 }
  }
}
```

### Games / Templates

| Methode | Pfad | Beschreibung |
|---------|------|-------------|
| GET | `/games` | Verfügbare Spiele/Templates |
| GET | `/games/{slug}` | Template-Details inkl. Variablen |
| GET | `/games/{slug}/versions` | Verfügbare Image-Versionen |

### Backups

| Methode | Pfad | Beschreibung |
|---------|------|-------------|
| GET | `/servers/{id}/backups` | Backups auflisten |
| POST | `/servers/{id}/backups` | Backup-Job erstellen |
| POST | `/servers/{id}/backups/{backupId}/restore` | Restore-Job |
| DELETE | `/servers/{id}/backups/{backupId}` | Backup löschen |

### Users & Permissions (Admin)

| Methode | Pfad | Beschreibung |
|---------|------|-------------|
| GET | `/users` | Benutzer auflisten |
| POST | `/users` | Benutzer anlegen |
| PATCH | `/users/{id}` | Bearbeiten |
| DELETE | `/users/{id}` | Löschen |
| GET | `/roles` | Rollen auflisten |

## WebSocket (Reverb)

Optional für Live-Events (Server-Status, Logs, Job-Fortschritt):

```
wss://panel.example.com/app/{REVERB_APP_KEY}
```

Events (Laravel Broadcasting):

| Event | Kanal | Beschreibung |
|-------|-------|-------------|
| `ServerStatusChanged` | `server.{id}` | Status-Update |
| `ServerLogLine` | `server.{id}` | Neue Log-Zeile |
| `JobProgress` | `server.{id}` | Install/Update-Fortschritt |
| `NodeHeartbeat` | `admin.nodes` | Node-Metriken (Admin) |

Aktivierung: Reverb-Profil in Docker Compose, siehe [installation.md](installation.md).

## Rate Limiting

| Endpunkt | Limit |
|----------|-------|
| `/login` | 5/min pro IP |
| `/api/*` (auth) | 60/min pro User |
| `/nodes/register` | 3/h pro IP |
| Agent Heartbeat | 120/min pro Node |

Überschreitung: HTTP 429 mit `Retry-After` Header.

## OpenAPI / Swagger

Interaktive Dokumentation:

```
https://panel.example.com/docs
```

Spec generieren (Entwicklung):

```bash
docker compose exec backend php artisan l5-swagger:generate
```

Spec-Datei: `backend/storage/api-docs/api-docs.json`

## Fehlercodes (Agent-relevant)

| Code | Bedeutung |
|------|-----------|
| 401 | Token ungültig/abgelaufen |
| 403 | Node deaktiviert |
| 404 | Job/Server nicht gefunden |
| 409 | Job bereits abgeschlossen |
| 422 | Payload ungültig |

## Versionierung

Aktuell: keine URL-Versionierung (`/api/v1/` geplant).

Breaking Changes werden im Changelog dokumentiert.

## Weiterführend

- [node-agent.md](node-agent.md) — Agent-Integration
- [development.md](development.md) — API lokal testen
- [security.md](security.md) — Auth & Permissions
