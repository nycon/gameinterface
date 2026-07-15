# 3-VM Deployment — Panel-first (wie Pterodactyl)

Kein Kopieren von Join-Dateien oder SSH-Keys zwischen den VMs.  
Du installierst das Panel, legst Image-Server und Node in der UI an und führst den angezeigten Install-Befehl auf der jeweiligen VM aus.

## Reihenfolge

1. **VM1 — Panel**
2. **VM2 — Image-Server** (Befehl aus Panel)
3. **VM3 — Game-Node** (Befehl aus Panel)

Voraussetzungen: Debian 12 / Ubuntu 24.04, Root, Internet.

---

## 1) Panel (VM1)

```bash
sudo git clone https://github.com/nycon/gameinterface.git /opt/gamepanel-src
cd /opt/gamepanel-src

sudo ./install.sh --role panel --non-interactive \
  --domain panel.example.com \
  --ssl-mode letsencrypt \
  --admin-email admin@example.com \
  --admin-password 'StrongPass!2026'
```

Panel öffnen → einloggen.

**SSL kaputt (Self-Signed / HSTS-Fehler trotz letsencrypt):** Port 80 muss öffentlich erreichbar sein. Dann:

```bash
cd /opt/gamepanel-src && sudo git pull
sudo ./install.sh --role panel --fix-ssl --non-interactive \
  --domain panel.example.com \
  --ssl-mode letsencrypt \
  --admin-email admin@example.com
openssl x509 -in deploy/nginx/certs/fullchain.pem -noout -issuer
# erwartet: Let's Encrypt — nicht O = GamePanel
```

Firefox HSTS-Cache leeren: `about:networking#security` → Domain suchen → Delete (oder Website-Daten für die Domain löschen).

---

## 2) Image-Server im Panel anlegen (dann auf VM2)

1. Admin → **Image Server** → **Image Server hinzufügen**
2. Nur einen **Namen** eingeben → Erstellen
3. Den angezeigten Befehl kopieren und **auf VM2 als root** ausführen, z.B.:

```bash
curl -fsSL https://panel.example.com/install/image-server/gpd_….sh | sudo bash
```

Der Installer setzt SFTP auf und meldet den Private Key automatisch ans Panel. Kein `scp`.
Zusätzlich: **Go, SteamCMD und `gp-image`** (Image-Builder) werden mitinstalliert.

Falls der Image-Server schon läuft **ohne** Builder:

```bash
cd /opt/gamepanel-src
sudo git pull
sudo bash installer/install-image-builder.sh
gp-image list
gp-image build cs2 --version 1.0.0
```

---

## 3) Node im Panel anlegen (dann auf VM3)

1. Admin → **Nodes** → **Node hinzufügen** (Name, Hostname, IP)
2. Den angezeigten Befehl **auf VM3 als root** ausführen:

```bash
curl -fsSL https://panel.example.com/install/node/gpd_….sh | sudo bash
```

Installiert automatisch: SteamCMD, lib32, Java, MariaDB, **phpMyAdmin**, Agent — und claimt den Node am Panel (inkl. Image-Server-Credentials und MySQL-Admin-Zugang fürs Panel).

Beim Anlegen des Nodes wird **automatisch ein Port-Pool** (25565+) angelegt — kein manuelles Port-Setup nötig.

`--tls-insecure` ist im Auto-Script enthalten (Self-Signed). Bei gültigem Let’s-Encrypt kannst du lokal ohne Flag installieren:

```bash
sudo ./install.sh --role node --non-interactive \
  --panel-url https://panel.example.com \
  --deploy-token 'gpd_…'
```

---

## 4) Ersten Gameserver: Minecraft

1. Admin → **Server** → **Server erstellen**
2. Template ist standardmäßig **Minecraft Java Edition**
3. **Anlegen & installieren** — der Agent lädt automatisch `server.jar` (Mojang), schreibt EULA + `server.properties`, legt die systemd-Unit an und öffnet den Port

Kein manuelles Java-/JAR-Setup. Optional danach **Start**.

---

## Datenbanken / phpMyAdmin

- Pro Node: MariaDB nur auf `127.0.0.1`, phpMyAdmin auf **Port 8081**
- Client: Server → **Datenbanken** → Anlegen → **phpMyAdmin** (Login mit DB-User; sieht nur diese DB)
- Admin: **Datenbanken** → Node-Button für Full-Access (`gamepanel-agent`) oder Passwort+PMA pro DB

Firewall: Port **8081/tcp** zum Node freigeben (macht der Node-Installer lokal).

---

## Live-Check

```bash
# Panel
curl -k https://PANEL/api/health

# Node
systemctl status gamepanel-agent
curl -I http://NODE-IP:8081/
sudo ./install.sh --doctor
```

Im UI: Node **online** → Minecraft-Server anlegen → installieren → starten.

---

## Firewall

| Von | Nach | Port |
|-----|------|------|
| Internet | VM1 | 80/443 |
| VM3 | VM1 | 443 |
| VM3 | VM2 | 22 |
| Spieler | VM3 | Game-Ports (z.B. 25565) |
| Admin/Kunde | VM3 | 8081 (phpMyAdmin) |

---

## Token neu erzeugen

Im Panel bei Node bzw. Image-Server auf **Install-Befehl** / **Install** klicken — erzeugt einen neuen Deploy-Token.
