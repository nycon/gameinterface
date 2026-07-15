package scripts

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
)

var allowedName = regexp.MustCompile(`^[a-zA-Z0-9._-]+$`)

func ValidateParameters(params map[string]string) error {
	for key, value := range params {
		if !allowedName.MatchString(key) {
			return fmt.Errorf("parameter-name ungültig: %s", key)
		}
		if strings.ContainsAny(value, "\x00\n\r") {
			return fmt.Errorf("parameter-wert enthält ungültige zeichen: %s", key)
		}
		if len(value) > 4096 {
			return fmt.Errorf("parameter-wert zu lang: %s", key)
		}
	}
	return nil
}

func ValidateScriptPath(scriptPath string, allowedDirs []string) error {
	abs, err := filepath.Abs(scriptPath)
	if err != nil {
		return fmt.Errorf("script-pfad: %w", err)
	}

	for _, dir := range allowedDirs {
		base, err := filepath.Abs(dir)
		if err != nil {
			continue
		}
		rel, err := filepath.Rel(base, abs)
		if err != nil {
			continue
		}
		if rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			return nil
		}
	}
	return fmt.Errorf("script außerhalb erlaubter verzeichnisse: %s", scriptPath)
}

func ValidateInterpreter(interpreter string, allowed []string) error {
	abs, err := filepath.Abs(interpreter)
	if err != nil {
		return fmt.Errorf("interpreter: %w", err)
	}
	for _, a := range allowed {
		if abs == a {
			return nil
		}
	}
	return fmt.Errorf("interpreter nicht erlaubt: %s", interpreter)
}
