package config

import (
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

const DefaultConfigPath = "/opt/gamepanel/agent/config.yaml"

type Config struct {
	Panel    PanelConfig    `yaml:"panel"`
	Node     NodeConfig     `yaml:"node"`
	Paths    PathsConfig    `yaml:"paths"`
	Agent    AgentConfig    `yaml:"agent"`
	Systemd  SystemdConfig  `yaml:"systemd"`
	Firewall FirewallConfig `yaml:"firewall"`
	Database DatabaseConfig `yaml:"database"`
	SFTP     SFTPConfig     `yaml:"sftp"`
	FTP      FTPConfig      `yaml:"ftp"`
	Logging  LoggingConfig  `yaml:"logging"`
	Scripts  ScriptsConfig  `yaml:"scripts"`
}

type PanelConfig struct {
	URL         string        `yaml:"url"`
	Timeout     time.Duration `yaml:"timeout"`
	TLSInsecure bool          `yaml:"tls_insecure"`
}

type NodeConfig struct {
	ID    string `yaml:"id"`
	Token string `yaml:"token"`
	Name  string `yaml:"name"`
	FQDN  string `yaml:"fqdn"`
}

type PathsConfig struct {
	AgentDir   string `yaml:"agent_dir"`
	ServersDir string `yaml:"servers_dir"`
	ImagesDir  string `yaml:"images_dir"`
	BackupsDir string `yaml:"backups_dir"`
	SteamCMDDir string `yaml:"steamcmd_dir"`
	LogsDir    string `yaml:"logs_dir"`
}

type AgentConfig struct {
	HeartbeatInterval time.Duration `yaml:"heartbeat_interval"`
	JobPollInterval   time.Duration `yaml:"job_poll_interval"`
	DataDir           string        `yaml:"data_dir"`
}

type SystemdConfig struct {
	UnitPrefix string `yaml:"unit_prefix"`
	Slice      string `yaml:"slice"`
}

type FirewallConfig struct {
	Backend string `yaml:"backend"`
	Table   string `yaml:"table"`
	Chain   string `yaml:"chain"`
}

type DatabaseConfig struct {
	Engine   string `yaml:"engine"`
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Username string `yaml:"username"`
	Password string `yaml:"password"`
}

type SFTPConfig struct {
	Enabled        bool   `yaml:"enabled"`
	Host           string `yaml:"host"`
	Port           int    `yaml:"port"`
	Username       string `yaml:"username"`
	Password       string `yaml:"password"`
	PrivateKeyPath string `yaml:"private_key_path"`
	KnownHostsPath string `yaml:"known_hosts_path"`
	RemoteBase     string `yaml:"remote_base"`
}

type FTPConfig struct {
	Enabled    bool   `yaml:"enabled"`
	Host       string `yaml:"host"`
	Port       int    `yaml:"port"`
	Username   string `yaml:"username"`
	Password   string `yaml:"password"`
	UseTLS     bool   `yaml:"use_tls"`
	RemoteBase string `yaml:"remote_base"`
}

type LoggingConfig struct {
	Level  string `yaml:"level"`
	Format string `yaml:"format"`
	File   string `yaml:"file"`
}

type ScriptsConfig struct {
	Timeout             time.Duration `yaml:"timeout"`
	AllowedInterpreters []string      `yaml:"allowed_interpreters"`
	Sandbox             SandboxConfig `yaml:"sandbox"`
}

type SandboxConfig struct {
	DropCapabilities  bool     `yaml:"drop_capabilities"`
	NoNewPrivileges   bool     `yaml:"no_new_privileges"`
	ReadOnlyPaths     []string `yaml:"read_only_paths"`
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("config lesen: %w", err)
	}

	cfg := Default()
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("config parsen: %w", err)
	}

	if err := cfg.Validate(); err != nil {
		return nil, err
	}

	return cfg, nil
}

func Default() *Config {
	return &Config{
		Panel: PanelConfig{
			URL:     "https://panel.example.com",
			Timeout: 30 * time.Second,
		},
		Paths: PathsConfig{
			AgentDir:    "/opt/gamepanel/agent",
			ServersDir:  "/srv/gamepanel/servers",
			ImagesDir:   "/srv/gamepanel/images",
			BackupsDir:  "/srv/gamepanel/backups",
			SteamCMDDir: "/opt/gamepanel/steamcmd",
			LogsDir:     "/var/log/gamepanel",
		},
		Agent: AgentConfig{
			HeartbeatInterval: 30 * time.Second,
			JobPollInterval:   10 * time.Second,
			DataDir:           "/opt/gamepanel/agent/data",
		},
		Systemd: SystemdConfig{
			UnitPrefix: "gamepanel-server",
			Slice:      "gamepanel.slice",
		},
		Firewall: FirewallConfig{
			Backend: "nftables",
			Table:   "gamepanel",
			Chain:   "allocations",
		},
		Database: DatabaseConfig{
			Engine:   "mariadb",
			Host:     "127.0.0.1",
			Port:     3306,
			Username: "gamepanel-agent",
		},
		SFTP: SFTPConfig{
			Enabled:    true,
			Port:       22,
			RemoteBase: "/images",
		},
		FTP: FTPConfig{
			Enabled:    false,
			Port:       21,
			UseTLS:     true,
			RemoteBase: "/images",
		},
		Logging: LoggingConfig{
			Level:  "info",
			Format: "json",
			File:   "/var/log/gamepanel/agent.log",
		},
		Scripts: ScriptsConfig{
			Timeout: 5 * time.Minute,
			AllowedInterpreters: []string{
				"/bin/bash",
				"/bin/sh",
			},
			Sandbox: SandboxConfig{
				DropCapabilities: true,
				NoNewPrivileges:  true,
				ReadOnlyPaths: []string{
					"/usr", "/lib", "/lib64",
				},
			},
		},
	}
}

func (c *Config) Validate() error {
	if c.Panel.URL == "" {
		return fmt.Errorf("panel.url ist erforderlich")
	}
	if c.Paths.ServersDir == "" {
		return fmt.Errorf("paths.servers_dir ist erforderlich")
	}
	if c.Agent.HeartbeatInterval <= 0 {
		c.Agent.HeartbeatInterval = 30 * time.Second
	}
	if c.Agent.JobPollInterval <= 0 {
		c.Agent.JobPollInterval = 10 * time.Second
	}
	return nil
}

func (c *Config) ServerPath(serverID string) string {
	return fmt.Sprintf("%s/%s", c.Paths.ServersDir, serverID)
}

func (c *Config) ServerUser(serverID string) string {
	return fmt.Sprintf("gp-s%s", serverID)
}

func (c *Config) UnitName(serverID string) string {
	return fmt.Sprintf("%s-%s.service", c.Systemd.UnitPrefix, serverID)
}

func Save(path string, cfg *Config) error {
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("config serialisieren: %w", err)
	}
	if err := os.WriteFile(path, data, 0o640); err != nil {
		return fmt.Errorf("config schreiben: %w", err)
	}
	return nil
}
