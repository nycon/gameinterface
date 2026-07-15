# Image Server

Der Image Server ist ein dedizierter Linux-Host, der Game-Server-Images per **SFTP** (bevorzugt), **FTPS** oder **FTP** bereitstellt. GamePanel verwendet bewusst **kein MinIO, S3 oder Object Storage** — ein einfacher Dateiserver mit SSH genügt und entspricht der etablierten Praxis bei Teklab- und Easy-WI-ähnlichen Systemen.

## Aufgaben

- Zentraler Speicher für `.tar.zst`-Game-Images
- Bereitstellung von Manifesten (`.yaml`), Dateilisten (`.lst`) und Checksummen (`.sha256`)
- Authentifizierung via SSH-Key (SFTP) oder FTP-Credentials
- Optional: zentraler `index.json` für verfügbare Images

## Verzeichnisstruktur

```
/srv/gamepanel-images/
├── index.json                          # Katalog aller verfügbaren Images
└── games/
    └── {slug}/                         # z.B. cs2, minecraft, rust
        └── versions/
            └── {version}/              # z.B. 1.0.0, 2024.03.15
                ├── {slug}-{version}.tar.zst
                ├── {slug}-{version}.manifest.yaml
                ├── {slug}-{version}.lst
                └── {slug}-{version}.sha256
```

Beispiel:

```
/srv/gamepanel-images/games/cs2/versions/1.0.0/
  cs2-1.0.0.tar.zst
  cs2-1.0.0.manifest.yaml
  cs2-1.0.0.lst
  cs2-1.0.0.sha256
```

## Installation

### Automatisch (Installer)

```bash
sudo ./installer/install.sh --role image-server --config installer/installer.env
```

Relevante `installer.env`-Variablen:

```env
IMAGE_SERVER_ROOT=/srv/gamepanel-images
IMAGE_SERVER_USER=gamepanel-images
IMAGE_SERVER_GROUP=gamepanel-images
IMAGE_SERVER_HOST=10.0.0.10
IMAGE_SERVER_FTP_BACKEND=sftp
IMAGE_SERVER_ENABLE_FTPS=no
IMAGE_SERVER_AUTHORIZED_KEY_DATA="ssh-ed25519 AAAA... gamepanel"
```

### Manuell

#### 1. Benutzer und Verzeichnisse

```bash
useradd --system --home-dir /srv/gamepanel-images --shell /usr/sbin/nologin gamepanel-images
mkdir -p /srv/gamepanel-images/games
chown -R gamepanel-images:gamepanel-images /srv/gamepanel-images
chmod 755 /srv/gamepanel-images
```

#### 2. SFTP (OpenSSH internal-sftp)

In `/etc/ssh/sshd_config.d/gamepanel-images.conf`:

```
Match User gamepanel-images
    ChrootDirectory /srv/gamepanel-images
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PasswordAuthentication no
```

SSH-Key autorisieren:

```bash
mkdir -p /srv/gamepanel-images/.ssh
echo "ssh-ed25519 AAAA... gamepanel-agent" >> /srv/gamepanel-images/.ssh/authorized_keys
chown -R gamepanel-images:gamepanel-images /srv/gamepanel-images/.ssh
chmod 700 /srv/gamepanel-images/.ssh
chmod 600 /srv/gamepanel-images/.ssh/authorized_keys
systemctl reload sshd
```

**Hinweis:** Das Chroot-Verzeichnis muss root-owned sein (`chown root:root /srv/gamepanel-images`), Unterverzeichnisse dem Benutzer gehören. Der Installer setzt dies korrekt.

#### 3. Optional: FTPS (vsftpd)

Nur aktivieren wenn SFTP nicht möglich ist:

```env
IMAGE_SERVER_ENABLE_FTPS=yes
```

Der Installer konfiguriert vsftpd mit TLS, chrooted Home und passive Ports. FTPS ist weniger sicher als SFTP — SFTP bleibt Standard.

#### 4. index.json

Der Installer erzeugt `index.json` automatisch. Manuell aktualisieren:

```bash
# Nach dem Hochladen neuer Images
sudo /opt/gamepanel/scripts/refresh-image-index.sh
# oder über image-builder:
gamepanel-image list --remote
```

Beispiel `index.json`:

```json
{
  "generated_at": "2026-07-15T08:00:00Z",
  "games": {
    "cs2": {
      "versions": ["1.0.0", "1.0.1"],
      "latest": "1.0.1"
    },
    "minecraft": {
      "versions": ["2026.07.01"],
      "latest": "2026.07.01"
    }
  }
}
```

## Panel-Konfiguration

In Panel `.env`:

```env
GAMEPANEL_IMAGE_SERVER_HOST=10.0.0.10
GAMEPANEL_IMAGE_SERVER_PORT=22
GAMEPANEL_IMAGE_SERVER_PROTOCOL=sftp
GAMEPANEL_IMAGE_SERVER_USER=gamepanel-images
GAMEPANEL_IMAGE_SERVER_REMOTE_BASE=/images
```

Der Pfad `/images` ist relativ zum SFTP-Chroot (`/srv/gamepanel-images` → `/images/games/...`).

## Agent-Konfiguration

In `/opt/gamepanel/agent/config.yaml`:

```yaml
sftp:
  enabled: true
  host: "10.0.0.10"
  port: 22
  username: "gamepanel-images"
  private_key_path: "/opt/gamepanel/agent/keys/image-server"
  remote_base: "/images"

ftp:
  enabled: false
  # Fallback wenn SFTP nicht verfügbar
```

## Images publizieren

Mit dem Image Builder:

```bash
gamepanel-image build cs2 --version 1.0.1
gamepanel-image verify cs2 --version 1.0.1
gamepanel-image publish cs2 --version 1.0.1
```

Umgebungsvariablen für Publish:

```env
FTP_HOST=10.0.0.10
FTP_USER=gamepanel-images
FTP_PASS=          # leer bei Key-Auth
SIGNING_KEY_PATH=/etc/gamepanel/image-signing.key
```

Alternativ manuell per `scp`/`rsync`:

```bash
rsync -avz /srv/gamepanel-images-build/ gamepanel-images@10.0.0.10:/srv/gamepanel-images/games/
```

## Firewall

```bash
# SFTP
ufw allow from 10.0.0.0/24 to any port 22 proto tcp

# FTPS (falls aktiv)
ufw allow from 10.0.0.0/24 to any port 990 proto tcp
ufw allow from 10.0.0.0/24 to any port 40000:40100 proto tcp  # passive
```

Image Server muss **nicht** öffentlich im Internet erreichbar sein — nur Panel/Nodes im internen Netz.

## Monitoring & Wartung

- Speicherplatz: `df -h /srv/gamepanel-images`
- Alte Versionen bereinigen: `gamepanel-image prune --keep 3`
- Logs: `/var/log/gamepanel/image-server.log`
- Integrität: regelmäßig `gamepanel-image verify` für alle aktiven Versionen

## Sicherheit

- SSH-Key-Auth only (kein Passwort-Login)
- Chrooted SFTP — kein Shell-Zugang
- Separater Systembenutzer ohne sudo
- Netzwerk-Isolation (internes VLAN)
- Optional: Ed25519-Signatur auf Manifesten (Agent prüft Signatur)

Siehe [security.md](security.md).

## Weiterführend

- [image-system.md](image-system.md) — Archivformat und Manifeste
- [game-templates.md](game-templates.md) — Templates für neue Spiele
