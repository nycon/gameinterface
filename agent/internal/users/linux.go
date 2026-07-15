//go:build linux

package users

import (
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

const minUID = 20000

var validLinuxUser = regexp.MustCompile(`^[a-z_][a-z0-9_-]{0,31}$`)

type Manager struct {
	serversDir string
}

func NewManager(serversDir string) *Manager {
	return &Manager{serversDir: serversDir}
}

// SanitizeUsername erzeugt einen useradd-kompatiblen Namen (max 32, keine UUID-Hyphens).
func SanitizeUsername(preferred, serverKey string) string {
	preferred = strings.TrimSpace(strings.ToLower(preferred))
	if preferred != "" && validLinuxUser.MatchString(preferred) && !strings.Contains(preferred, "--") {
		return preferred
	}

	// Numerische ID: gp-s42
	if id, err := strconv.ParseUint(serverKey, 10, 64); err == nil && id > 0 {
		u := fmt.Sprintf("gp-s%d", id)
		if validLinuxUser.MatchString(u) {
			return u
		}
	}

	// UUID → gp + 12 Hex ohne Bindestriche
	hex := strings.ReplaceAll(strings.ToLower(serverKey), "-", "")
	hex = regexp.MustCompile(`[^a-f0-9]`).ReplaceAllString(hex, "")
	if len(hex) > 12 {
		hex = hex[:12]
	}
	if hex == "" {
		hex = "0"
	}
	u := "gp" + hex
	if len(u) > 32 {
		u = u[:32]
	}
	return u
}

func Username(serverID string) string {
	return SanitizeUsername("", serverID)
}

func (m *Manager) Ensure(serverID string) (string, error) {
	return m.EnsureNamed(serverID, "")
}

func (m *Manager) EnsureNamed(serverKey, preferredUsername string) (string, error) {
	username := SanitizeUsername(preferredUsername, serverKey)
	if _, err := user.Lookup(username); err == nil {
		return username, nil
	}

	uid, err := m.nextUID()
	if err != nil {
		return "", err
	}

	home := filepath.Join(m.serversDir, serverKey)
	if err := os.MkdirAll(home, 0o750); err != nil {
		return "", fmt.Errorf("server-verzeichnis erstellen: %w", err)
	}

	cmd := exec.Command("useradd",
		"--system",
		"--home-dir", home,
		"--shell", "/usr/sbin/nologin",
		"--no-create-home",
		"--uid", strconv.Itoa(uid),
		username,
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("useradd fehlgeschlagen: %w: %s", err, string(out))
	}

	if err := os.Chown(home, uid, uid); err != nil {
		return "", fmt.Errorf("verzeichnis chown: %w", err)
	}

	return username, nil
}

func (m *Manager) Delete(serverID string) error {
	username := Username(serverID)
	cmd := exec.Command("userdel", "--remove", username)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("userdel fehlgeschlagen: %w: %s", err, string(out))
	}
	return nil
}

func (m *Manager) ChownTree(path, username string) error {
	u, err := user.Lookup(username)
	if err != nil {
		return err
	}
	uid, _ := strconv.Atoi(u.Uid)
	gid, _ := strconv.Atoi(u.Gid)
	return filepath.Walk(path, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		return os.Chown(p, uid, gid)
	})
}

func (m *Manager) nextUID() (int, error) {
	for uid := minUID; uid < minUID+100000; uid++ {
		if _, err := user.LookupId(strconv.Itoa(uid)); err != nil {
			return uid, nil
		}
	}
	return 0, fmt.Errorf("keine freie uid gefunden")
}
