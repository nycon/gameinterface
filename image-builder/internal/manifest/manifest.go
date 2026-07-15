package manifest

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// FileEntry beschreibt eine Datei im Image.
type FileEntry struct {
	Path string `json:"path"`
	Size int64  `json:"size"`
	Hash string `json:"hash,omitempty"`
}

// Manifest beschreibt ein gebautes Game-Image.
type Manifest struct {
	Slug        string      `json:"slug"`
	Name        string      `json:"name"`
	Version     string      `json:"version"`
	Type        string      `json:"type"`
	SteamAppID  string      `json:"steam_app_id,omitempty"`
	Archive     string      `json:"archive"`
	ArchiveSize int64       `json:"archive_size"`
	SHA256      string      `json:"sha256"`
	FileCount   int         `json:"file_count"`
	TotalBytes  int64       `json:"total_bytes"`
	BuiltAt     time.Time   `json:"built_at"`
	Signature   string      `json:"signature,omitempty"`
	Files       []FileEntry `json:"files,omitempty"`
}

// Latest zeigt die aktuell veröffentlichte Version.
type Latest struct {
	Slug      string    `json:"slug"`
	Version   string    `json:"version"`
	SHA256    string    `json:"sha256"`
	UpdatedAt time.Time `json:"updated_at"`
}

// WriteManifest schreibt manifest.json für eine Version.
func WriteManifest(path string, m Manifest) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0o644)
}

// ReadManifest liest ein Manifest.
func ReadManifest(path string) (*Manifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var m Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	return &m, nil
}

// WriteLatest aktualisiert latest.json im Slug-Verzeichnis.
func WriteLatest(slugDir string, latest Latest) error {
	path := filepath.Join(slugDir, "latest.json")
	data, err := json.MarshalIndent(latest, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0o644)
}

// ParseListFile liest eine .lst-Datei und erzeugt FileEntries.
func ParseListFile(path string) ([]FileEntry, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var entries []FileEntry
	for _, line := range splitLines(string(data)) {
		if line == "" {
			continue
		}
		parts := splitTab(line)
		if len(parts) < 2 {
			continue
		}
		var size int64
		fmt.Sscanf(parts[1], "%d", &size)
		entries = append(entries, FileEntry{
			Path: parts[0],
			Size: size,
		})
	}
	return entries, nil
}

// HashManifest berechnet SHA256 über den kanonischen JSON-Inhalt ohne Signatur.
func HashManifest(m Manifest) (string, error) {
	m.Signature = ""
	data, err := json.Marshal(m)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:]), nil
}

func splitLines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			line := s[start:i]
			if len(line) > 0 && line[len(line)-1] == '\r' {
				line = line[:len(line)-1]
			}
			lines = append(lines, line)
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

func splitTab(s string) []string {
	var parts []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\t' {
			parts = append(parts, s[start:i])
			start = i + 1
		}
	}
	parts = append(parts, s[start:])
	return parts
}
