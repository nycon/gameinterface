//go:build !linux

package systemd

import "fmt"

type ServerSpec struct {
	ServerID    string
	Username    string
	WorkingDir  string
	Executable  string
	Args        []string
	Environment map[string]string
	MemoryMax   string
	CPUPercent  int
	Port        int
}

type Manager struct {
	unitPrefix string
	slice      string
}

func NewManager(unitPrefix, slice string) *Manager {
	return &Manager{unitPrefix: unitPrefix, slice: slice}
}

func (m *Manager) UnitName(serverID string) string {
	return fmt.Sprintf("%s-%s.service", m.unitPrefix, serverID)
}

func (m *Manager) Install(spec ServerSpec) error {
	return fmt.Errorf("systemd nur auf linux verfügbar")
}

func (m *Manager) Start(serverID string) error {
	return fmt.Errorf("systemd nur auf linux verfügbar")
}

func (m *Manager) Stop(serverID string) error {
	return fmt.Errorf("systemd nur auf linux verfügbar")
}

func (m *Manager) Restart(serverID string) error {
	return fmt.Errorf("systemd nur auf linux verfügbar")
}

func (m *Manager) Kill(serverID string) error {
	return fmt.Errorf("systemd nur auf linux verfügbar")
}

func (m *Manager) Status(serverID string) (string, error) {
	return "", fmt.Errorf("systemd nur auf linux verfügbar")
}

func (m *Manager) IsActive(serverID string) (bool, error) {
	return false, fmt.Errorf("systemd nur auf linux verfügbar")
}

func (m *Manager) Remove(serverID string) error {
	return fmt.Errorf("systemd nur auf linux verfügbar")
}
