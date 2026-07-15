package ftp

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Manager provisions OpenSSH SFTP-only chroot accounts for game servers.
//
// OpenSSH verlangt: ChrootDirectory + alle Parents root-owned und nicht
// group/world-writable. Das writable Home liegt als Unterverzeichnis im Jail.
// Dateien bleiben dem Game-User gehören; der SFTP-User wird in dieselbe Gruppe aufgenommen.
type Manager struct {
	ConfigDir string
}

func NewManager() *Manager {
	return &Manager{ConfigDir: "/etc/ssh/sshd_config.d"}
}

func (m *Manager) snippetPath(username string) string {
	return filepath.Join(m.ConfigDir, "zz-gamepanel-sftp-"+sanitize(username)+".conf")
}

func sanitize(s string) string {
	s = strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' {
			return r
		}
		return '-'
	}, s)
	if s == "" {
		return "user"
	}
	return s
}

func (m *Manager) Ensure(username, password, homePath, gameUser string) error {
	homePath = filepath.Clean(homePath)
	if homePath == "" || homePath == "/" {
		return fmt.Errorf("home_path ungültig")
	}

	// Chroot = Parent des Homes. Beispiel:
	//   home=/srv/gamepanel/servers/server-42
	//   chroot=/srv/gamepanel/servers  (root:root 755)
	chroot := filepath.Dir(homePath)
	if chroot == "" || chroot == "/" || chroot == "." {
		return fmt.Errorf("chroot aus home_path ungültig: %s", homePath)
	}

	if err := os.MkdirAll(homePath, 0o750); err != nil {
		return fmt.Errorf("home anlegen: %w", err)
	}
	if err := hardenChrootPath(chroot); err != nil {
		return fmt.Errorf("chroot härten: %w", err)
	}

	owner := gameUser
	if owner == "" {
		owner = username
	}

	if _, err := exec.Command("id", username).CombinedOutput(); err != nil {
		args := []string{"-M", "-s", "/usr/sbin/nologin", "-d", homePath}
		// gleiche Gruppe wie Game-User → Zugriff ohne Owner-Diebstahl
		if gameUser != "" && gameUser != username {
			if out, err := exec.Command("id", "-gn", gameUser).CombinedOutput(); err == nil {
				grp := strings.TrimSpace(string(out))
				if grp != "" {
					args = append(args, "-g", grp)
				}
			}
		}
		args = append(args, username)
		out, err := exec.Command("useradd", args...).CombinedOutput()
		if err != nil {
			return fmt.Errorf("useradd: %w: %s", err, strings.TrimSpace(string(out)))
		}
	} else {
		_ = exec.Command("usermod", "-d", homePath, "-s", "/usr/sbin/nologin", username).Run()
		if gameUser != "" && gameUser != username {
			_ = exec.Command("usermod", "-aG", gameUser, username).Run()
			if out, err := exec.Command("id", "-gn", gameUser).CombinedOutput(); err == nil {
				grp := strings.TrimSpace(string(out))
				if grp != "" {
					_ = exec.Command("usermod", "-g", grp, username).Run()
				}
			}
		}
	}

	cmd := exec.Command("chpasswd")
	cmd.Stdin = strings.NewReader(username + ":" + password + "\n")
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("chpasswd: %w: %s", err, strings.TrimSpace(string(out)))
	}

	// Game-User bleibt Owner — SFTP über Gruppenrechte
	_ = exec.Command("chown", "-R", owner+":"+owner, homePath).Run()
	_ = os.Chmod(homePath, 0o2770) // setgid: neue Dateien erben Gruppe
	_ = exec.Command("chmod", "-R", "g+rwX", homePath).Run()

	if err := os.MkdirAll(m.ConfigDir, 0o755); err != nil {
		return err
	}
	match := fmt.Sprintf(`# GamePanel SFTP account (auto)
Match User %s
    ChrootDirectory %s
    ForceCommand internal-sftp
    PasswordAuthentication yes
    PubkeyAuthentication no
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
    AllowAgentForwarding no
`, username, chroot)

	path := m.snippetPath(username)
	if err := os.WriteFile(path, []byte(match), 0o644); err != nil {
		return fmt.Errorf("sshd snippet: %w", err)
	}

	_ = os.Remove(filepath.Join("/etc/ssh/gamepanel_sftp", username+".conf"))
	cleanupLegacySshdInclude()

	if err := validateAndReloadSSHD(); err != nil {
		_ = os.Remove(path)
		return err
	}
	return nil
}

func (m *Manager) Delete(username string) error {
	_ = os.Remove(m.snippetPath(username))
	_ = os.Remove(filepath.Join("/etc/ssh/gamepanel_sftp", username+".conf"))
	_ = exec.Command("userdel", "-f", username).Run()
	cleanupLegacySshdInclude()
	_ = validateAndReloadSSHD()
	return nil
}

func cleanupLegacySshdInclude() {
	const marker = "/etc/ssh/gamepanel_sftp"
	sshd := "/etc/ssh/sshd_config"
	data, err := os.ReadFile(sshd)
	if err != nil {
		return
	}
	lines := strings.Split(string(data), "\n")
	var out []string
	changed := false
	for _, line := range lines {
		trim := strings.TrimSpace(line)
		if strings.HasPrefix(trim, "Include ") && strings.Contains(trim, marker) {
			changed = true
			continue
		}
		out = append(out, line)
	}
	if changed {
		_ = os.WriteFile(sshd, []byte(strings.Join(out, "\n")), 0o644)
	}
}

func hardenChrootPath(path string) error {
	path = filepath.Clean(path)
	if path == "/" {
		return fmt.Errorf("chroot darf nicht / sein")
	}

	cur := ""
	for _, part := range strings.Split(strings.TrimPrefix(path, "/"), "/") {
		if part == "" {
			continue
		}
		cur += "/" + part
		if err := os.MkdirAll(cur, 0o755); err != nil {
			return err
		}
		if err := os.Chown(cur, 0, 0); err != nil {
			return fmt.Errorf("chown root %s: %w", cur, err)
		}
		if err := os.Chmod(cur, 0o755); err != nil {
			return fmt.Errorf("chmod %s: %w", cur, err)
		}
	}
	return nil
}

func validateAndReloadSSHD() error {
	out, err := exec.Command("/usr/sbin/sshd", "-t").CombinedOutput()
	if err != nil {
		return fmt.Errorf("sshd -t ungültig: %w: %s", err, strings.TrimSpace(string(out)))
	}
	_ = exec.Command("systemctl", "reload", "ssh").Run()
	_ = exec.Command("systemctl", "reload", "sshd").Run()
	return nil
}
