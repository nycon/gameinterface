package process

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"io"
	"os/exec"
	"sync"
)

type Console struct {
	mu       sync.Mutex
	lines    []string
	maxLines int
}

func NewConsole(maxLines int) *Console {
	if maxLines <= 0 {
		maxLines = 1000
	}
	return &Console{maxLines: maxLines}
}

func (c *Console) Append(line string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.lines = append(c.lines, line)
	if len(c.lines) > c.maxLines {
		c.lines = c.lines[len(c.lines)-c.maxLines:]
	}
}

func (c *Console) Lines() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make([]string, len(c.lines))
	copy(out, c.lines)
	return out
}

func (c *Console) Tail(n int) []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	if n <= 0 || n >= len(c.lines) {
		out := make([]string, len(c.lines))
		copy(out, c.lines)
		return out
	}
	out := make([]string, n)
	copy(out, c.lines[len(c.lines)-n:])
	return out
}

func StreamCommand(ctx context.Context, name string, args ...string) error {
	cmd := exec.CommandContext(ctx, name, args...)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("stdout pipe: %w", err)
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return fmt.Errorf("stderr pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("prozess starten: %w", err)
	}

	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); scanLines(stdout, nil) }()
	go func() { defer wg.Done(); scanLines(stderr, nil) }()
	wg.Wait()

	if err := cmd.Wait(); err != nil {
		return fmt.Errorf("prozess beendet: %w", err)
	}
	return nil
}

func scanLines(r io.Reader, handler func(string)) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		if handler != nil {
			handler(line)
		}
	}
}

func JournalLogs(ctx context.Context, unit string, lines int) ([]string, error) {
	args := []string{"-u", unit, "--no-pager", "-n", fmt.Sprintf("%d", lines)}
	cmd := exec.CommandContext(ctx, "journalctl", args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("journalctl: %w: %s", err, string(out))
	}

	var result []string
	scanner := bufio.NewScanner(bytes.NewReader(out))
	for scanner.Scan() {
		result = append(result, scanner.Text())
	}
	return result, scanner.Err()
}
