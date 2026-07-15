package backups

import (
	"archive/tar"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/klauspost/compress/zstd"
)

type Manager struct {
	backupsDir string
}

func NewManager(backupsDir string) *Manager {
	return &Manager{backupsDir: backupsDir}
}

func (m *Manager) Create(ctx context.Context, serverID, sourceDir string) (string, error) {
	if err := os.MkdirAll(m.backupsDir, 0o750); err != nil {
		return "", fmt.Errorf("backup-verzeichnis: %w", err)
	}

	name := fmt.Sprintf("%s-%s.tar.zst", serverID, time.Now().UTC().Format("20060102-150405"))
	dest := filepath.Join(m.backupsDir, name)

	f, err := os.Create(dest)
	if err != nil {
		return "", fmt.Errorf("backup erstellen: %w", err)
	}
	defer f.Close()

	zw, err := zstd.NewWriter(f)
	if err != nil {
		return "", fmt.Errorf("zstd writer: %w", err)
	}
	tw := tar.NewWriter(zw)

	err = filepath.Walk(sourceDir, func(path string, info os.FileInfo, walkErr error) error {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		if walkErr != nil {
			return walkErr
		}
		if info.IsDir() {
			return nil
		}

		rel, err := filepath.Rel(sourceDir, path)
		if err != nil {
			return err
		}
		if strings.HasPrefix(rel, "..") {
			return fmt.Errorf("path traversal: %s", rel)
		}

		hdr, err := tar.FileInfoHeader(info, "")
		if err != nil {
			return err
		}
		hdr.Name = rel

		if err := tw.WriteHeader(hdr); err != nil {
			return err
		}

		src, err := os.Open(path)
		if err != nil {
			return err
		}
		defer src.Close()

		_, err = io.Copy(tw, src)
		return err
	})
	if err != nil {
		_ = tw.Close()
		_ = zw.Close()
		_ = os.Remove(dest)
		return "", err
	}

	if err := tw.Close(); err != nil {
		return "", err
	}
	if err := zw.Close(); err != nil {
		return "", err
	}

	return dest, nil
}

func (m *Manager) Restore(ctx context.Context, archivePath, destDir string) error {
	if err := os.MkdirAll(destDir, 0o750); err != nil {
		return fmt.Errorf("zielverzeichnis: %w", err)
	}

	f, err := os.Open(archivePath)
	if err != nil {
		return fmt.Errorf("archiv öffnen: %w", err)
	}
	defer f.Close()

	zr, err := zstd.NewReader(f)
	if err != nil {
		return fmt.Errorf("zstd reader: %w", err)
	}
	defer zr.Close()

	destAbs, err := filepath.Abs(destDir)
	if err != nil {
		return err
	}

	tr := tar.NewReader(zr)
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("tar lesen: %w", err)
		}

		target, err := safePath(destAbs, hdr.Name)
		if err != nil {
			return err
		}

		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o750); err != nil {
				return err
			}
		case tar.TypeReg, tar.TypeRegA:
			if err := os.MkdirAll(filepath.Dir(target), 0o750); err != nil {
				return err
			}
			out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, hdr.FileInfo().Mode()&0o777)
			if err != nil {
				return err
			}
			if _, err := io.Copy(out, tr); err != nil {
				out.Close()
				return err
			}
			out.Close()
		default:
			return fmt.Errorf("nicht unterstützter eintrag: %s", hdr.Name)
		}
	}
	return nil
}

func safePath(root, name string) (string, error) {
	clean := filepath.Clean(name)
	if filepath.IsAbs(clean) || strings.HasPrefix(clean, "..") {
		return "", fmt.Errorf("path traversal verweigert: %s", name)
	}
	target := filepath.Join(root, strings.TrimPrefix(clean, "/"))
	abs, err := filepath.Abs(target)
	if err != nil {
		return "", err
	}
	rel, err := filepath.Rel(root, abs)
	if err != nil {
		return "", err
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return "", fmt.Errorf("path traversal verweigert: %s", name)
	}
	return abs, nil
}

func (m *Manager) List(serverID string) ([]string, error) {
	entries, err := os.ReadDir(m.backupsDir)
	if err != nil {
		return nil, err
	}
	prefix := serverID + "-"
	var result []string
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), prefix) && strings.HasSuffix(e.Name(), ".tar.zst") {
			result = append(result, filepath.Join(m.backupsDir, e.Name()))
		}
	}
	return result, nil
}
