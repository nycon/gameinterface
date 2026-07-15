package build

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"time"

	"github.com/gamepanel/image-builder/internal/archive"
	"github.com/gamepanel/image-builder/internal/ftp"
	"github.com/gamepanel/image-builder/internal/manifest"
	"github.com/gamepanel/image-builder/internal/signing"
	"github.com/gamepanel/image-builder/internal/steamcmd"
	"github.com/gamepanel/image-builder/internal/templates"
)

const defaultImageRoot = "/srv/gamepanel-images"

// Builder orchestriert Build-, Verify-, Publish- und Prune-Operationen.
type Builder struct {
	ImageRoot    string
	TemplatesDir string
	ProjectRoot  string
	Loader       *templates.Loader
	SteamCMD     *steamcmd.Runner
	Signer       *signing.Signer
}

// NewBuilder erstellt einen Builder mit Standardpfaden.
func NewBuilder(templatesDir, projectRoot string) (*Builder, error) {
	imageRoot := os.Getenv("GAMEPANEL_IMAGE_ROOT")
	if imageRoot == "" {
		imageRoot = defaultImageRoot
	}

	signer, err := signing.LoadSigner("")
	if err != nil {
		return nil, err
	}

	return &Builder{
		ImageRoot:    imageRoot,
		TemplatesDir: templatesDir,
		ProjectRoot:  projectRoot,
		Loader:       templates.NewLoader(templatesDir),
		SteamCMD:     steamcmd.NewRunner(),
		Signer:       signer,
	}, nil
}

// VersionPaths enthält alle Pfade für eine Image-Version.
type VersionPaths struct {
	SlugDir      string
	VersionDir   string
	ArchivePath  string
	ManifestPath string
	ListPath     string
	SHA256Path   string
	BaseName     string
}

// PathsFor berechnet alle Ausgabepfade für slug/version.
func (b *Builder) PathsFor(slug, version string) VersionPaths {
	baseName := fmt.Sprintf("%s-%s", slug, version)
	versionDir := filepath.Join(b.ImageRoot, "games", slug, "versions", version)
	return VersionPaths{
		SlugDir:      filepath.Join(b.ImageRoot, "games", slug),
		VersionDir:   versionDir,
		ArchivePath:  filepath.Join(versionDir, baseName+".tar.zst"),
		ManifestPath: filepath.Join(versionDir, baseName+".manifest.json"),
		ListPath:     filepath.Join(versionDir, baseName+".lst"),
		SHA256Path:   filepath.Join(versionDir, baseName+".sha256"),
		BaseName:     baseName,
	}
}

// Build erstellt ein vollständiges Image für ein Template.
func (b *Builder) Build(ctx context.Context, slug, version string) (*manifest.Manifest, error) {
	tmpl, err := b.Loader.Load(slug)
	if err != nil {
		return nil, err
	}
	if version == "" {
		return nil, fmt.Errorf("version ist erforderlich")
	}

	if err := b.runUpdate(ctx, tmpl); err != nil {
		return nil, fmt.Errorf("update vor build: %w", err)
	}

	sourceDir := b.sourceDir(tmpl)
	if _, err := os.Stat(sourceDir); err != nil {
		return nil, fmt.Errorf("quellverzeichnis fehlt: %s", sourceDir)
	}

	paths := b.PathsFor(slug, version)
	if err := os.MkdirAll(paths.VersionDir, 0o755); err != nil {
		return nil, err
	}

	fileCount, totalBytes, err := archive.Create(archive.CreateOptions{
		SourceDir:       sourceDir,
		OutputPath:      paths.ArchivePath,
		ListPath:        paths.ListPath,
		ExcludePatterns: tmpl.Image.ExcludePatterns,
	})
	if err != nil {
		return nil, fmt.Errorf("archiv erstellen: %w", err)
	}

	sha256sum, err := archive.WriteSHA256(paths.ArchivePath, paths.SHA256Path)
	if err != nil {
		return nil, fmt.Errorf("sha256 schreiben: %w", err)
	}

	archiveInfo, err := os.Stat(paths.ArchivePath)
	if err != nil {
		return nil, err
	}

	files, err := manifest.ParseListFile(paths.ListPath)
	if err != nil {
		return nil, err
	}

	m := manifest.Manifest{
		Slug:        tmpl.Slug,
		Name:        tmpl.Name,
		Version:     version,
		Type:        tmpl.Type,
		SteamAppID:  tmpl.SteamAppID,
		Archive:     filepath.Base(paths.ArchivePath),
		ArchiveSize: archiveInfo.Size(),
		SHA256:      sha256sum,
		FileCount:   fileCount,
		TotalBytes:  totalBytes,
		BuiltAt:     time.Now().UTC(),
		Files:       files,
	}

	if err := b.Signer.SignManifest(&m); err != nil {
		return nil, fmt.Errorf("manifest signieren: %w", err)
	}
	if err := manifest.WriteManifest(paths.ManifestPath, m); err != nil {
		return nil, fmt.Errorf("manifest schreiben: %w", err)
	}

	return &m, nil
}

