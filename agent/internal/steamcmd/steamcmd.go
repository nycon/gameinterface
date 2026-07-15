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

type Options struct {
	InstallDir string
	Timeout    time.Duration
}

type Runner struct {
	installDir string
	timeout    time.Duration
}

func New(opts Options) *Runner {
	if opts.Timeout <= 0 {
		opts.Timeout = 30 * time.Minute
	}
	return &Runner{
		installDir: opts.InstallDir,
		timeout:    opts.Timeout,
	}
}

func (r *Runner) Binary() string {
	return filepath.Join(r.installDir, "steamcmd.sh")
}

func (r *Runner) EnsureInstalled(ctx context.Context) error {
	if _, err := os.Stat(r.Binary()); err == nil {
		return nil
	}

	if err := os.MkdirAll(r.installDir, 0o755); err != nil {
		return fmt.Errorf("steamcmd verzeichnis: %w", err)
	}

	// Minimaler Bootstrap – in Produktion wird steamcmd.sh vom Panel/Image bereitgestellt.
	return fmt.Errorf("steamcmd nicht installiert unter %s", r.Binary())
}

type InstallRequest struct {
	AppID       string
	InstallDir  string
	Validate    bool
	ExtraArgs   []string
}

func (r *Runner) Install(ctx context.Context, req InstallRequest) (string, error) {
	if err := r.EnsureInstalled(ctx); err != nil {
		return "", err
	}

	args := []string{
		"+force_install_dir", req.InstallDir,
		"+login", "anonymous",
		"+app_update", req.AppID,
	}
	if req.Validate {
		args = append(args, "validate")
	}
	args = append(args, "+quit")
	args = append(args, req.ExtraArgs...)

	runCtx, cancel := context.WithTimeout(ctx, r.timeout)
	defer cancel()

	cmd := exec.CommandContext(runCtx, r.Binary(), args...)
	cmd.Dir = r.installDir
	cmd.Env = append(os.Environ(), "HOME="+r.installDir)

	out, err := cmd.CombinedOutput()
	output := strings.TrimSpace(string(out))
	if err != nil {
		return output, fmt.Errorf("steamcmd: %w", err)
	}
	return output, nil
}

func (r *Runner) RunScript(ctx context.Context, scriptPath string) (string, error) {
	if err := r.EnsureInstalled(ctx); err != nil {
		return "", err
	}

	runCtx, cancel := context.WithTimeout(ctx, r.timeout)
	defer cancel()

	cmd := exec.CommandContext(runCtx, r.Binary(), "+runscript", scriptPath)
	cmd.Dir = r.installDir
	out, err := cmd.CombinedOutput()
	output := strings.TrimSpace(string(out))
	if err != nil {
		return output, fmt.Errorf("steamcmd script: %w", err)
	}
	return output, nil
}
