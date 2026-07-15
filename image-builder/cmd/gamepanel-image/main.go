package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/gamepanel/image-builder/internal/build"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	templatesDir := envOr("GAMEPANEL_TEMPLATES_DIR", defaultTemplatesDir())
	projectRoot := envOr("GAMEPANEL_PROJECT_ROOT", defaultProjectRoot(templatesDir))

	builder, err := build.NewBuilder(templatesDir, projectRoot)
	if err != nil {
		fail(err)
	}

	ctx := context.Background()
	cmd := os.Args[1]

	switch cmd {
	case "build":
		slug, version := parseSlugVersion(os.Args[2:], true)
		m, err := builder.Build(ctx, slug, version)
		if err != nil {
			fail(err)
		}
		fmt.Printf("build erfolgreich: %s %s (%d dateien, sha256=%s)\n",
			m.Slug, m.Version, m.FileCount, m.SHA256)

	case "update":
		slug := requireArg(os.Args, 2, "template")
		if err := builder.Update(ctx, slug); err != nil {
			fail(err)
		}
		fmt.Printf("update erfolgreich: %s\n", slug)

	case "publish":
		slug, version := parseSlugVersion(os.Args[2:], true)
		if err := builder.Publish(slug, version); err != nil {
			fail(err)
		}
		fmt.Printf("publish erfolgreich: %s %s\n", slug, version)

	case "verify":
		slug, version := parseSlugVersion(os.Args[2:], true)
		if err := builder.Verify(slug, version); err != nil {
			fail(err)
		}
		fmt.Printf("verify erfolgreich: %s %s\n", slug, version)

	case "list":
		templates, err := builder.List()
		if err != nil {
			fail(err)
		}
		for _, t := range templates {
			fmt.Printf("%-12s %-24s type=%s strategy=%s\n",
				t.Slug, t.Name, t.Type, t.Image.Strategy)
		}

	case "prune":
		fs := flag.NewFlagSet("prune", flag.ExitOnError)
		keep := fs.Int("keep", 3, "Anzahl zu behaltender Versionen")
		_ = fs.Parse(os.Args[2:])
		removed, err := builder.Prune(*keep)
		if err != nil {
			fail(err)
		}
		fmt.Printf("prune abgeschlossen: %d versionen entfernt\n", removed)

	default:
		fmt.Fprintf(os.Stderr, "unbekannter befehl: %s\n\n", cmd)
		printUsage()
		os.Exit(1)
	}
}

func parseSlugVersion(args []string, requireVersion bool) (string, string) {
	if len(args) < 1 {
		fail(fmt.Errorf("template slug erforderlich"))
	}
	slug := args[0]

	fs := flag.NewFlagSet("command", flag.ExitOnError)
	version := fs.String("version", "", "Image-Version")
	_ = fs.Parse(args[1:])

	if requireVersion && *version == "" {
		fail(fmt.Errorf("--version ist erforderlich"))
	}
	return slug, *version
}

func requireArg(args []string, idx int, name string) string {
	if len(args) <= idx {
		fail(fmt.Errorf("%s erforderlich", name))
	}
	return args[idx]
}

func defaultTemplatesDir() string {
	exe, err := os.Executable()
	if err != nil {
		return "../templates/games"
	}
	return filepath.Clean(filepath.Join(filepath.Dir(exe), "..", "..", "..", "templates", "games"))
}

func defaultProjectRoot(templatesDir string) string {
	return filepath.Clean(filepath.Join(templatesDir, "..", ".."))
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func fail(err error) {
	fmt.Fprintf(os.Stderr, "fehler: %v\n", err)
	os.Exit(1)
}

func printUsage() {
	usage := `gamepanel-image – GamePanel Image Builder

Verwendung:
  gamepanel-image build <template> --version X
  gamepanel-image update <template>
  gamepanel-image publish <template> --version X
  gamepanel-image verify <template> --version X
  gamepanel-image list
  gamepanel-image prune --keep 3

Umgebungsvariablen:
  GAMEPANEL_IMAGE_ROOT      Ausgabeverzeichnis (Standard: /srv/gamepanel-images)
  GAMEPANEL_TEMPLATES_DIR   Template-Verzeichnis
  GAMEPANEL_PROJECT_ROOT    Projektroot für Skripte
  STEAMCMD_PATH             Pfad zu steamcmd
  FTP_HOST, FTP_USER, FTP_PASS  FTP-Zugangsdaten
  SIGNING_KEY_PATH          Optional: Ed25519-Privatkey
`
	fmt.Fprint(os.Stderr, usage)
}
