# GamePanel Image Builder

CLI-Tool zum Erstellen, Verifizieren und Veröffentlichen von Game-Server-Images für GamePanel.

## Installation

```bash
make build
# oder
make install
```

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| `build <template> --version X` | Image aus Template bauen |
| `update <template>` | SteamCMD-Update für Template ausführen |
| `publish <template> --version X` | Image auf den Image-Server hochladen |
| `verify <template> --version X` | Checksummen und Manifest prüfen |
| `list` | Verfügbare Templates auflisten |
| `prune --keep N` | Alte Versionen behalten, Rest löschen |

## Umgebungsvariablen

| Variable | Standard | Beschreibung |
|----------|----------|--------------|
| `GAMEPANEL_IMAGE_ROOT` | `/srv/gamepanel-images` | Ausgabeverzeichnis |
| `GAMEPANEL_TEMPLATES_DIR` | `../templates/games` | Pfad zu Game-Templates |
| `STEAMCMD_PATH` | `/usr/games/steamcmd` | SteamCMD-Binary |
| `FTP_HOST` | — | Image-Server FTP-Host |
| `FTP_USER` | — | FTP-Benutzer |
| `FTP_PASS` | — | FTP-Passwort |
| `SIGNING_KEY_PATH` | — | Optional: Ed25519-Privatkey für Manifest-Signatur |

## Output-Struktur

```
/srv/gamepanel-images/games/{slug}/versions/{version}/
  {slug}-{version}.tar.zst
  {slug}-{version}.manifest.json
  {slug}-{version}.lst
  {slug}-{version}.sha256
```

## Beispiel

```bash
gamepanel-image build cs2 --version 1.0.0
gamepanel-image verify cs2 --version 1.0.0
gamepanel-image publish cs2 --version 1.0.0
```
