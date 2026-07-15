package scripts

import (
	"github.com/gamepanel/agent/internal/config"
)

type Sandbox struct {
	cfg config.SandboxConfig
}

func NewSandbox(cfg config.SandboxConfig) *Sandbox {
	return &Sandbox{cfg: cfg}
}

func (s *Sandbox) Env(base []string) []string {
	env := make([]string, len(base))
	copy(env, base)

	if s.cfg.NoNewPrivileges {
		env = append(env, "GAMEPANEL_NO_NEW_PRIVILEGES=1")
	}
	if s.cfg.DropCapabilities {
		env = append(env, "GAMEPANEL_DROP_CAPS=1")
	}
	return env
}

func (s *Sandbox) ReadOnlyPaths() []string {
	return append([]string(nil), s.cfg.ReadOnlyPaths...)
}

func (s *Sandbox) NoNewPrivileges() bool {
	return s.cfg.NoNewPrivileges
}

func (s *Sandbox) DropCapabilities() bool {
	return s.cfg.DropCapabilities
}
