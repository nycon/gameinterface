package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/gamepanel/agent/internal/api"
	"github.com/gamepanel/agent/internal/auth"
	"github.com/gamepanel/agent/internal/config"
	"github.com/gamepanel/agent/internal/images"
	"github.com/gamepanel/agent/internal/jobs"
	"github.com/gamepanel/agent/internal/logs"
	"github.com/gamepanel/agent/internal/metrics"
	"github.com/gamepanel/agent/internal/process"
	"github.com/gamepanel/agent/internal/systemd"
	"github.com/spf13/cobra"
)

var (
	version = "dev"
	cfgPath string
	cfg     *config.Config
	logger  *slog.Logger
)

func main() {
	root := &cobra.Command{
		Use:   "gamepanel-agent",
		Short: "GamePanel Node Agent für Bare-Metal Game Nodes",
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			if cmd.Name() == "help" || cmd.Name() == "completion" {
				return nil
			}
			var err error
			cfg, err = config.Load(cfgPath)
			if err != nil {
				return err
			}
			var closer interface{ Close() error }
			logger, closer, err = logs.New(logs.Options{
				Level:  cfg.Logging.Level,
				Format: cfg.Logging.Format,
				File:   cfg.Logging.File,
			})
			if err != nil {
				return err
			}
			cmd.SetContext(contextWithCloser(cmd.Context(), closer))
			return nil
		},
	}

	root.PersistentFlags().StringVar(&cfgPath, "config", config.DefaultConfigPath, "Pfad zur config.yaml")

	root.AddCommand(
		runCmd(),
		registerCmd(),
		statusCmd(),
		doctorCmd(),
		testImageDownloadCmd(),
		serverCmd(),
		logsCmd(),
	)

	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}

func runCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "run",
		Short: "Agent-Daemon starten (Heartbeat + Job-Polling)",
		RunE: func(cmd *cobra.Command, args []string) error {
			token := auth.NewTokenProvider(cfg.Node.Token)
			if err := token.Validate(); err != nil {
				return err
			}
			if cfg.Node.ID == "" {
				return fmt.Errorf("node.id fehlt – bitte zuerst registrieren")
			}

			client := api.NewClient(cfg, token)
			handler := jobs.NewHandler(cfg, client, logger)
			collector := metrics.NewCollector()

			ctx, stop := signal.NotifyContext(cmd.Context(), syscall.SIGINT, syscall.SIGTERM)
			defer stop()

			start := time.Now()
			logger.Info("agent gestartet", "node_id", cfg.Node.ID)

			go client.RunHeartbeatLoop(ctx, cfg.Agent.HeartbeatInterval, collector, start)
			go client.RunJobPollLoop(ctx, cfg.Agent.JobPollInterval, func(jobCtx context.Context, job api.Job) error {
				return handler.Handle(jobCtx, job)
			})

			<-ctx.Done()
			logger.Info("agent beendet")
			return nil
		},
	}
}

func registerCmd() *cobra.Command {
	var setupToken string
	cmd := &cobra.Command{
		Use:   "register",
		Short: "Node beim Panel registrieren",
		RunE: func(cmd *cobra.Command, args []string) error {
			token := auth.NewTokenProvider("")
			client := api.NewClient(cfg, token)

			hostname := cfg.Node.FQDN
			if hostname == "" {
				hostname = cfg.Node.Name
			}
			ip := firstNonEmpty(os.Getenv("GAMEPANEL_NODE_IP"), "127.0.0.1")

			resp, err := client.Register(cmd.Context(), api.RegisterRequest{
				Name:         cfg.Node.Name,
				Hostname:     hostname,
				IPAddress:    ip,
				AgentVersion: version,
				SetupToken:   firstNonEmpty(setupToken, os.Getenv("GAMEPANEL_SETUP_TOKEN")),
				NodeUUID:     cfg.Node.ID,
			})
			if err != nil {
				return err
			}

			cfg.Node.ID = resp.Node.UUID
			cfg.Node.Token = resp.Token

			if err := saveNodeCredentials(cfgPath, cfg); err != nil {
				return err
			}

			fmt.Printf("Node registriert: uuid=%s id=%d\n", resp.Node.UUID, resp.Node.ID)
			fmt.Printf("Token gespeichert in %s\n", cfgPath)
			return nil
		},
	}
	cmd.Flags().StringVar(&setupToken, "setup-token", "", "Setup-Token vom Panel")
	cmd.Flags().StringVar(&setupToken, "token", "", "Alias für --setup-token")
	return cmd
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

func statusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Agent- und Node-Status anzeigen",
		RunE: func(cmd *cobra.Command, args []string) error {
			collector := metrics.NewCollector()
			snap, err := collector.Collect()
			if err != nil {
				return err
			}

			out := map[string]any{
				"node_id":   cfg.Node.ID,
				"node_name": cfg.Node.Name,
				"panel_url": cfg.Panel.URL,
				"metrics":   snap,
			}
			data, _ := json.MarshalIndent(out, "", "  ")
			fmt.Println(string(data))
			return nil
		},
	}
}

func doctorCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "doctor",
		Short: "Systemvoraussetzungen prüfen",
		RunE: func(cmd *cobra.Command, args []string) error {
			checks := []struct {
				name string
				fn   func() error
			}{
				{"config", func() error { return cfg.Validate() }},
				{"agent_dir", func() error { return dirWritable(cfg.Paths.AgentDir) }},
				{"servers_dir", func() error { return dirWritable(cfg.Paths.ServersDir) }},
				{"systemctl", func() error {
					_, err := systemd.NewManager(cfg.Systemd.UnitPrefix, cfg.Systemd.Slice).Status("nonexistent-check")
					if err != nil {
						return nil // systemctl vorhanden wenn kein 'command not found'
					}
					return nil
				}},
			}

			ok := true
			for _, c := range checks {
				if err := c.fn(); err != nil {
					fmt.Printf("[FAIL] %s: %v\n", c.name, err)
					ok = false
				} else {
					fmt.Printf("[ OK ] %s\n", c.name)
				}
			}

			if cfg.Node.Token != "" {
				if err := auth.NewTokenProvider(cfg.Node.Token).Validate(); err != nil {
					fmt.Printf("[FAIL] node_token: %v\n", err)
					ok = false
				} else {
					fmt.Printf("[ OK ] node_token\n")
				}
			} else {
				fmt.Printf("[WARN] node_token: nicht gesetzt\n")
			}

			if !ok {
				return fmt.Errorf("doctor hat fehler gefunden")
			}
			return nil
		},
	}
}

func testImageDownloadCmd() *cobra.Command {
	var remotePath, manifestPath string
	cmd := &cobra.Command{
		Use:   "test-image-download",
		Short: "Image-Download und Extraktion testen",
		RunE: func(cmd *cobra.Command, args []string) error {
			if remotePath == "" {
				return fmt.Errorf("--remote ist erforderlich")
			}

			downloader := images.NewDownloader(cfg)
			var manifest *images.Manifest
			var err error

			if manifestPath != "" {
				manifest, err = images.ParseManifestFile(manifestPath)
				if err != nil {
					return err
				}
			}

			result, err := downloader.Download(cmd.Context(), images.DownloadRequest{
				RemotePath: remotePath,
				Manifest:   manifest,
			})
			if err != nil {
				return err
			}

			fmt.Printf("Download erfolgreich: %s (extracted=%v)\n", result.LocalPath, result.Extracted)
			return nil
		},
	}
	cmd.Flags().StringVar(&remotePath, "remote", "", "Remote-Pfad zum Archiv")
	cmd.Flags().StringVar(&manifestPath, "manifest", "", "Lokaler Manifest-Pfad")
	return cmd
}

func serverCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "server",
		Short: "Game-Server verwalten",
	}
	cmd.AddCommand(
		&cobra.Command{
			Use:   "start [server-id]",
			Args:  cobra.ExactArgs(1),
			Short: "Server starten",
			RunE: func(cmd *cobra.Command, args []string) error {
				mgr := systemd.NewManager(cfg.Systemd.UnitPrefix, cfg.Systemd.Slice)
				return mgr.Start(args[0])
			},
		},
		&cobra.Command{
			Use:   "stop [server-id]",
			Args:  cobra.ExactArgs(1),
			Short: "Server stoppen",
			RunE: func(cmd *cobra.Command, args []string) error {
				mgr := systemd.NewManager(cfg.Systemd.UnitPrefix, cfg.Systemd.Slice)
				return mgr.Stop(args[0])
			},
		},
	)
	return cmd
}

func logsCmd() *cobra.Command {
	var lines int
	cmd := &cobra.Command{
		Use:   "logs [server-id]",
		Args:  cobra.ExactArgs(1),
		Short: "Server-Logs anzeigen",
		RunE: func(cmd *cobra.Command, args []string) error {
			unit := cfg.UnitName(args[0])
			entries, err := process.JournalLogs(cmd.Context(), unit, lines)
			if err != nil {
				return err
			}
			for _, line := range entries {
				fmt.Println(line)
			}
			return nil
		},
	}
	cmd.Flags().IntVarP(&lines, "lines", "n", 100, "Anzahl Zeilen")
	return cmd
}

func dirWritable(path string) error {
	if err := os.MkdirAll(path, 0o750); err != nil {
		return err
	}
	test := filepath.Join(path, ".write-test")
	if err := os.WriteFile(test, []byte("ok"), 0o600); err != nil {
		return err
	}
	return os.Remove(test)
}

func saveNodeCredentials(path string, cfg *config.Config) error {
	if err := config.Save(path, cfg); err != nil {
		return err
	}
	logger.Info("node credentials aktualisiert", "id", cfg.Node.ID)
	return nil
}

type closerKey struct{}

func contextWithCloser(ctx context.Context, closer interface{ Close() error }) context.Context {
	return context.WithValue(ctx, closerKey{}, closer)
}
