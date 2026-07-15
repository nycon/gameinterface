# Legacy Scripts – Kompatibilitätslayer

Dieses Verzeichnis ist für **abwärtskompatible Skripte** reserviert, die ältere GamePanel-Installationen und Pterodactyl-Egg-Workflows weiterhin unterstützen.

## Warum ein Legacy-Layer?

GamePanel führt schrittweise von monolithischen Egg-Startup-Skripten auf **modulare Templates** (`templates/games/`) und den **Image Builder** (`image-builder/`) um. Während der Übergangsphase können bestehende Server weiterhin Legacy-Skripte referenzieren.

## Unterschied zu `scripts/modern/`

| Aspekt | Legacy | Modern |
|--------|--------|--------|
| Aufruf | Direkt im Container-Start | Über Image Builder / Template |
| Konfiguration | Hardcodierte Umgebungsvariablen | YAML-Template mit `variables` |
| Updates | Manuell oder Cron im Container | `gamepanel-image update` |
| Images | Keine versionierten Archive | `tar.zst` + Manifest auf Image-Server |

## Migration

1. Template unter `templates/games/{slug}.yaml` anlegen oder vorhandenes nutzen
2. Image mit `gamepanel-image build {slug} --version X` erstellen
3. Legacy-Startup-Skript durch Template-`runtime`-Block ersetzen
4. Legacy-Skript hier ablegen (optional), bis alle Server migriert sind

Neue Spiele **sollten ausschließlich** Skripte aus `scripts/modern/` verwenden.
