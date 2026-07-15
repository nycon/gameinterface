package archive

import (
	"archive/tar"
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/klauspost/compress/zstd"
)

// CreateOptions steuert Archiv-Erstellung und Metadaten.
type CreateOptions struct {
	SourceDir       string
	OutputPath      string
	ListPath        string
	ExcludePatterns []string
}

// Create erstellt ein tar.zst-Archiv und eine .lst-Datei mit Dateiliste.
func Create(opts CreateOptions) (fileCount int, totalBytes int64, err error) {
	if err := os.MkdirAll(filepath.Dir(opts.OutputPath), 0o755); err != nil {
		return 0, 0, fmt.Errorf("output-dir anlegen: %w", err)
	}

	files, err := collectFiles(opts.SourceDir, opts.ExcludePatterns)
	if err != nil {
		return 0, 0, err
	}

	outFile, err := os.Create(opts.OutputPath)
	if err != nil {
		return 0, 0, fmt.Errorf("archiv anlegen: %w", err)
	}
	defer outFile.Close()

	zw, err := zstd.NewWriter(outFile, zstd.WithEncoderLevel(zstd.SpeedDefault))
	if err != nil {
		return 0, 0, fmt.Errorf("zstd writer: %w", err)
	}

	listFile, err := os.Create(opts.ListPath)
	if err != nil {
		return 0, 0, fmt.Errorf("lst anlegen: %w", err)
	}
	defer listFile.Close()

	listWriter := bufio.NewWriter(listFile)
	defer listWriter.Flush()

	tw := tar.NewWriter(zw)
	defer tw.Close()

	for _, rel := range files {
		abs := filepath.Join(opts.SourceDir, rel)
		info, err := os.Stat(abs)
		if err != nil {
			return 0, 0, err
		}
		if info.IsDir() {
			continue
		}

		if err := writeTarEntry(tw, opts.SourceDir, rel, info); err != nil {
			return 0, 0, err
		}

		line := fmt.Sprintf("%s\t%d\t%s\n", rel, info.Size(), info.ModTime().UTC().Format(time.RFC3339))
		if _, err := listWriter.WriteString(line); err != nil {
			return 0, 0, err
		}

		fileCount++
		totalBytes += info.Size()
	}

	if err := tw.Close(); err != nil {
		return 0, 0, fmt.Errorf("tar schließen: %w", err)
	}
	if err := zw.Close(); err != nil {
		return 0, 0, fmt.Errorf("archiv schließen: %w", err)
	}

	return fileCount, totalBytes, nil
}

func writeTarEntry(tw *tar.Writer, sourceDir, rel string, info os.FileInfo) error {
	hdr, err := tar.FileInfoHeader(info, "")
	if err != nil {
		return err
	}
	hdr.Name = rel

	if err := tw.WriteHeader(hdr); err != nil {
		return err
	}

	f, err := os.Open(filepath.Join(sourceDir, rel))
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = io.Copy(tw, f)
	return err
}

// WriteSHA256 schreibt die SHA256-Checksumme einer Datei.
func WriteSHA256(filePath, shaPath string) (string, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return "", err
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	sum := hex.EncodeToString(h.Sum(nil))

	content := fmt.Sprintf("%s  %s\n", sum, filepath.Base(filePath))
	if err := os.WriteFile(shaPath, []byte(content), 0o644); err != nil {
		return "", err
	}
	return sum, nil
}

// VerifySHA256 prüft eine Datei gegen eine .sha256-Datei.
func VerifySHA256(filePath, shaPath string) error {
	data, err := os.ReadFile(shaPath)
	if err != nil {
		return err
	}
	fields := strings.Fields(string(data))
	if len(fields) < 1 {
		return fmt.Errorf("ungültige sha256-datei: %s", shaPath)
	}
	expected := fields[0]

	f, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return err
	}
	actual := hex.EncodeToString(h.Sum(nil))

	if actual != expected {
		return fmt.Errorf("sha256 stimmt nicht überein: erwartet %s, erhalten %s", expected, actual)
	}
	return nil
}

func collectFiles(root string, excludes []string) ([]string, error) {
	var files []string
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		if matchesExclude(rel, excludes) {
			return nil
		}
		files = append(files, filepath.ToSlash(rel))
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(files)
	return files, nil
}

func matchesExclude(rel string, patterns []string) bool {
	for _, pattern := range patterns {
		if matched, _ := filepath.Match(pattern, rel); matched {
			return true
		}
		trimmed := strings.TrimSuffix(pattern, "/**")
		if strings.HasPrefix(rel, trimmed+"/") {
			return true
		}
	}
	return false
}
