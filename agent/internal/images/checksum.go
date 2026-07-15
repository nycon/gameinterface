package images

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"strings"
)

func SHA256File(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("datei öffnen: %w", err)
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", fmt.Errorf("hash berechnen: %w", err)
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func VerifySHA256(path, expected string) error {
	expected = strings.ToLower(strings.TrimSpace(expected))
	if expected == "" {
		return fmt.Errorf("erwarteter sha256 hash fehlt")
	}

	actual, err := SHA256File(path)
	if err != nil {
		return err
	}

	if !strings.EqualFold(actual, expected) {
		return fmt.Errorf("sha256 stimmt nicht überein: erwartet %s, erhalten %s", expected, actual)
	}
	return nil
}
