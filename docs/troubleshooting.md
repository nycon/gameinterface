# Troubleshooting

Häufige Probleme und Lösungen für GamePanel — Panel, Nodes, Image Server und Agent.

## Diagnose-Tools

```bash
# Panel Stack
make doctor
docker compose ps
docker compose logs --tail=100

# Installer/Node/Image Server
sudo ./installer/doctor.sh

# Node Agent
sudo gamepanel-agent doctor
sudo gamepanel-agent status
journalctl -u gamepanel-agent -n 100
```

---

## Panel / Docker Compose

### Container starten nicht

**Symptom:** `docker compose up` schlägt fehl, Services `Restarting`.

**Prüfen:**

```bash
docker compose logs backend
docker compose logs postgres
```

**Häufige Ursachen:**

| Ursache | Lösung |
|---------|--------|
| `POSTGRES_PASSWORD` fehlt | In `.env` setzen |
| Port 80/443 belegt | `HTTP_PORT=8080` in `.env` |
| APP_KEY fehlt | `docker compose run --rm backend php artisan key:generate` |
| Volume-Permissions | `docker compose down -v` und neu starten (Dev only!) |

### 502 Bad Gateway (Nginx)

**Symptom:** Browser zeigt 502, Nginx-Logs: `connection refused`.

**Checks:**
```bash
docker compose ps
docker compose logs proxy backend frontend --tail=50
```

Backend braucht ~30–60s zum Starten — Nginx `depends_on` wartet nicht auf Health.
**Lösung:**

```bash
docker compose ps                    # backend/frontend running?
docker compose logs backend        # PHP-Fehler?
docker compose restart backend frontend
```

Backend braucht ~30s zum Starten — Caddy `depends_on` wartet nicht auf Health.

### Migrationen schlagen fehl

```bash
docker compose exec backend php artisan migrate:status
docker compose exec postgres psql -U gamepanel -c "\l"
```

DB-Credentials in `.env` mit `POSTGRES_*` abgleichen.

### Queue-Jobs hängen

**Symptom:** Server bleibt auf „installing“, Jobs werden nicht verarbeitet.

```bash
docker compose ps worker           # Worker running?
docker compose logs worker
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" ping
docker compose exec backend php artisan queue:failed
docker compose exec backend php artisan queue:retry all
```

Worker neu starten:

```bash
docker compose restart worker
```

### Reverb/WebSocket verbindet nicht

1. Profil aktiv? `docker compose --profile reverb ps`
2. `.env`: `REVERB_APP_KEY`, `VITE_REVERB_*` gesetzt?
3. Frontend mit korrekten Build-Args gebaut?
4. Caddy routet `/app/*` → reverb:8080?

---

## Node Agent

### Agent startet nicht

```bash
systemctl status gamepanel-agent
journalctl -u gamepanel-agent -n 50
/opt/gamepanel/agent/gamepanel-agent doctor
```

| Fehler | Lösung |
|--------|--------|
| `config.yaml not found` | `cp config.example.yaml /opt/gamepanel/agent/config.yaml` |
| `permission denied` | Binary chmod 755, Config chmod 600 |
| `panel.url unreachable` | DNS, Firewall ausgehend, TLS-Zertifikat |

### Registrierung schlägt fehl

**Symptom:** `register --token` → 401 oder 404.

- Token abgelaufen? Im Panel neuen Token generieren (TTL 1h)
- Panel-URL korrekt? `https://` nicht vergessen
- Node bereits registriert? Token in `config.yaml` prüfen

### Kein Heartbeat im Panel

```bash
gamepanel-agent status
curl -H "Authorization: Bearer $TOKEN" https://panel.example.com/api/nodes/$ID/heartbeat
```

- Ausgehende HTTPS-Verbindung vom Node zum Panel?
- Node im Panel deaktiviert?
- Token nach Rotation aktualisiert?

### Jobs werden nicht ausgeführt

```bash
gamepanel-agent status    # job_poll aktiv?
journalctl -u gamepanel-agent -f
```

Panel-Seite:

```bash
docker compose exec backend php artisan queue:failed
```

Häufig: Image-Download schlägt fehl → siehe Image Server unten.

### Server startet nicht (systemd)

```bash
systemctl status gamepanel-server-42
journalctl -u gamepanel-server-42 -n 50
gamepanel-agent logs 42 -n 100
```

| Fehler | Lösung |
|--------|--------|
| `status=203/EXEC` | Executable-Pfad im Manifest prüfen |
| `status=127` | Abhängigkeit fehlt (lib32, java) |
| Port belegt | Anderen Prozess auf Port killen |
| Permission denied | `chown -R gp-s42:gp-s42 /srv/gamepanel/servers/42` |

