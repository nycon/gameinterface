//go:build !linux

package users

import "fmt"

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
	return "", fmt.Errorf("benutzerverwaltung nur auf linux verfügbar")
}

func (m *Manager) Delete(serverID string) error {
	return fmt.Errorf("benutzerverwaltung nur auf linux verfügbar")
}
