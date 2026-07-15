package files

import (
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

type Entry struct {
	Name    string `json:"name"`
	Path    string `json:"path"`
	Size    int64  `json:"size"`
	Mode    string `json:"mode"`
	IsDir   bool   `json:"is_dir"`
	ModTime int64  `json:"mod_time"`
}

type Manager struct {
	baseDir string
}

func NewManager(baseDir string) *Manager {
	return &Manager{baseDir: baseDir}
}

func (m *Manager) Resolve(serverID, relPath string) (string, error) {
	root := filepath.Join(m.baseDir, serverID)
	clean := filepath.Clean("/" + relPath)
	target := filepath.Join(root, clean)

	rel, err := filepath.Rel(root, target)
	if err != nil {
		return "", fmt.Errorf("pfad ungültig: %w", err)
	}
	if strings.HasPrefix(rel, "..") {
		return "", fmt.Errorf("pfad traversal verweigert: %s", relPath)
	}
	return target, nil
}

func (m *Manager) List(serverID, relPath string) ([]Entry, error) {
	dir, err := m.Resolve(serverID, relPath)
	if err != nil {
		return nil, err
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("verzeichnis lesen: %w", err)
	}

	result := make([]Entry, 0, len(entries))
	for _, e := range entries {
		info, err := e.Info()
		if err != nil {
			continue
		}
		result = append(result, Entry{
			Name:    e.Name(),
			Path:    filepath.Join(relPath, e.Name()),
			Size:    info.Size(),
			Mode:    info.Mode().String(),
			IsDir:   e.IsDir(),
			ModTime: info.ModTime().Unix(),
		})
	}
	return result, nil
}

func (m *Manager) Read(serverID, relPath string, maxBytes int64) ([]byte, error) {
	path, err := m.Resolve(serverID, relPath)
	if err != nil {
		return nil, err
	}

	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("datei öffnen: %w", err)
	}
	defer f.Close()

	if maxBytes <= 0 {
		maxBytes = 8 << 20
	}
	return io.ReadAll(io.LimitReader(f, maxBytes))
}

func (m *Manager) Write(serverID, relPath string, data []byte, mode fs.FileMode) error {
	path, err := m.Resolve(serverID, relPath)
	if err != nil {
		return err
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("verzeichnis erstellen: %w", err)
	}

	if mode == 0 {
		mode = 0o640
	}

	if err := os.WriteFile(path, data, mode); err != nil {
		return fmt.Errorf("datei schreiben: %w", err)
	}
	return nil
}

func (m *Manager) Delete(serverID, relPath string) error {
	path, err := m.Resolve(serverID, relPath)
	if err != nil {
		return err
	}

	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("stat: %w", err)
	}
	if info.IsDir() {
		return fmt.Errorf("verzeichnisse müssen rekursiv gelöscht werden")
	}
	return os.Remove(path)
}

func (m *Manager) ResolveRoot(root, relPath string) (string, error) {
	clean := filepath.Clean("/" + relPath)
	target := filepath.Join(root, clean)

	rel, err := filepath.Rel(root, target)
	if err != nil {
		return "", fmt.Errorf("pfad ungültig: %w", err)
	}
	if strings.HasPrefix(rel, "..") {
		return "", fmt.Errorf("pfad traversal verweigert: %s", relPath)
	}
	return target, nil
}

func (m *Manager) ListIn(root, relPath string) ([]Entry, error) {
	dir, err := m.ResolveRoot(root, relPath)
	if err != nil {
		return nil, err
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return []Entry{}, nil
		}
		return nil, fmt.Errorf("verzeichnis lesen: %w", err)
	}

	result := make([]Entry, 0, len(entries))
	for _, e := range entries {
		info, err := e.Info()
		if err != nil {
			continue
		}
		p := filepath.Join(relPath, e.Name())
		if relPath == "/" || relPath == "" {
			p = "/" + e.Name()
		}
		result = append(result, Entry{
			Name:    e.Name(),
			Path:    p,
			Size:    info.Size(),
			Mode:    info.Mode().String(),
			IsDir:   e.IsDir(),
			ModTime: info.ModTime().Unix(),
		})
	}
	return result, nil
}

func (m *Manager) ReadIn(root, relPath string, maxBytes int64) ([]byte, error) {
	path, err := m.ResolveRoot(root, relPath)
	if err != nil {
		return nil, err
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("datei öffnen: %w", err)
	}
	defer f.Close()
	if maxBytes <= 0 {
		maxBytes = 8 << 20
	}
	return io.ReadAll(io.LimitReader(f, maxBytes))
}

func (m *Manager) WriteIn(root, relPath string, data []byte, mode fs.FileMode) error {
	path, err := m.ResolveRoot(root, relPath)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("verzeichnis erstellen: %w", err)
	}
	if mode == 0 {
		mode = 0o640
	}
	return os.WriteFile(path, data, mode)
}

func (m *Manager) EnsureServerDir(serverID string) (string, error) {
	dir := filepath.Join(m.baseDir, serverID)
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return "", fmt.Errorf("server-verzeichnis: %w", err)
	}
	return dir, nil
}
