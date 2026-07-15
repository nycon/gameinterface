//go:build linux

package systemd

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"text/template"
)

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
	unitDir    string
}

func NewManager(unitPrefix, slice string) *Manager {
	return &Manager{
		unitPrefix: unitPrefix,
		slice:      slice,
		unitDir:    "/etc/systemd/system",
	}
}

func (m *Manager) UnitName(serverID string) string {
	// systemd erlaubt Bindestriche; Dateiname sanitizen
	safe := strings.ReplaceAll(serverID, "/", "-")
	return fmt.Sprintf("%s-%s.service", m.unitPrefix, safe)
}

func (m *Manager) Install(spec ServerSpec) error {
	content, err := m.renderUnit(spec)
	if err != nil {
		return err
	}

	path := filepath.Join(m.unitDir, m.UnitName(spec.ServerID))
	if err := os.WriteFile(path, content, 0o644); err != nil {
		return fmt.Errorf("unit schreiben: %w", err)
	}

	return m.run("daemon-reload")
}

func (m *Manager) Start(serverID string) error {
	return m.run("start", m.UnitName(serverID))
}

func (m *Manager) Stop(serverID string) error {
	return m.run("stop", m.UnitName(serverID))
}

func (m *Manager) Restart(serverID string) error {
	return m.run("restart", m.UnitName(serverID))
}

func (m *Manager) Kill(serverID string) error {
	return m.run("kill", "-s", "SIGKILL", m.UnitName(serverID))
}

func (m *Manager) Status(serverID string) (string, error) {
	out, err := exec.Command("systemctl", "status", m.UnitName(serverID)).CombinedOutput()
	return string(out), err
}

func (m *Manager) IsActive(serverID string) (bool, error) {
	err := exec.Command("systemctl", "is-active", "--quiet", m.UnitName(serverID)).Run()
	if err == nil {
		return true, nil
	}
	if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 3 {
		return false, nil
	}
	return false, err
}

func (m *Manager) Remove(serverID string) error {
	_ = m.Stop(serverID)
	path := filepath.Join(m.unitDir, m.UnitName(serverID))
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("unit entfernen: %w", err)
	}
	return m.run("daemon-reload")
}

func (m *Manager) run(args ...string) error {
	cmd := exec.Command("systemctl", args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("systemctl %s: %w: %s", strings.Join(args, " "), err, string(out))
	}
	return nil
}

func (m *Manager) renderUnit(spec ServerSpec) ([]byte, error) {
	tmpl := template.Must(template.New("unit").Funcs(template.FuncMap{
		"mul": func(a, b int) int { return a * b },
	}).Parse(unitTemplate))

	data := struct {
		ServerSpec
		UnitName  string
		Slice     string
		ExecStart string
		EnvLines  []string
	}{
		ServerSpec: spec,
		UnitName:   m.UnitName(spec.ServerID),
		Slice:      m.slice,
		ExecStart:  buildExecStart(spec.Executable, spec.Args),
	}

	for k, v := range spec.Environment {
		data.EnvLines = append(data.EnvLines, fmt.Sprintf(`Environment="%s=%s"`, k, escapeSystemdValue(v)))
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func buildExecStart(executable string, args []string) string {
	parts := append([]string{executable}, args...)
	for i, p := range parts {
		parts[i] = quoteSystemdArg(p)
	}
	return strings.Join(parts, " ")
}

func quoteSystemdArg(s string) string {
	if s == "" {
		return `""`
	}
	if !strings.ContainsAny(s, " \t\n\"\\") {
		return s
	}
	return `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(s) + `"`
}

func escapeSystemdValue(s string) string {
	return strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(s)
}

const unitTemplate = `[Unit]
Description=GamePanel Server {{ .ServerID }}
After=network-online.target
Wants=network-online.target
PartOf={{ .Slice }}

[Service]
Type=simple
User={{ .Username }}
Group={{ .Username }}
WorkingDirectory={{ .WorkingDir }}
ExecStart={{ .ExecStart }}
{{ range .EnvLines }}{{ . }}
{{ end }}Restart=on-failure
RestartSec=5
KillMode=mixed
TimeoutStopSec=30

# Hardening (Java/Games brauchen Schreibzugriff + JIT)
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths={{ .WorkingDir }}
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
MemoryDenyWriteExecute=false
SystemCallArchitectures=native
UMask=0027

# Resource limits
{{- if .MemoryMax }}
MemoryMax={{ .MemoryMax }}
{{- end }}
{{- if gt .CPUPercent 0 }}
CPUQuota={{ mul .CPUPercent 100 }}%
{{- end }}

Slice={{ .Slice }}

[Install]
WantedBy=multi-user.target
`
