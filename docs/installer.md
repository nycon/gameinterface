# Installer

GamePanel enthält einen **Easy-WI-inspirierten Bash-Installer** für unattended Deployments.
**Keine manuelle `.env`-Pflicht** — Flags + Auto-Secrets; Join-Dateien verbinden die VMs.

## Philosophie

- **Rollenbasiert** — Panel, Node, Image-Server oder Standalone
- **Zero-Touch** — `--non-interactive` + CLI-Flags; Secrets werden generiert
- **Idempotent wo möglich** — wiederholte Läufe überschreiben keine Secrets
- **Doctor-Modus** — Systemprüfung vor und nach Installation
- **Strukturierte Logs** — `/var/log/gamepanel-installer.log`

## Einstieg

```bash
sudo ./install.sh --help
```

### 3-VM Zero-Touch (Produktions)

```bash
# VM2
sudo ./install.sh --role image-server --non-interactive

# VM1
sudo ./install.sh --role panel --non-interactive \
  --domain panel.example.com --ssl-mode letsencrypt \
  --admin-email admin@example.com --admin-password 'StrongPass!2026' \
  --image-server-host 10.0.0.11

# VM3
scp root@PANEL:/etc/gamepanel/node-join.env /tmp/node-join.env
sudo ./install.sh --role node --non-interactive \
  --join-file /tmp/node-join.env \
  --pull-image-key root@10.0.0.11:/etc/gamepanel/keys/node-access
```

Details: [deploy-3vm.md](deploy-3vm.md)

### Doctor

```bash
sudo ./install.sh --doctor
```

## Rollen

### `panel`

1. Systembenutzer, Docker, Sync nach `/opt/gamepanel/`
2. `.env` mit generierten Secrets (kein Handedit nötig)
3. SSL (`selfsigned` | `letsencrypt`) → Nginx
4. Compose Up, Migrationen, Seed, Admin, Setup-Token
5. Optional Image-Server-Eintrag bei `--image-server-host`
6. Join-Datei `/etc/gamepanel/node-join.env`

### `image-server`

SFTP-Chroot, Keys unter `/etc/gamepanel/keys/`, Join-Datei `image-server-join.env`.

### `node`

**Produktions-Runtimes im Installer (kein Nachziehen):**

| Komponente | Zweck |
|------------|--------|
| i386 / lib32 | Steam-Games |
| SteamCMD | `/opt/gamepanel/steamcmd` |
| OpenJDK 21 (+17) | Minecraft |
| MariaDB | Kunden-DBs (`gamepanel-agent@localhost`) |
| Agent + systemd | Job-Ausführung, Heartbeat |
| SFTP-Key | via `--pull-image-key` vom Image-Server |

## Dateien

| Datei | Zweck |
|-------|--------|
| `installer/install.sh` | Haupteinstieg, Flags |
| `installer/install-panel.sh` | Panel |
| `installer/install-node.sh` | Game-Node |
| `installer/install-image-server.sh` | Image-Server |
| `installer/lib/config_collect.sh` | Defaults, Join-Dateien |
| `installer/doctor.sh` | Diagnose inkl. Node-Runtimes |
| `installer/examples/*.env.example` | Referenz (optional) |

Persistenz: `/etc/gamepanel/installer.env` (vom Installer geschrieben, nicht voraussetzen).
