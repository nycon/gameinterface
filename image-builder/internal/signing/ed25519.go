package signing

import (
	"crypto/ed25519"
	"encoding/hex"
	"fmt"
	"os"

	"github.com/gamepanel/image-builder/internal/manifest"
)

// Signer signiert Manifeste mit Ed25519.
type Signer struct {
	privateKey ed25519.PrivateKey
}

// LoadSigner lädt einen Ed25519-Privatkey aus einer Hex-Datei oder Umgebungsvariable.
func LoadSigner(keyPath string) (*Signer, error) {
	if keyPath == "" {
		keyPath = os.Getenv("SIGNING_KEY_PATH")
	}
	if keyPath == "" {
		return nil, nil
	}

	data, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("signing key laden: %w", err)
	}

	keyBytes, err := hex.DecodeString(string(trimSpace(data)))
	if err != nil {
		return nil, fmt.Errorf("signing key dekodieren: %w", err)
	}
	if len(keyBytes) != ed25519.PrivateKeySize {
		return nil, fmt.Errorf("ungültige key-länge: %d", len(keyBytes))
	}

	return &Signer{privateKey: ed25519.PrivateKey(keyBytes)}, nil
}

// SignManifest signiert ein Manifest und setzt das Signaturfeld.
func (s *Signer) SignManifest(m *manifest.Manifest) error {
	if s == nil {
		return nil
	}
	hash, err := manifest.HashManifest(*m)
	if err != nil {
		return err
	}
	sig := ed25519.Sign(s.privateKey, []byte(hash))
	m.Signature = hex.EncodeToString(sig)
	return nil
}

// VerifyManifest prüft die Ed25519-Signatur eines Manifests.
func VerifyManifest(m *manifest.Manifest, publicKey ed25519.PublicKey) error {
	if m.Signature == "" {
		return fmt.Errorf("manifest hat keine signatur")
	}
	hash, err := manifest.HashManifest(*m)
	if err != nil {
		return err
	}
	sig, err := hex.DecodeString(m.Signature)
	if err != nil {
		return err
	}
	if !ed25519.Verify(publicKey, []byte(hash), sig) {
		return fmt.Errorf("signatur ungültig")
	}
	return nil
}

// GenerateKeyPair erzeugt ein neues Ed25519-Schlüsselpaar und schreibt den Privatkey.
func GenerateKeyPair(path string) (ed25519.PublicKey, error) {
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		return nil, err
	}
	hexKey := hex.EncodeToString(priv)
	if err := os.WriteFile(path, []byte(hexKey+"\n"), 0o600); err != nil {
		return nil, err
	}
	return pub, nil
}

func trimSpace(b []byte) []byte {
	start, end := 0, len(b)
	for start < end && (b[start] == ' ' || b[start] == '\n' || b[start] == '\r' || b[start] == '\t') {
		start++
	}
	for end > start && (b[end-1] == ' ' || b[end-1] == '\n' || b[end-1] == '\r' || b[end-1] == '\t') {
		end--
	}
	return b[start:end]
}