// Update führt nur den Update-Schritt für ein Template aus.
func (b *Builder) Update(ctx context.Context, slug string) error {
	tmpl, err := b.Loader.Load(slug)
	if err != nil {
		return err
	}
	return b.runUpdate(ctx, tmpl)
}

func (b *Builder) runUpdate(ctx context.Context, tmpl *templates.GameTemplate) error {
	sourceDir := b.sourceDir(tmpl)

	switch {
	case steamcmd.IsSteamTemplate(tmpl.Type, tmpl.Image.Strategy):
		return b.SteamCMD.Update(ctx, steamcmd.Config{
			InstallDir: sourceDir,
			AppID:      tmpl.SteamAppID,
			Validate:   true,
		})
	case tmpl.Update.Script != "":
		scriptPath, err := steamcmd.ResolveScriptPath(b.ProjectRoot, tmpl.Update.Script)
		if err != nil {
			return err
		}
		env := map[string]string{
			"SERVER_DIR":   sourceDir,
			"STEAM_APP_ID": tmpl.SteamAppID,
			"TEMPLATE_SLUG": tmpl.Slug,
		}
		for k, v := range tmpl.Update.Env {
			env[k] = v
		}
		return steamcmd.RunScript(ctx, scriptPath, env, tmpl.Update.Args...)
	default:
		return fmt.Errorf("kein update-verfahren für template %s definiert", tmpl.Slug)
	}
}

func (b *Builder) sourceDir(tmpl *templates.GameTemplate) string {
	if tmpl.Image.BuildDir != "" {
		if filepath.IsAbs(tmpl.Image.BuildDir) {
			return tmpl.Image.BuildDir
		}
		return filepath.Join(b.ImageRoot, tmpl.Image.BuildDir)
	}
	return steamcmd.InstallDirFor(b.ImageRoot, tmpl.Slug)
}

// Verify prüft Checksummen und Manifest-Konsistenz.
func (b *Builder) Verify(slug, version string) error {
	if _, err := b.Loader.Load(slug); err != nil {
		return err
	}
	paths := b.PathsFor(slug, version)

	if err := archive.VerifySHA256(paths.ArchivePath, paths.SHA256Path); err != nil {
		return fmt.Errorf("sha256: %w", err)
	}

	m, err := manifest.ReadManifest(paths.ManifestPath)
	if err != nil {
		return fmt.Errorf("manifest lesen: %w", err)
	}

	actualSHA, err := archive.WriteSHA256(paths.ArchivePath, paths.SHA256Path+".verify")
	if err != nil {
		return err
	}
	_ = os.Remove(paths.SHA256Path + ".verify")

	if m.SHA256 != actualSHA {
		return fmt.Errorf("manifest sha256 stimmt nicht mit archiv überein")
	}
	if m.Version != version {
		return fmt.Errorf("manifest version %q != erwartet %q", m.Version, version)
	}
	if m.Slug != slug {
		return fmt.Errorf("manifest slug %q != erwartet %q", m.Slug, slug)
	}

	if _, err := os.Stat(paths.ListPath); err != nil {
		return fmt.Errorf("lst fehlt: %w", err)
	}

	return nil
}

