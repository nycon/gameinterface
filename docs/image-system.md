# Image-System

GamePanel verwendet ein **dateibasiertes Image-Format** inspiriert von Teklab: komprimierte Archive mit begleitenden Metadaten-Dateien. Images werden per SFTP/FTPS/FTP übertragen — **kein MinIO/S3**.

## Komponenten eines Image-Pakets

Jede Version eines Spiels besteht aus vier Dateien:

| Datei | Zweck |
|-------|-------|
| `{slug}-{version}.tar.zst` | Komprimiertes Server-Dateisystem (Zstandard) |
| `{slug}-{version}.manifest.yaml` | Metadaten: Startup, Umgebung, Checksumme |
| `{slug}-{version}.lst` | Vollständige Dateiliste mit Größen |
| `{slug}-{version}.sha256` | SHA256-Hash des Archives |

### Beispiel: CS2 Version 1.0.0

```
cs2-1.0.0.tar.zst          # ~25 GB
cs2-1.0.0.manifest.yaml    # ~2 KB
cs2-1.0.0.lst              # ~500 KB
cs2-1.0.0.sha256           # 64 Zeichen Hex
```

## Archivformat (.tar.zst)

- **tar** — POSIX-Archive, erhalten Symlinks und Berechtigungen
- **zstd** — schnelle Kompression (Level 3–6 empfohlen)
- **Kein Verschlüsselung** — Integrität via SHA256; Transport-Sicherheit via SFTP/TLS

Erstellung (Image Builder):

```bash
gamepanel-image build cs2 --version 1.0.0
```

Interner Ablauf:

1. SteamCMD oder Custom-Skript lädt Spieldateien
2. Exclude-Patterns aus Template anwenden (`logs/**`, `world/**`)
3. `tar --use-compress-program=zstd -cf cs2-1.0.0.tar.zst -C /build .
4. `.lst` generieren: `find . -type f -printf '%s %p\n'`
5. SHA256 berechnen: `sha256sum cs2-1.0.0.tar.zst`

## Manifest (.manifest.yaml)

Das Manifest beschreibt, wie der Agent das Image installiert und startet:

```yaml
id: cs2
name: "Counter-Strike 2"
version: "1.0.0"
archive: cs2-1.0.0.tar.zst
sha256: "a1b2c3d4e5f6..."
extract_to: /server

startup:
  executable: "./game/bin/linuxsteamrt64/cs2"
  args:
    - "-dedicated"
    - "+map"
    - "de_dust2"

environment:
  SteamAppId: "730"
  LD_LIBRARY_PATH: "/server/game/bin/linuxsteamrt64"

ports:
  - name: game
    protocol: udp
    default: 27015

signature: "ed25519:base64..."   # optional
```

### Pflichtfelder

| Feld | Beschreibung |
|------|-------------|
| `id` | Spiel-Slug (muss Template entsprechen) |
| `archive` | Dateiname des Archives |
| `sha256` | Prüfsumme des Archives |
| `startup.executable` | Relativer Pfad nach Extraktion |

### Optionale Felder

- `environment` — Default-Umgebungsvariablen
- `ports` — Standard-Ports für Firewall-Allocations
- `signature` — Ed25519-Signatur (Schutz vor manipulierten Manifesten)

## Dateiliste (.lst)

Teklab-kompatibles Format — eine Zeile pro Datei:

```
1048576 server/server.jar
4096 server/config/server.properties
2048 server/eula.txt
```

Verwendung:

- **Integritätsprüfung** nach Extraktion (Agent vergleicht Dateianzahl)
- **Diff bei Updates** — welche Dateien sich geändert haben
- **Support/Debug** — schneller Überblick über Image-Inhalt

## Checksumme (.sha256)

Eine Zeile, nur der Hex-Hash:

```
a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
```

Der Agent:

1. Lädt `.sha256` vom Image Server
2. Berechnet SHA256 des heruntergeladenen Archives
3. Bricht ab bei Mismatch (keine Extraktion)
4. Speichert validiertes Archive im lokalen Cache (`/srv/gamepanel/images/`)

## Download-Ablauf (Agent)

```
1. Panel sendet Job "install" mit image_slug + version
2. Agent ermittelt Remote-Pfad:
   /images/games/{slug}/versions/{version}/{slug}-{version}.tar.zst
