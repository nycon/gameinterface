//go:build linux

package users

import (
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
)

const minUID = 20000

type Manager struct {
	serversDir string
}

func NewManager(serversDir string) *Manager {
	return &Manager{serversDir: serversDir}
}

func Username(serverID string) string {
	return fmt.Sprintf("gp-s%s", serverID)
}

func (m *Manager) Ensure(serverID string) (string, error) {
	username := Username(serverID)
	if _, err := user.Lookup(username); err == nil {
		return username, nil
	}

	uid, err := m.nextUID()
	if err != nil {
		return "", err
	}

	home := filepath.Join(m.serversDir, serverID)
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

func (m *Manager) nextUID() (int, error) {
	for uid := minUID; uid < minUID+100000; uid++ {
		if _, err := user.LookupId(strconv.Itoa(uid)); err != nil {
			return uid, nil
		}
	}
	return 0, fmt.Errorf("keine freie uid gefunden")
}
