package images

import (
	"archive/tar"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/klauspost/compress/zstd"
)

const maxExtractSize = 20 << 30 // 20 GiB

// ExtractTarZst extrahiert ein tar.zst Archiv sicher nach destDir.
func ExtractTarZst(archivePath, destDir string) error {
	destAbs, err := filepath.Abs(destDir)
	if err != nil {
		return fmt.Errorf("ziel absolut: %w", err)
	}

	if err := os.MkdirAll(destAbs, 0o750); err != nil {
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

	tr := tar.NewReader(zr)
	var written int64

	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("tar lesen: %w", err)
		}

		target, err := safeExtractPath(destAbs, hdr.Name)
		if err != nil {
			return err
		}

		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o750); err != nil {
				return fmt.Errorf("verzeichnis erstellen: %w", err)
			}
		case tar.TypeReg, tar.TypeRegA:
			if err := os.MkdirAll(filepath.Dir(target), 0o750); err != nil {
				return fmt.Errorf("elternverzeichnis: %w", err)
			}

			mode := hdr.FileInfo().Mode() & 0o777
			if mode&0o0222 != 0 {
				mode &^= 0o0222 // keine world-writable dateien
			}

			out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
			if err != nil {
				return fmt.Errorf("datei erstellen: %w", err)
			}

			n, err := io.Copy(out, io.LimitReader(tr, maxExtractSize-written+1))
			out.Close()
			written += n
			if written > maxExtractSize {
				return fmt.Errorf("archiv überschreitet max. extraktionsgröße")
			}
			if err != nil {
				return fmt.Errorf("datei schreiben: %w", err)
			}
		case tar.TypeSymlink:
			if err := validateSymlink(destAbs, target, hdr.Linkname); err != nil {
				return err
			}
			if err := os.Symlink(hdr.Linkname, target); err != nil {
				return fmt.Errorf("symlink erstellen: %w", err)
			}
		default:
			return fmt.Errorf("nicht unterstützter tar-eintrag: %c in %s", hdr.Typeflag, hdr.Name)
		}
	}

	return nil
}

func safeExtractPath(destRoot, name string) (string, error) {
	clean := filepath.Clean(name)
	if filepath.IsAbs(clean) || strings.HasPrefix(clean, "..") {
		return "", fmt.Errorf("path traversal verweigert: %s", name)
	}
	clean = strings.TrimPrefix(clean, "/")

	target := filepath.Join(destRoot, clean)
	abs, err := filepath.Abs(target)
	if err != nil {
		return "", err
	}

	rel, err := filepath.Rel(destRoot, abs)
	if err != nil {
		return "", err
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return "", fmt.Errorf("path traversal verweigert: %s", name)
	}
	return abs, nil
}

func validateSymlink(destRoot, linkPath, target string) error {
	if filepath.IsAbs(target) {
		return fmt.Errorf("absolute symlink-ziele verboten: %s -> %s", linkPath, target)
	}
	clean := filepath.Clean(target)
	if strings.HasPrefix(clean, "..") {
		return fmt.Errorf("symlink traversal verweigert: %s -> %s", linkPath, target)
	}

	resolved := filepath.Join(filepath.Dir(linkPath), clean)
	rel, err := filepath.Rel(destRoot, resolved)
	if err != nil {
		return err
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return fmt.Errorf("symlink zeigt außerhalb des ziels: %s", target)
	}
	return nil
}
