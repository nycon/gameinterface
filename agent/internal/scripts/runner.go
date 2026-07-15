package scripts

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/gamepanel/agent/internal/config"
)

type Runner struct {
	cfg     config.ScriptsConfig
	sandbox *Sandbox
}

func NewRunner(cfg config.ScriptsConfig) *Runner {
	return &Runner{
		cfg:     cfg,
		sandbox: NewSandbox(cfg.Sandbox),
	}
}

type RunRequest struct {
	Interpreter string
	ScriptPath  string
	Args        []string
	Params      map[string]string
	WorkDir     string
	AllowedDirs []string
}

type RunResult struct {
	ExitCode int
	Stdout   string
	Stderr   string
	Duration time.Duration
}

func (r *Runner) Run(ctx context.Context, req RunRequest) (*RunResult, error) {
	if err := ValidateParameters(req.Params); err != nil {
		return nil, err
	}
	if err := ValidateScriptPath(req.ScriptPath, req.AllowedDirs); err != nil {
		return nil, err
	}

	interpreter := req.Interpreter
	if interpreter == "" {
		interpreter = "/bin/bash"
	}
	if err := ValidateInterpreter(interpreter, r.cfg.AllowedInterpreters); err != nil {
		return nil, err
	}

	timeout := r.cfg.Timeout
	if timeout <= 0 {
		timeout = 5 * time.Minute
	}
	runCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	args := append([]string{req.ScriptPath}, req.Args...)
	cmd := exec.CommandContext(runCtx, interpreter, args...)
	cmd.Dir = req.WorkDir
	if cmd.Dir == "" {
		cmd.Dir = filepath.Dir(req.ScriptPath)
	}

	env := r.sandbox.Env(os.Environ())
	for k, v := range req.Params {
		env = append(env, fmt.Sprintf("GP_PARAM_%s=%s", k, v))
	}
	cmd.Env = env

	if r.sandbox.NoNewPrivileges() {
		// Linux: NoNewPrivileges wird über systemd/prctl gesetzt; hier als Dokumentation.
		cmd.Env = append(cmd.Env, "PRCTL_NO_NEW_PRIVS=1")
	}

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	start := time.Now()
	err := cmd.Run()
	duration := time.Since(start)

	result := &RunResult{
		Stdout:   stdout.String(),
		Stderr:   stderr.String(),
		Duration: duration,
	}

	if err == nil {
		result.ExitCode = 0
		return result, nil
	}

	if exitErr, ok := err.(*exec.ExitError); ok {
		result.ExitCode = exitErr.ExitCode()
		return result, fmt.Errorf("script exit %d", result.ExitCode)
	}
	if runCtx.Err() == context.DeadlineExceeded {
		return result, fmt.Errorf("script timeout nach %s", timeout)
	}
	return result, err
}
