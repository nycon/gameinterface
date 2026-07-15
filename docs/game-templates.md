# Game Templates

Game Templates sind YAML-Dateien unter `templates/games/`, die definieren, wie ein Spiel gebaut, installiert, gestartet und konfiguriert wird. Sie sind die zentrale Quelle für Image Builder, Panel-UI und Node Agent.

## Dateistruktur

```
templates/games/
├── minecraft.yaml
├── cs2.yaml
├── rust.yaml
├── valheim.yaml
└── ark.yaml
```

Jede Datei beschreibt ein Spiel vollständig. Das Panel lädt Templates zur Laufzeit für Variablen-Formulare und Validierung.

## Template-Schema

```yaml
name: "Anzeigename"
slug: "eindeutiger-slug"        # URL/API/Image-Pfad
type: "steam" | "custom"        # steam = SteamCMD, custom = eigenes Skript
steam_app_id: "730"             # nur bei type: steam

image:
  strategy: "steamcmd" | "script"
  archive_format: "tar.zst"
  image_server_path: "games/cs2"
  exclude_patterns:
    - "logs/**"
    - "crash-reports/**"

install:
  script: "scripts/modern/steamcmd-update.sh"
  env:
    STEAM_APP_ID: "730"
  requires:
    - steamcmd

update:
  script: "scripts/modern/steamcmd-update.sh"
  env:
    STEAM_APP_ID: "730"

runtime:
  executable: "./game/bin/linuxsteamrt64/cs2"
  work_dir: "/server"
  args:
    - "-dedicated"
    - "+map"
    - "de_dust2"
  env:
    SteamAppId: "730"

ports:
  - name: "game"
    protocol: "udp"
    default: 27015
    required: true
    description: "Spiel-Port"

variables:
  - name: "Map"
    env: "START_MAP"
    default: "de_dust2"
    description: "Startkarte"
    rules: "string|max:64"
  - name: "Tickrate"
    env: "TICKRATE"
    default: "128"
    rules: "integer|min:64|max:128"
```

## Felder im Detail

### Metadaten

| Feld | Pflicht | Beschreibung |
|------|---------|-------------|
| `name` | ja | Anzeigename in der UI |
| `slug` | ja | Eindeutiger Identifier (lowercase, a-z0-9-) |
| `type` | ja | `steam` oder `custom` |
| `steam_app_id` | bei steam | Steam App ID |

### `image`

Steuert Image Builder:

| Feld | Beschreibung |
|------|-------------|
| `strategy` | `steamcmd` — SteamCMD-Download; `script` — Custom-Skript |
| `archive_format` | Immer `tar.zst` |
| `image_server_path` | Relativer Pfad auf Image Server |
| `exclude_patterns` | Glob-Patterns, die nicht ins Archiv kommen |

### `install` / `update`

| Feld | Beschreibung |
|------|-------------|
| `script` | Pfad relativ zum Repo-Root |
| `env` | Umgebungsvariablen für das Skript |
| `requires` | Abhängigkeiten: `steamcmd`, `java17`, `wine` |

### `runtime`

Wird vom Agent in systemd Unit und Startskript übernommen:

| Feld | Beschreibung |
|------|-------------|
| `executable` | Startbefehl (relativ zu `work_dir`) |
| `work_dir` | Arbeitsverzeichnis im Server-Container |
| `args` | Kommandozeilenargumente (Platzhalter erlaubt) |
| `env` | Default-Umgebungsvariablen |

### Platzhalter in `args`

| Platzhalter | Ersetzt durch |
|-------------|---------------|
| `{{MEMORY_MIN}}` | Variable des Servers |
| `{{MEMORY_MAX}}` | Variable des Servers |
| `{{SERVER_ID}}` | Numerische Server-ID |
| `{{PORT_game}}` | Allokierter Port „game“ |

### `ports`

```yaml
ports:
  - name: "game"
    protocol: "tcp" | "udp" | "both"
    default: 25565
    required: true
    description: "Haupt-Spielport"
  - name: "query"
    protocol: "udp"
    default: 25565
    required: false
```

Der Agent öffnet `required: true` Ports automatisch in der Firewall.

### `variables`

Definiert konfigurierbare Server-Optionen in der Panel-UI:

