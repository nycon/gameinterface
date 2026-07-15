package api

import (
	"context"
	"strings"
	"sync"
	"time"
)

// isInteractiveJob — schnelle UI-Ops, parallel zu Heavy-Jobs (Install/Backup).
func isInteractiveJob(jobType string) bool {
	t := strings.TrimPrefix(strings.ToLower(strings.TrimSpace(jobType)), "server.")
	switch {
	case strings.HasPrefix(t, "files."):
		return true
	case strings.HasPrefix(t, "console."):
		return true
	case t == "diagnostics":
		return true
	case strings.HasPrefix(t, "ftp."):
		return true
	case strings.HasPrefix(t, "database."):
		return true
	default:
		return false
	}
}

// RunJobPollLoop pollt adaptiv (schnell bei Last, max ~2s idle) und führt
// File/Console-Jobs parallel aus, damit sie nicht hinter Install/Backup warten.
func (c *Client) RunJobPollLoop(ctx context.Context, interval time.Duration, handler func(context.Context, Job) error) {
	minBusy := 300 * time.Millisecond
	maxIdle := interval
	if maxIdle <= 0 || maxIdle > 2*time.Second {
		maxIdle = 2 * time.Second
	}
	if maxIdle < minBusy {
		maxIdle = minBusy
	}

	delay := minBusy
	var heavyMu sync.Mutex

	run := func(job Job) {
		if err := handler(ctx, job); err != nil {
			_ = c.FailJob(ctx, job.UUID, err.Error())
		}
	}

	for {
		if ctx.Err() != nil {
			return
		}

		jobs, err := c.PollJobs(ctx)
		if err != nil {
			select {
			case <-ctx.Done():
				return
			case <-time.After(delay):
			}
			if delay < maxIdle {
				delay *= 2
				if delay > maxIdle {
					delay = maxIdle
				}
			}
			continue
		}

		if len(jobs) == 0 {
			if delay < maxIdle {
				next := delay * 2
				if next > maxIdle {
					next = maxIdle
				}
				delay = next
			}
			select {
			case <-ctx.Done():
				return
			case <-time.After(delay):
			}
			continue
		}

		delay = minBusy
		for _, job := range jobs {
			job := job
			if isInteractiveJob(job.Type) {
				go run(job)
				continue
			}
			go func(job Job) {
				heavyMu.Lock()
				defer heavyMu.Unlock()
				run(job)
			}(job)
		}

		select {
		case <-ctx.Done():
			return
		case <-time.After(minBusy):
		}
	}
}