3. SFTP-Download → /srv/gamepanel/images/cache/
4. SHA256 validieren
5. Manifest parsen und optional Signatur prüfen
6. Sichere Extraktion nach /srv/gamepanel/servers/{id}/
   - Path-Traversal-Schutz (kein ../)
   - Atomic rename nach Erfolg
7. systemd Unit aus Template + Manifest generieren
8. Server starten
```

## Image Builder CLI

```bash
# Verfügbare Templates
gamepanel-image list

# Image bauen
gamepanel-image build minecraft --version 2026.07.01

# Integrität prüfen
gamepanel-image verify cs2 --version 1.0.0

# Auf Image Server hochladen
gamepanel-image publish cs2 --version 1.0.0

# Alte Versionen aufräumen (lokal)
gamepanel-image prune --keep 5

# SteamCMD-Update ohne vollständigen Rebuild
gamepanel-image update cs2
```

Umgebungsvariablen:

| Variable | Standard | Beschreibung |
|----------|----------|-------------|
| `GAMEPANEL_IMAGE_ROOT` | `/srv/gamepanel-images` | Build-Ausgabe |
| `GAMEPANEL_TEMPLATES_DIR` | `templates/games` | Template-Pfad |
| `STEAMCMD_PATH` | `/usr/games/steamcmd` | SteamCMD |
| `SIGNING_KEY_PATH` | — | Ed25519 Private Key |

## Signierung (optional)

Ed25519-Signaturen auf Manifesten verhindern Supply-Chain-Angriffe:

```bash
# Key generieren (einmalig, sicher aufbewahren)
openssl genpkey -algorithm ED25519 -out /etc/gamepanel/image-signing.key

# Beim Build automatisch signieren wenn SIGNING_KEY_PATH gesetzt
gamepanel-image build cs2 --version 1.0.1
```

Agent-Konfiguration:

```yaml
images:
  verify_signature: true
  public_key_path: "/opt/gamepanel/agent/keys/image-signing.pub"
```

## Cache & Deduplizierung

Der Agent cached heruntergeladene Images:

```
/srv/gamepanel/images/
├── cache/
│   └── cs2-1.0.0.tar.zst
└── extracted/
    └── cs2-1.0.0/          # optional, für schnelle Neuinstallation
```

Mehrere Server mit gleichem Image teilen den Cache — nur die Server-spezifischen Daten (Welten, Configs) liegen unter `/srv/gamepanel/servers/{id}/`.

## Updates

**Minor Update** (SteamCMD):

```bash
gamepanel-image update cs2
gamepanel-image publish cs2 --version 1.0.2
```

Panel triggert Agent-Job `update` → neues Image laden → Server stoppen → extrahieren → Config migrieren → starten.

**Config-Erhaltung:** Exclude-Patterns im Template schützen persistente Pfade (`world/**`, `server.properties`).

## Fehlerbehandlung

| Fehler | Ursache | Lösung |
|--------|---------|--------|
| SHA256 mismatch | Korrupte Übertragung | Download wiederholen |
| Manifest invalid | Fehlende Pflichtfelder | Image neu bauen |
| Extract failed | Disk voll | Speicher freigeben |
| Signature invalid | Manipuliertes Manifest | Key/Quelle prüfen |

## Weiterführend

- [image-server.md](image-server.md) — Server-Setup
- [game-templates.md](game-templates.md) — Template-Definition
- [node-agent.md](node-agent.md) — Agent-Extraktion
