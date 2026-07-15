# Installer

Panel-first Deployment (Pterodactyl-Stil): Image-Server und Node werden im Admin angelegt; der angezeigte `curl | bash`-Befehl verbindet die VM ohne Datei-Kopieren.

## Empfohlener Ablauf

1. `sudo ./install.sh --role panel --non-interactive --domain …`
2. Panel → Image-Server anlegen → Befehl auf Image-VM
3. Panel → Node anlegen → Befehl auf Node-VM

Details: [deploy-3vm.md](deploy-3vm.md)

## Flags

```bash
sudo ./install.sh --help
```

Wichtig:

| Flag | Zweck |
|------|--------|
| `--deploy-token` | Einmal-Token aus dem Panel (`gpd_…`) |
| `--panel-url` | Panel-Basis-URL |
| `--tls-insecure` | Self-Signed Zertifikate akzeptieren |

## Rollen kurz

- **panel** — Docker, SSL, Admin
- **image-server** — SFTP + Complete an Panel (mit Deploy-Token)
- **node** — SteamCMD, lib32, Java, MariaDB, Agent + Claim

## Doctor

```bash
sudo ./install.sh --doctor
```
