package database

import (
	"context"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

type Options struct {
	Host     string
	Port     int
	Username string
	Password string
}

type Manager struct {
	opts Options
}

func NewManager(opts Options) *Manager {
	if opts.Host == "" {
		opts.Host = "127.0.0.1"
	}
	if opts.Port == 0 {
		opts.Port = 3306
	}
	return &Manager{opts: opts}
}

func (m *Manager) Create(ctx context.Context, name, username, password string) error {
	sql := fmt.Sprintf(
		"CREATE DATABASE IF NOT EXISTS `%s`; CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s'; GRANT ALL PRIVILEGES ON `%s`.* TO '%s'@'%%'; FLUSH PRIVILEGES;",
		escapeIdent(name), escapeIdent(username), escapeString(password), escapeIdent(name), escapeIdent(username),
	)
	return m.exec(ctx, sql)
}

func (m *Manager) Delete(ctx context.Context, name, username string) error {
	sql := fmt.Sprintf(
		"DROP DATABASE IF EXISTS `%s`; DROP USER IF EXISTS '%s'@'%%'; FLUSH PRIVILEGES;",
		escapeIdent(name), escapeIdent(username),
	)
	return m.exec(ctx, sql)
}

func (m *Manager) exec(ctx context.Context, sql string) error {
	bin := "mysql"
	if _, err := exec.LookPath("mysql"); err != nil {
		bin = "mariadb"
	}
	args := []string{"-N", "-e", sql}
	if m.opts.Username != "" {
		args = append([]string{
			"-h", m.opts.Host,
			"-P", strconv.Itoa(m.opts.Port),
			"-u", m.opts.Username,
			"-p" + m.opts.Password,
		}, args...)
	}
	cmd := exec.CommandContext(ctx, bin, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s: %w: %s", bin, err, strings.TrimSpace(string(out)))
	}
	return nil
}

func escapeIdent(s string) string {
	return strings.ReplaceAll(s, "`", "")
}

func escapeString(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `'`, `\'`)
	return s
}
