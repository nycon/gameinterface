package templates

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// ImageConfig beschreibt, wie das Image gebaut und veröffentlicht wird.
type ImageConfig struct {
	Strategy         string `yaml:"strategy"`
	ArchiveFormat    string `yaml:"archive_format"`
	ImageServerPath  string `yaml:"image_server_path"`
	BuildDir         string `yaml:"build_dir,omitempty"`
	ExcludePatterns  []string `yaml:"exclude_patterns,omitempty"`
}

// ScriptRef verweist auf ein Install-/Update-Skript.
type ScriptRef struct {
	Script string            `yaml:"script"`
	Args   []string          `yaml:"args,omitempty"`
	Env    map[string]string `yaml:"env,omitempty"`
}

// InstallConfig beschreibt den Erstinstallationsprozess.
type InstallConfig struct {
	Script   string            `yaml:"script,omitempty"`
	Args     []string          `yaml:"args,omitempty"`
	Env      map[string]string `yaml:"env,omitempty"`
	Steps    []ScriptRef       `yaml:"steps,omitempty"`
	Requires []string          `yaml:"requires,omitempty"`
}

// UpdateConfig beschreibt den Update-Prozess.
type UpdateConfig struct {
	Script string            `yaml:"script,omitempty"`
	Args   []string          `yaml:"args,omitempty"`
	Env    map[string]string `yaml:"env,omitempty"`
}

// RuntimeConfig beschreibt Laufzeit-Anforderungen des Servers.
type RuntimeConfig struct {
	Executable string            `yaml:"executable"`
	Args       []string          `yaml:"args,omitempty"`
	WorkDir    string            `yaml:"work_dir,omitempty"`
	Env        map[string]string `yaml:"env,omitempty"`
}

// Port beschreibt einen Netzwerk-Port.
type Port struct {
	Name        string `yaml:"name"`
	Protocol    string `yaml:"protocol"`
	Default     int    `yaml:"default"`
	Required    bool   `yaml:"required,omitempty"`
	Description string `yaml:"description,omitempty"`
}

// Variable beschreibt eine konfigurierbare Server-Variable.
type Variable struct {
	Name        string `yaml:"name"`
	Env         string `yaml:"env,omitempty"`
	Default     string `yaml:"default,omitempty"`
	Description string `yaml:"description,omitempty"`
	Rules       string `yaml:"rules,omitempty"`
	Required    bool   `yaml:"required,omitempty"`
}

// GameTemplate ist das vollständige Game-Template im YAML-Format.
type GameTemplate struct {
	Name       string         `yaml:"name"`
	Slug       string         `yaml:"slug"`
	Type       string         `yaml:"type"`
	SteamAppID string         `yaml:"steam_app_id,omitempty"`
	Image      ImageConfig    `yaml:"image"`
	Install    InstallConfig  `yaml:"install"`
	Update     UpdateConfig   `yaml:"update"`
	Runtime    RuntimeConfig  `yaml:"runtime"`
	Ports      []Port         `yaml:"ports"`
	Variables  []Variable     `yaml:"variables"`

	sourcePath string
}

// SourcePath gibt den Dateipfad des geladenen Templates zurück.
func (t *GameTemplate) SourcePath() string {
	return t.sourcePath
}

// Validate prüft Pflichtfelder und Konsistenz.
func (t *GameTemplate) Validate() error {
	if t.Name == "" {
		return fmt.Errorf("name ist erforderlich")
	}
	if t.Slug == "" {
		return fmt.Errorf("slug ist erforderlich")
	}
	if t.Type == "" {
		return fmt.Errorf("type ist erforderlich")
	}
	if t.Image.Strategy == "" {
		return fmt.Errorf("image.strategy ist erforderlich")
	}
	if t.Image.ArchiveFormat == "" {
		return fmt.Errorf("image.archive_format ist erforderlich")
	}
	if t.Type == "steam" && t.SteamAppID == "" {
		return fmt.Errorf("steam_app_id ist für type=steam erforderlich")
	}
	return nil
}

// Loader lädt Game-Templates aus einem Verzeichnis.
type Loader struct {
	Dir string
}

// NewLoader erstellt einen Template-Loader.
func NewLoader(dir string) *Loader {
	return &Loader{Dir: dir}
}

// Load lädt ein Template anhand des Slugs.
func (l *Loader) Load(slug string) (*GameTemplate, error) {
	path := filepath.Join(l.Dir, slug+".yaml")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("template %q laden: %w", slug, err)
	}

	var tmpl GameTemplate
	if err := yaml.Unmarshal(data, &tmpl); err != nil {
		return nil, fmt.Errorf("template %q parsen: %w", slug, err)
	}
	tmpl.sourcePath = path

	if err := tmpl.Validate(); err != nil {
		return nil, fmt.Errorf("template %q: %w", slug, err)
	}
	return &tmpl, nil
}

// List gibt alle verfügbaren Template-Slugs zurück.
func (l *Loader) List() ([]*GameTemplate, error) {
	entries, err := os.ReadDir(l.Dir)
	if err != nil {
		return nil, fmt.Errorf("templates lesen: %w", err)
	}

	var templates []*GameTemplate
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".yaml") {
			continue
		}
		slug := strings.TrimSuffix(entry.Name(), ".yaml")
		tmpl, err := l.Load(slug)
		if err != nil {
			return nil, err
		}
		templates = append(templates, tmpl)
	}
	return templates, nil
}
