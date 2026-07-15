package logs

import (
	"fmt"
	"io"
	"log/slog"
	"os"
	"strings"
)

type Options struct {
	Level  string
	Format string
	File   string
}

func New(opts Options) (*slog.Logger, io.Closer, error) {
	level := parseLevel(opts.Level)

	var writers []io.Writer
	writers = append(writers, os.Stdout)

	var closer io.Closer = noopCloser{}
	if opts.File != "" {
		f, err := os.OpenFile(opts.File, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o640)
		if err != nil {
			return nil, nil, fmt.Errorf("log-datei öffnen: %w", err)
		}
		writers = append(writers, f)
		closer = f
	}

	w := io.MultiWriter(writers...)
	handlerOpts := &slog.HandlerOptions{Level: level}

	var handler slog.Handler
	switch strings.ToLower(opts.Format) {
	case "text":
		handler = slog.NewTextHandler(w, handlerOpts)
	default:
		handler = slog.NewJSONHandler(w, handlerOpts)
	}

	return slog.New(handler), closer, nil
}

func parseLevel(level string) slog.Level {
	switch strings.ToLower(level) {
	case "debug":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

type noopCloser struct{}

func (noopCloser) Close() error { return nil }
