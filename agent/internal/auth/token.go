package auth

import (
	"fmt"
	"net/http"
	"os"
	"strings"
)

const (
	HeaderAuthorization = "Authorization"
	HeaderNodeToken     = "X-Node-Token"
	TokenScheme         = "Bearer"
)

// TokenProvider liefert das Node-Authentifizierungstoken.
type TokenProvider struct {
	token string
}

func NewTokenProvider(token string) *TokenProvider {
	return &TokenProvider{token: strings.TrimSpace(token)}
}

func LoadFromFile(path string) (*TokenProvider, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("token-datei lesen: %w", err)
	}
	token := strings.TrimSpace(string(data))
	if token == "" {
		return nil, fmt.Errorf("token-datei ist leer: %s", path)
	}
	return NewTokenProvider(token), nil
}

func (p *TokenProvider) Token() string {
	return p.token
}

func (p *TokenProvider) SetToken(token string) {
	p.token = strings.TrimSpace(token)
}

func (p *TokenProvider) Apply(req *http.Request) {
	if p.token == "" {
		return
	}
	req.Header.Set(HeaderAuthorization, fmt.Sprintf("%s %s", TokenScheme, p.token))
	req.Header.Set(HeaderNodeToken, p.token)
}

func (p *TokenProvider) Validate() error {
	if p.token == "" {
		return fmt.Errorf("node-token fehlt")
	}
	if len(p.token) < 32 {
		return fmt.Errorf("node-token ist zu kurz (min. 32 Zeichen)")
	}
	return nil
}
