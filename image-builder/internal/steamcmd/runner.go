package steamcmd

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const defaultSteamCMD = "/usr/games/steamcmd"

// Config enthält SteamCMD-Laufzeitparameter.
type Config struct {
	BinaryPath string
	InstallDir string
	AppID      string
	Validate   bool
	ExtraArgs  []string
	Timeout    time.Duration
}

// Runner führt SteamCMD-Befehle aus.
type Runner struct {
	binaryPath string
}

// NewRunner erstellt einen SteamCMD-Runner.
func NewRunner() *Runner {
	path := os.Getenv("STEAMCMD_PATH")
	if path == "" {
		path = defaultSteamCMD
	}
	return &Runner{binaryPath: path}
}

// Update führt ein SteamCMD-App-Update aus.
func (r *Runner) Update(ctx context.Context, cfg Config) error {
	if cfg.BinaryPath != "" {
		r.binaryPath = cfg.BinaryPath
	}
	if cfg.InstallDir == "" {
		return fmt.Errorf("install_dir ist erforderlich")
	}
	if cfg.AppID == "" {
		return fmt.Errorf("app_id ist erforderlich")
	}
	if cfg.Timeout == 0 {
		cfg.Timeout = 2 * time.Hour
	}

	if err := os.MkdirAll(cfg.InstallDir, 0o755); err != nil {
		return fmt.Errorf("install_dir anlegen: %w", err)
	}

	ctx, cancel := context.WithTimeout(ctx, cfg.Timeout)
	defer cancel()

	args := []string{
		"+force_install_dir", cfg.InstallDir,
		"+login", "anonymous",
		"+app_update", cfg.AppID,
	}
	if cfg.Validate {
		args = append(args, "validate")
	}
	args = append(args, "+quit")
	args = append(args, cfg.ExtraArgs...)

	cmd := exec.CommandContext(ctx, r.binaryPath, args...)
	cmd.Dir = filepath.Dir(r.binaryPath)
	cmd.Env = append(os.Environ(),
		"HOME="+cfg.InstallDir,
		"STEAMCMD=/usr/games/steamcmd.sh",
	)

	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("steamcmd fehlgeschlagen: %w\n%s", err, truncateOutput(out))
	}
	return nil
}

// InstallDirFor erzeugt den Standard-Build-Pfad für ein Template.
func InstallDirFor(root, slug string) string {
	return filepath.Join(root, "build", slug, "serverfiles")
}

func truncateOutput(out []byte) string {
	const maxLen = 4096
	s := string(out)
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "\n... (gekürzt)"
}

// ResolveScriptPath findet ein Update-Skript relativ zum Projektroot.
func ResolveScriptPath(projectRoot, script string) (string, error) {
	if filepath.IsAbs(script) {
		if _, err := os.Stat(script); err != nil {
			return "", err
		}
		return script, nil
	}

	candidates := []string{
		filepath.Join(projectRoot, script),
		filepath.Join(projectRoot, "scripts", "modern", script),
		filepath.Join(projectRoot, "scripts", script),
	}
	for _, candidate := range candidates {
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		}
	}
	return "", fmt.Errorf("skript nicht gefunden: %s", script)
}

// RunScript führt ein Shell-Skript mit Umgebungsvariablen aus.
func RunScript(ctx context.Context, scriptPath string, env map[string]string, args ...string) error {
	cmdArgs := append([]string{scriptPath}, args...)
	cmd := exec.CommandContext(ctx, "/bin/bash", cmdArgs...)
	cmd.Env = os.Environ()
	for k, v := range env {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
	}

	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("skript %s fehlgeschlagen: %w\n%s", filepath.Base(scriptPath), err, truncateOutput(out))
	}
	return nil
}

// IsSteamTemplate prüft, ob ein Template-Typ SteamCMD nutzt.
func IsSteamTemplate(templateType, strategy string) bool {
	return templateType == "steam" || strings.EqualFold(strategy, "steamcmd")
}
