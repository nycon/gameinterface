package images

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type Manifest struct {
	ID          string            `yaml:"id" json:"id"`
	Name        string            `yaml:"name" json:"name"`
	Version     string            `yaml:"version" json:"version"`
	Archive     string            `yaml:"archive" json:"archive"`
	SHA256      string            `yaml:"sha256" json:"sha256"`
	ExtractTo   string            `yaml:"extract_to" json:"extract_to"`
	Startup     StartupConfig     `yaml:"startup" json:"startup"`
	Environment map[string]string `yaml:"environment" json:"environment"`
}

type StartupConfig struct {
	Executable string   `yaml:"executable" json:"executable"`
	Args       []string `yaml:"args" json:"args"`
}

func ParseManifest(data []byte) (*Manifest, error) {
	var m Manifest
	if err := yaml.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("manifest parsen: %w", err)
	}
	return m.Validate()
}

func ParseManifestFile(path string) (*Manifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("manifest lesen: %w", err)
	}
	return ParseManifest(data)
}

func (m *Manifest) Validate() (*Manifest, error) {
	if m.ID == "" {
		return nil, fmt.Errorf("manifest.id fehlt")
	}
	if m.Archive == "" {
		return nil, fmt.Errorf("manifest.archive fehlt")
	}
	if m.SHA256 == "" {
		return nil, fmt.Errorf("manifest.sha256 fehlt")
	}
	if m.Startup.Executable == "" {
		return nil, fmt.Errorf("manifest.startup.executable fehlt")
	}
	return m, nil
}
