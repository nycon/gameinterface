# 3-VM Deployment — Zero-Touch (ohne manuelle .env)

Alles läuft über `./install.sh` mit Flags. Keine handgeschriebenen `.env`-Dateien nötig — Secrets, Domain/IP, SSL, Admin, Join-Tokens und Keys werden vom Installer erzeugt.

## Übersicht

| VM | Rolle | Befehl |
|----|--------|--------|
| VM2 | Image-Server | `--role image-server` |
| VM1 | Panel | `--role panel` |
| VM3 | Game-Node | `--role node` (+ SteamCMD, lib32, Java, MariaDB) |

**Reihenfolge:** Image-Server → Panel → Node

Voraussetzungen: Debian 12 / Ubuntu 24.04, Root, Repo auf jeder VM (git clone oder rsync).

---

## 1) Image-Server (VM2)

```bash
cd /opt/gamepanel-src   # oder wohin das Repo lag
sudo ./install.sh --role image-server --non-interactive
```

Erzeugt u. a.:
- SFTP-User + Chroot `/srv/gamepanel-images`
- Key `/etc/gamepanel/keys/node-access`
- Join-Datei `/etc/gamepanel/image-server-join.env`

---

## 2) Panel (VM1)

```bash
sudo ./install.sh --role panel --non-interactive \
  --domain panel.example.com \
  --ssl-mode letsencrypt \
  --admin-email admin@example.com \
  --admin-password 'StrongPass!2026' \
  --image-server-host 10.0.0.11
```

Ohne Domain (nur IP / Self-Signed):

```bash
sudo ./install.sh --role panel --non-interactive \
  --domain 10.0.0.10 \
  --ssl-mode selfsigned \
  --admin-email admin@example.com \
  --admin-password 'StrongPass!2026' \
  --image-server-host 10.0.0.11
```

Installer erledigt: Docker, `.env`/Secrets, SSL, Compose-Up, Migrationen, Seed, Admin, **Setup-Token**, Join-Datei `/etc/gamepanel/node-join.env`.

---

## 3) Game-Node (VM3)

Vom Panel die Join-Datei kopieren (oder Token aus Panel-Ausgabe nehmen):

```bash
scp root@10.0.0.10:/etc/gamepanel/node-join.env /tmp/node-join.env

sudo ./install.sh --role node --non-interactive \
  --join-file /tmp/node-join.env \
  --image-server-host 10.0.0.11 \
  --pull-image-key root@10.0.0.11:/etc/gamepanel/keys/node-access \
  --tls-insecure
```

(`--tls-insecure` nur bei `selfsigned` SSL)

**Node-Installer installiert automatisch:**
- i386 / **lib32** (Steam)
- **SteamCMD** unter `/opt/gamepanel/steamcmd`
- **Java 21** (+ 17 Fallback) für Minecraft
- **MariaDB** lokal (Kunden-DBs, User `gamepanel-agent@localhost`)
- OpenSSH-Client, nftables, Agent, systemd-Unit
- SFTP-Key vom Image-Server (via `--pull-image-key`)
- Panel-Registrierung mit Setup-Token

---

## Live-Check

```bash
# Panel
curl -k https://10.0.0.10/api/health

# Node
systemctl status gamepanel-agent
java -version
/opt/gamepanel/steamcmd/steamcmd.sh +quit
mysql -u gamepanel-agent -p"$(grep MYSQL_PASSWORD /etc/gamepanel/node.env | cut -d= -f2-)" -e 'SELECT 1'
```

Im UI: Node **online** → Server anlegen → Job `install` → Start.

---

## Firewall

| Von | Nach | Port |
|-----|------|------|
| Internet | VM1 | 80/443 |
| VM3 | VM1 | 443 |
| VM3 | VM2 | 22 |
| Spieler | VM3 | Game-Ports |

SSH zum Image-Server: Key-basiert, möglichst nur Node-IPs.

---

## Hilfe

```bash
./install.sh --help
sudo ./install.sh --doctor
```