```yaml
variables:
  - name: "Max Players"
    env: "MAX_PLAYERS"           # wird als Env-Var gesetzt
    default: "20"
    description: "Maximale Spieleranzahl"
    rules: "integer|min:1|max:100"
    hidden: false                # in UI ausblenden
    readonly: false              # nicht änderbar nach Installation
```

**Validation Rules** (Laravel-Validator-Syntax):

- `string`, `integer`, `boolean`
- `min:N`, `max:N`
- `in:val1,val2`
- Kombinierbar mit `|`

## Beispiele

### Minecraft (Custom/Java)

```yaml
name: "Minecraft Java Edition"
slug: "minecraft"
type: "custom"
steam_app_id: ""

image:
  strategy: "script"
  archive_format: "tar.zst"
  image_server_path: "games/minecraft"
  exclude_patterns:
    - "world/**"
    - "logs/**"

install:
  script: "scripts/modern/minecraft-update.sh"
  env:
    MINECRAFT_VERSION: "latest"
  requires:
    - java17

runtime:
  executable: "java"
  work_dir: "/server"
  args:
    - "-Xms{{MEMORY_MIN}}"
    - "-Xmx{{MEMORY_MAX}}"
    - "-jar"
    - "server.jar"
    - "nogui"
  env:
    EULA: "TRUE"

ports:
  - name: "game"
    protocol: "tcp"
    default: 25565
    required: true

variables:
  - name: "Memory Max"
    env: "MEMORY_MAX"
    default: "2048M"
    rules: "string"
```

### CS2 (Steam)

```yaml
name: "Counter-Strike 2"
slug: "cs2"
type: "steam"
steam_app_id: "730"

image:
  strategy: "steamcmd"
  archive_format: "tar.zst"
  image_server_path: "games/cs2"

install:
  script: "scripts/modern/steamcmd-update.sh"
  env:
    STEAM_APP_ID: "730"
  requires:
    - steamcmd

runtime:
  executable: "./game/bin/linuxsteamrt64/cs2"
  work_dir: "/server"
  args:
    - "-dedicated"
    - "+map"
    - "{{START_MAP}}"

ports:
  - name: "game"
    protocol: "udp"
    default: 27015
    required: true
```

## Neues Spiel hinzufügen

1. **Template erstellen:** `templates/games/meinspiel.yaml`
2. **Install-Skript:** `scripts/modern/meinspiel-install.sh` (falls nötig)
3. **Image bauen:** `gamepanel-image build meinspiel --version 1.0.0`
4. **Verifizieren:** `gamepanel-image verify meinspiel --version 1.0.0`
5. **Publizieren:** `gamepanel-image publish meinspiel --version 1.0.0`
6. **Panel:** Template wird automatisch erkannt (Cache leeren: `php artisan cache:clear`)

## Install-Skripte

Skripte unter `scripts/modern/` erhalten standardisierte Umgebungsvariablen:

| Variable | Beschreibung |
|----------|-------------|
| `GP_SERVER_DIR` | Zielverzeichnis |
| `GP_TEMPLATE_SLUG` | Spiel-Slug |
| `GP_VERSION` | Image-Version |
| `STEAMCMD` | Pfad zu SteamCMD |

Konventionen:

- `set -euo pipefail` am Anfang
- Exit 0 bei Erfolg, Exit 1+ bei Fehler
- Logs nach stdout (werden vom Image Builder erfasst)

## Legacy-Skripte

`scripts/legacy/` enthält migrierte Skripte aus älteren Systemen. Neue Entwicklung nur in `scripts/modern/`.

## Best Practices

- **Exclude-Patterns** für persistente Daten (`world/**`, `saves/**`)
- **Sinnvolle Defaults** für alle Variablen
- **Validation Rules** für numerische/boolean Werte
- **Beschreibungen** auf Deutsch für Endbenutzer
- **Steam App IDs** verifizieren auf [SteamDB](https://steamdb.info/)
- Images testen mit `gamepanel-agent test-image-download` vor Publish

## Weiterführend

- [image-system.md](image-system.md) — Archivformat
- [image-server.md](image-server.md) — Publizierung
- [development.md](development.md) — Lokale Template-Entwicklung
