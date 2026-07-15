package images

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/gamepanel/agent/internal/config"
	"github.com/gamepanel/agent/internal/ftpclient"
	"github.com/gamepanel/agent/internal/sftpclient"
)

type Downloader struct {
	cfg *config.Config
}

func NewDownloader(cfg *config.Config) *Downloader {
	return &Downloader{cfg: cfg}
}

type DownloadRequest struct {
	RemotePath string
	LocalName  string
	Manifest   *Manifest
}

type DownloadResult struct {
	LocalPath   string
	ArchivePath string
	Extracted   bool
}

func (d *Downloader) Download(ctx context.Context, req DownloadRequest) (*DownloadResult, error) {
	if err := os.MkdirAll(d.cfg.Paths.ImagesDir, 0o750); err != nil {
		return nil, fmt.Errorf("images-verzeichnis: %w", err)
	}

	localName := req.LocalName
	if localName == "" {
		localName = filepath.Base(req.RemotePath)
	}
	dest := filepath.Join(d.cfg.Paths.ImagesDir, localName)

	if d.cfg.SFTP.Enabled {
		client, err := sftpclient.New(d.cfg.SFTP)
		if err != nil {
			return nil, fmt.Errorf("sftp-client: %w", err)
		}
		defer client.Close()

		if err := client.Download(ctx, req.RemotePath, dest); err != nil {
			return nil, fmt.Errorf("sftp download: %w", err)
		}
	} else if d.cfg.FTP.Enabled {
		client, err := ftpclient.New(d.cfg.FTP)
		if err != nil {
			return nil, fmt.Errorf("ftp-client: %w", err)
		}
		defer client.Close()

		if err := client.Download(ctx, req.RemotePath, dest); err != nil {
			return nil, fmt.Errorf("ftp download: %w", err)
		}
	} else {
		return nil, fmt.Errorf("weder sftp noch ftp aktiviert")
	}

	result := &DownloadResult{
		LocalPath:   dest,
		ArchivePath: dest,
	}

	if req.Manifest != nil {
		if err := VerifySHA256(dest, req.Manifest.SHA256); err != nil {
			_ = os.Remove(dest)
			return nil, err
		}

		extractDir := filepath.Join(d.cfg.Paths.ImagesDir, req.Manifest.ID)
		if err := ExtractTarZst(dest, extractDir); err != nil {
			return nil, fmt.Errorf("extraktion: %w", err)
		}
		result.LocalPath = extractDir
		result.Extracted = true
	}

	return result, nil
}

func (d *Downloader) DownloadManifest(ctx context.Context, remoteManifest string) (*Manifest, error) {
	tmp := filepath.Join(d.cfg.Paths.ImagesDir, ".manifest.tmp")
	defer os.Remove(tmp)

	if d.cfg.SFTP.Enabled {
		client, err := sftpclient.New(d.cfg.SFTP)
		if err != nil {
			return nil, err
		}
		defer client.Close()
		if err := client.Download(ctx, remoteManifest, tmp); err != nil {
			return nil, err
		}
	} else if d.cfg.FTP.Enabled {
		client, err := ftpclient.New(d.cfg.FTP)
		if err != nil {
			return nil, err
		}
		defer client.Close()
		if err := client.Download(ctx, remoteManifest, tmp); err != nil {
			return nil, err
		}
	} else {
		return nil, fmt.Errorf("kein transfer-backend konfiguriert")
	}

	return ParseManifestFile(tmp)
}