// Publish veröffentlicht ein Image auf dem Image-Server.
func (b *Builder) Publish(slug, version string) error {
	tmpl, err := b.Loader.Load(slug)
	if err != nil {
		return err
	}
	if err := b.Verify(slug, version); err != nil {
		return fmt.Errorf("verify vor publish: %w", err)
	}

	cfg, err := ftp.ConfigFromEnv()
	if err != nil {
		return err
	}
	publisher := ftp.NewPublisher(cfg)

	paths := b.PathsFor(slug, version)
	remotePath := filepath.Join(tmpl.Image.ImageServerPath, "versions", version)
	if err := publisher.PublishFiles(paths.VersionDir, remotePath); err != nil {
		return err
	}

	m, err := manifest.ReadManifest(paths.ManifestPath)
	if err != nil {
		return err
	}

	if err := ftp.PublishManifest(paths.SlugDir, version, m.SHA256); err != nil {
		return err
	}

	latestPath := filepath.Join(paths.SlugDir, "latest.json")
	return publisher.UpdateLatest(latestPath, tmpl.Image.ImageServerPath)
}

// List gibt alle Templates zurück.
func (b *Builder) List() ([]*templates.GameTemplate, error) {
	return b.Loader.List()
}

// Prune löscht alte Versionen und behält die neuesten N.
func (b *Builder) Prune(keep int) (int, error) {
	if keep < 1 {
		return 0, fmt.Errorf("keep muss >= 1 sein")
	}

	gamesDir := filepath.Join(b.ImageRoot, "games")
	entries, err := os.ReadDir(gamesDir)
	if err != nil {
		if os.IsNotExist(err) {
			return 0, nil
		}
		return 0, err
	}

	removed := 0
	for _, slugEntry := range entries {
		if !slugEntry.IsDir() {
			continue
		}
		versionsDir := filepath.Join(gamesDir, slugEntry.Name(), "versions")
		versions, err := os.ReadDir(versionsDir)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return removed, err
		}

		var versionNames []string
		for _, v := range versions {
			if v.IsDir() {
				versionNames = append(versionNames, v.Name())
			}
		}
		sort.Slice(versionNames, func(i, j int) bool {
			return compareVersions(versionNames[i], versionNames[j]) > 0
		})

		for i := keep; i < len(versionNames); i++ {
			target := filepath.Join(versionsDir, versionNames[i])
			if err := os.RemoveAll(target); err != nil {
				return removed, fmt.Errorf("löschen %s: %w", target, err)
			}
			removed++
		}
	}
	return removed, nil
}

func compareVersions(a, b string) int {
	aParts := splitVersion(a)
	bParts := splitVersion(b)
	maxLen := len(aParts)
	if len(bParts) > maxLen {
		maxLen = len(bParts)
	}
	for i := 0; i < maxLen; i++ {
		var av, bv int
		if i < len(aParts) {
			av = aParts[i]
		}
		if i < len(bParts) {
			bv = bParts[i]
		}
		if av != bv {
			return av - bv
		}
	}
	return 0
}

func splitVersion(v string) []int {
	parts := []int{}
	current := ""
	for _, ch := range v {
		if ch >= '0' && ch <= '9' {
			current += string(ch)
		} else if current != "" {
			n, _ := strconv.Atoi(current)
			parts = append(parts, n)
			current = ""
		}
	}
	if current != "" {
		n, _ := strconv.Atoi(current)
		parts = append(parts, n)
	}
	return parts
}
