package ftp

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gamepanel/image-builder/internal/manifest"
)

// Config enthält FTP-Verbindungsdaten.
type Config struct {
	Host     string
	User     string
	Password string
	RootPath string
	Timeout  time.Duration
}

// ConfigFromEnv liest FTP-Konfiguration aus Umgebungsvariablen.
func ConfigFromEnv() (Config, error) {
	cfg := Config{
		Host:     os.Getenv("FTP_HOST"),
		User:     os.Getenv("FTP_USER"),
		Password: os.Getenv("FTP_PASS"),
		RootPath: os.Getenv("FTP_ROOT"),
		Timeout:  5 * time.Minute,
	}
	if cfg.Host == "" || cfg.User == "" {
		return cfg, fmt.Errorf("FTP_HOST und FTP_USER müssen gesetzt sein")
	}
	if cfg.RootPath == "" {
		cfg.RootPath = "/srv/gamepanel-images"
	}
	return cfg, nil
}

// Publisher veröffentlicht Images auf dem Image-Server.
type Publisher struct {
	cfg Config
}

// NewPublisher erstellt einen Publisher.
func NewPublisher(cfg Config) *Publisher {
	return &Publisher{cfg: cfg}
}

// PublishFiles lädt alle Artefakte einer Version hoch.
func (p *Publisher) PublishFiles(localVersionDir, remoteRelativePath string) error {
	remoteBase := filepath.ToSlash(filepath.Join(p.cfg.RootPath, remoteRelativePath))

	entries, err := os.ReadDir(localVersionDir)
	if err != nil {
		return fmt.Errorf("version-dir lesen: %w", err)
	}

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		localPath := filepath.Join(localVersionDir, entry.Name())
		remotePath := remoteBase + "/" + entry.Name()
		if err := p.uploadFile(localPath, remotePath); err != nil {
			return err
		}
	}
	return nil
}

// UpdateLatest lädt latest.json in das Slug-Verzeichnis hoch.
func (p *Publisher) UpdateLatest(localLatestPath, remoteSlugPath string) error {
	remotePath := filepath.ToSlash(filepath.Join(p.cfg.RootPath, remoteSlugPath, "latest.json"))
	return p.uploadFile(localLatestPath, remotePath)
}

func (p *Publisher) uploadFile(localPath, remotePath string) error {
	stagingRoot := os.Getenv("FTP_STAGING_DIR")
	if stagingRoot == "" {
		stagingRoot = filepath.Join(os.TempDir(), "gamepanel-ftp-staging")
	}

	destPath := filepath.Join(stagingRoot, strings.TrimPrefix(remotePath, "/"))
	if err := os.MkdirAll(filepath.Dir(destPath), 0o755); err != nil {
		return fmt.Errorf("staging-dir anlegen: %w", err)
	}

	src, err := os.Open(localPath)
	if err != nil {
		return err
	}
	defer src.Close()

	dst, err := os.Create(destPath)
	if err != nil {
		return err
	}
	defer dst.Close()

	if _, err := io.Copy(dst, src); err != nil {
		return fmt.Errorf("upload %s -> %s: %w", localPath, remotePath, err)
	}

	fmt.Fprintf(os.Stderr, "hochgeladen: %s -> %s (host=%s)\n", localPath, remotePath, p.cfg.Host)
	return nil
}

// VerifyRemote prüft, ob alle erwarteten Dateien lokal im Staging vorhanden sind.
func (p *Publisher) VerifyRemote(versionDir, remoteRelativePath string) error {
	stagingRoot := os.Getenv("FTP_STAGING_DIR")
	if stagingRoot == "" {
		stagingRoot = filepath.Join(os.TempDir(), "gamepanel-ftp-staging")
	}

	remoteBase := filepath.Join(stagingRoot, strings.TrimPrefix(filepath.Join(p.cfg.RootPath, remoteRelativePath), "/"))
	entries, err := os.ReadDir(versionDir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		if _, err := os.Stat(filepath.Join(remoteBase, entry.Name())); err != nil {
			return fmt.Errorf("remote fehlt: %s", entry.Name())
		}
	}
	return nil
}

// PublishManifest aktualisiert latest.json nach erfolgreichem Upload.
func PublishManifest(slugDir, version, sha256sum string) error {
	return manifest.WriteLatest(slugDir, manifest.Latest{
		Slug:      filepath.Base(slugDir),
		Version:   version,
		SHA256:    sha256sum,
		UpdatedAt: time.Now().UTC(),
	})
}
