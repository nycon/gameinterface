//go:build !linux

package firewall

import "fmt"

type Allocation struct {
	ServerID string
	Protocol string
	Port     int
	IP       string
}

type Manager struct{}

func NewManager(backend, table, chain string) *Manager {
	return &Manager{}
}

func (m *Manager) EnsureBase() error {
	return fmt.Errorf("firewall nur auf linux verfügbar")
}

func (m *Manager) Allow(alloc Allocation) error {
	return fmt.Errorf("firewall nur auf linux verfügbar")
}

func (m *Manager) Deny(alloc Allocation) error {
	return fmt.Errorf("firewall nur auf linux verfügbar")
}
