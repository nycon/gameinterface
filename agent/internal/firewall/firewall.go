//go:build linux

package firewall

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

type Allocation struct {
	ServerID  string
	Protocol  string // tcp | udp
	Port      int
	IP        string
}

type Manager struct {
	backend string
	table   string
	chain   string
}

func NewManager(backend, table, chain string) *Manager {
	return &Manager{backend: backend, table: table, chain: chain}
}

func (m *Manager) EnsureBase() error {
	switch m.backend {
	case "nftables":
		return m.ensureNftablesBase()
	case "iptables":
		return m.ensureIPTablesBase()
	default:
		return fmt.Errorf("unbekanntes firewall-backend: %s", m.backend)
	}
}

func (m *Manager) Allow(alloc Allocation) error {
	if err := m.EnsureBase(); err != nil {
		return err
	}

	proto := strings.ToLower(alloc.Protocol)
	if proto == "" {
		proto = "tcp"
	}
	ip := alloc.IP
	if ip == "" {
		ip = "0.0.0.0/0"
	}

	switch m.backend {
	case "nftables":
		rule := fmt.Sprintf("add rule inet %s %s %s dport %d ip saddr %s accept comment \"gp-%s\"",
			m.table, m.chain, proto, alloc.Port, ip, alloc.ServerID)
		return m.runNft(rule)
	case "iptables":
		args := []string{"-A", m.chain, "-p", proto, "--dport", strconv.Itoa(alloc.Port), "-s", ip, "-j", "ACCEPT", "-m", "comment", "--comment", "gp-" + alloc.ServerID}
		return m.runIPTables(args...)
	default:
		return fmt.Errorf("unbekanntes backend")
	}
}

func (m *Manager) Deny(alloc Allocation) error {
	switch m.backend {
	case "nftables":
		handle, err := m.findNftComment("gp-" + alloc.ServerID)
		if err != nil {
			return err
		}
		if handle == "" {
			return nil
		}
		return m.runNft(fmt.Sprintf("delete rule inet %s %s handle %s", m.table, m.chain, handle))
	case "iptables":
		return m.runIPTables("-D", m.chain, "-m", "comment", "--comment", "gp-"+alloc.ServerID, "-j", "ACCEPT")
	default:
		return fmt.Errorf("unbekanntes backend")
	}
}

func (m *Manager) ensureNftablesBase() error {
	commands := []string{
		fmt.Sprintf("add table inet %s", m.table),
		fmt.Sprintf("add chain inet %s %s { type filter hook input priority 0; policy accept; }", m.table, m.chain),
	}
	for _, cmd := range commands {
		if err := m.runNft(cmd); err != nil && !strings.Contains(err.Error(), "exists") {
			return err
		}
	}
	return nil
}

func (m *Manager) ensureIPTablesBase() error {
	if err := m.runIPTables("-N", m.chain); err != nil && !strings.Contains(err.Error(), "exists") {
		return err
	}
	return nil
}

func (m *Manager) runNft(args string) error {
	cmd := exec.Command("nft", strings.Fields(args)...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("nft: %w: %s", err, string(out))
	}
	return nil
}

func (m *Manager) runIPTables(args ...string) error {
	cmd := exec.Command("iptables", args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("iptables: %w: %s", err, string(out))
	}
	return nil
}

func (m *Manager) findNftComment(comment string) (string, error) {
	cmd := exec.Command("nft", "-a", "list", "chain", "inet", m.table, m.chain)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", err
	}
	for _, line := range strings.Split(string(out), "\n") {
		if strings.Contains(line, comment) {
			fields := strings.Fields(line)
			for i, f := range fields {
				if f == "handle" && i+1 < len(fields) {
					return fields[i+1], nil
				}
			}
		}
	}
	return "", nil
}