---

## Image Server

### SFTP Verbindung schlägt fehl

```bash
sftp -i /opt/gamepanel/agent/keys/image-server gamepanel-images@10.0.0.10
```

| Fehler | Lösung |
|--------|--------|
| `Permission denied (publickey)` | Authorized Keys prüfen |
| `Connection refused` | sshd running? Firewall? |
| `No such file` | Chroot-Pfad, `remote_base` in Agent-Config |

Authorized Keys:

```bash
cat /srv/gamepanel-images/.ssh/authorized_keys
# Muss Key des Agents enthalten
```

Chroot-Hinweis: `/srv/gamepanel-images` muss `root:root` mit `755` sein.

### SHA256 Mismatch

**Symptom:** Agent bricht Download ab.

```bash
# Auf Image Server
sha256sum /srv/gamepanel-images/games/cs2/versions/1.0.0/cs2-1.0.0.tar.zst
cat /srv/gamepanel-images/games/cs2/versions/1.0.0/cs2-1.0.0.sha256
```

Bei Mismatch: Image neu bauen und publizieren.

### Image nicht gefunden

Remote-Pfad muss sein:

```
/images/games/{slug}/versions/{version}/{slug}-{version}.tar.zst
```

Relativ zum SFTP-Chroot. `index.json` prüfen.

---

## Image Builder

### SteamCMD Fehler

```bash
steamcmd +quit    # Test ob SteamCMD funktioniert
```

- Genug Speicherplatz? (`df -h`)
- Steam-Server erreichbar? (Firewall ausgehend 443)
- App ID korrekt?

### Build schlägt fehl

```bash
gamepanel-image build cs2 --version dev 2>&1 | tee build.log
```

Template-Pfad prüfen: `GAMEPANEL_TEMPLATES_DIR=../templates/games`

---

## Netzwerk & Firewall

### Spieler können nicht connecten

```bash
# Auf Node: Port offen?
ss -ulnp | grep 27015
nft list table gamepanel

# Von außen testen
nc -u panel-ip 27015
```

Agent-Firewall:

```bash
gamepanel-agent doctor    # firewall backend ok?
```

Cloud-Provider: Security Groups / Floating IPs prüfen — Game-Ports müssen UDP/TCP erlaubt sein.

### Panel nicht von außen erreichbar

```bash
ufw status
curl -I https://panel.example.com
dig panel.example.com
```

DNS, TLS (Let's Encrypt), Port 443.

---

## Performance

### Node überlastet

```bash
gamepanel-agent status
htop
systemctl status gamepanel.slice
```

- Zu viele Server auf einem Node? Auslastung im Panel prüfen
- `gamepanel.slice` MemoryMax setzen
- Server auf anderen Node migrieren

### Langsame Image-Downloads

- Image Server und Node im selben Rechenzentrum?
- SFTP statt FTP nutzen
- Agent Image-Cache: `/srv/gamepanel/images/cache/`

---

## Logs — Übersicht

| Komponente | Log-Pfad |
|------------|----------|
| Panel Backend | `docker compose logs backend` |
| Worker | `docker compose logs worker` |
| Nginx | `docker compose logs proxy` |
| Node Agent | `/var/log/gamepanel/agent.log`, `journalctl -u gamepanel-agent` |
| Game Server | `journalctl -u gamepanel-server-{id}` |
| Installer | `/var/log/gamepanel-installer.log` |
| Image Server | `/var/log/gamepanel/image-server.log` |

---

## Notfall-Wiederherstellung

### Panel komplett neu

1. `.env` Backup wiederherstellen
2. PostgreSQL Volume Backup einspielen
3. `docker compose up -d`
4. `php artisan migrate --force`

### Node komplett neu

1. Agent installieren
2. Im Panel: Token rotieren oder neu registrieren
3. Server-Daten unter `/srv/gamepanel/servers/` bleiben erhalten
4. Agent erkennt laufende Units wieder nach Heartbeat

### Alle Node-Tokens invalidieren

Panel Admin → Nodes → Token rotieren für jeden Node  
Auf Nodes: `gamepanel-agent register --token <new-token>`

---

## Support

Bei anhaltenden Problemen:

1. `make doctor` und `gamepanel-agent doctor` Output sammeln
2. Relevante Logs (letzte 100 Zeilen)
3. Issue auf GitHub mit Systeminfo (OS, Versionen, Schritte zur Reproduktion)

## Weiterführend

- [installation.md](installation.md)
- [node-agent.md](node-agent.md)
- [image-server.md](image-server.md)
