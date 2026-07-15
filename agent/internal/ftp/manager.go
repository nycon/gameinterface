package ftp

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Manager provisions OpenSSH SFTP-only chroot accounts for game servers.
type Manager struct {
	ConfigDir string
}

func NewManager() *Manager {
	return &Manager{ConfigDir: "/etc/ssh/gamepanel_sftp"}
}

func (m *Manager) Ensure(username, password, homePath string) error {
	if err := os.MkdirAll(m.ConfigDir, 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(homePath), 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(homePath, 0o750); err != nil {
		return err
	}

	if _, err := exec.Command("id", username).CombinedOutput(); err != nil {
		out, err := exec.Command("useradd", "-M", "-s", "/usr/sbin/nologin", "-d", homePath, username).CombinedOutput()
		if err != nil {
			return fmt.Errorf("useradd: %w: %s", err, string(out))
		}
	}

	cmd := exec.Command("chpasswd")
	cmd.Stdin = strings.NewReader(username + ":" + password + "\n")
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("chpasswd: %w: %s", err, string(out))
	}

	_ = exec.Command("chown", "-R", username+":"+username, homePath).Run()

	match := fmt.Sprintf("Match User %s\n  ForceCommand internal-sftp\n  ChrootDirectory %s\n  AllowTcpForwarding no\n  X11Forwarding no\n",
		username, filepath.Dir(homePath))
	path := filepath.Join(m.ConfigDir, username+".conf")
	if err := os.WriteFile(path, []byte(match), 0o644); err != nil {
		return err
	}

	include := "Include " + m.ConfigDir + "/*.conf\n"
	sshd := "/etc/ssh/sshd_config"
	data, _ := os.ReadFile(sshd)
	if !strings.Contains(string(data), m.ConfigDir) {
		f, err := os.OpenFile(sshd, os.O_APPEND|os.O_WRONLY, 0o644)
		if err == nil {
			_, _ = f.WriteString("\n" + include)
			_ = f.Close()
		}
	}

	_ = exec.Command("systemctl", "reload", "ssh").Run()
	_ = exec.Command("systemctl", "reload", "sshd").Run()
	return nil
}

func (m *Manager) Delete(username string) error {
	_ = os.Remove(filepath.Join(m.ConfigDir, username+".conf"))
	_ = exec.Command("userdel", "-f", username).Run()
	_ = exec.Command("systemctl", "reload", "ssh").Run()
	_ = exec.Command("systemctl", "reload", "sshd").Run()
	return nil
}
