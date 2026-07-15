//go:build !linux

package users

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

var validLinuxUser = regexp.MustCompile(`^[a-z_][a-z0-9_-]{0,31}$`)

type Manager struct {
	serversDir string
}

func NewManager(serversDir string) *Manager {
	return &Manager{serversDir: serversDir}
}

func SanitizeUsername(preferred, serverKey string) string {
	preferred = strings.TrimSpace(strings.ToLower(preferred))
	if preferred != "" && validLinuxUser.MatchString(preferred) {
		return preferred
	}
	if id, err := strconv.ParseUint(serverKey, 10, 64); err == nil && id > 0 {
		return fmt.Sprintf("gp-s%d", id)
	}
	hex := strings.ReplaceAll(strings.ToLower(serverKey), "-", "")
	if len(hex) > 12 {
		hex = hex[:12]
	}
	if hex == "" {
		hex = "0"
	}
	return "gp" + hex
}

func Username(serverID string) string {
	return SanitizeUsername("", serverID)
}

func (m *Manager) Ensure(serverID string) (string, error) {
	return m.EnsureNamed(serverID, "")
}

func (m *Manager) EnsureNamed(serverKey, preferredUsername string) (string, error) {
	return SanitizeUsername(preferredUsername, serverKey), nil
}

func (m *Manager) Delete(serverID string) error { return nil }

func (m *Manager) ChownTree(path, username string) error { return nil }
