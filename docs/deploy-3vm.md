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
  --ssl-mode selfsigned \
  --admin-email admin@example.com \
  --admin-password 'StrongPass!2026'
```

Panel öffnen → einloggen.

---

## 2) Image-Server im Panel anlegen (dann auf VM2)

1. Admin → **Image Server** → **Image Server hinzufügen**
2. Nur einen **Namen** eingeben → Erstellen
3. Den angezeigten Befehl kopieren und **auf VM2 als root** ausführen, z.B.:

```bash
curl -fsSL https://panel.example.com/install/image-server/gpd_….sh | sudo bash
```

Der Installer setzt SFTP auf und meldet den Private Key automatisch ans Panel. Kein `scp`.

---

## 3) Node im Panel anlegen (dann auf VM3)

1. Admin → **Nodes** → **Node hinzufügen** (Name, Hostname, IP)
2. Den angezeigten Befehl **auf VM3 als root** ausführen:

```bash
curl -fsSL https://panel.example.com/install/node/gpd_….sh | sudo bash
```

Installiert automatisch: SteamCMD, lib32, Java, MariaDB, Agent — und claimt den Node am Panel (inkl. Image-Server-Credentials).

`--tls-insecure` ist im Auto-Script enthalten (Self-Signed). Bei gültigem Let’s-Encrypt kannst du lokal ohne Flag installieren:

```bash
sudo ./install.sh --role node --non-interactive \
  --panel-url https://panel.example.com \
  --deploy-token 'gpd_…'
```

---

## Live-Check

```bash
# Panel
curl -k https://PANEL/api/health

# Node
systemctl status gamepanel-agent
sudo ./install.sh --doctor
```

Im UI: Node **online** → Server anlegen → installieren → starten.

---

## Firewall

| Von | Nach | Port |
|-----|------|------|
| Internet | VM1 | 80/443 |
| VM3 | VM1 | 443 |
| VM3 | VM2 | 22 |
| Spieler | VM3 | Game-Ports |

---

## Token neu erzeugen

Im Panel bei Node bzw. Image-Server auf **Install-Befehl** / **Install** klicken — erzeugt einen neuen Deploy-Token.
