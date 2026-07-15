package sftpclient

import (
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"path"
	"path/filepath"
	"time"

	"github.com/gamepanel/agent/internal/config"
	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/knownhosts"
)

type Client struct {
	conn    *ssh.Client
	sftp    *sftp.Client
	remote  string
}

func New(cfg config.SFTPConfig) (*Client, error) {
	if cfg.Host == "" {
		return nil, fmt.Errorf("sftp.host fehlt")
	}
	if cfg.Port == 0 {
		cfg.Port = 22
	}

	authMethods, err := buildAuth(cfg)
	if err != nil {
		return nil, err
	}

	hostKeyCallback, err := buildHostKeyCallback(cfg)
	if err != nil {
		return nil, err
	}

	addr := net.JoinHostPort(cfg.Host, fmt.Sprintf("%d", cfg.Port))
	sshCfg := &ssh.ClientConfig{
		User:            cfg.Username,
		Auth:            authMethods,
		HostKeyCallback: hostKeyCallback,
		Timeout:         30 * time.Second,
	}

	conn, err := ssh.Dial("tcp", addr, sshCfg)
	if err != nil {
		return nil, fmt.Errorf("ssh verbindung: %w", err)
	}

	sftpClient, err := sftp.NewClient(conn)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("sftp session: %w", err)
	}

	return &Client{
		conn:   conn,
		sftp:   sftpClient,
		remote: cfg.RemoteBase,
	}, nil
}

func (c *Client) Close() error {
	if c.sftp != nil {
		_ = c.sftp.Close()
	}
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}

func (c *Client) Download(ctx context.Context, remotePath, localPath string) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	remote := c.resolveRemote(remotePath)
	if err := os.MkdirAll(filepath.Dir(localPath), 0o750); err != nil {
		return fmt.Errorf("lokales verzeichnis: %w", err)
	}

	src, err := c.sftp.Open(remote)
	if err != nil {
		return fmt.Errorf("remote öffnen: %w", err)
	}
	defer src.Close()

	dst, err := os.Create(localPath)
	if err != nil {
		return fmt.Errorf("lokal erstellen: %w", err)
	}
	defer dst.Close()

	if _, err := io.Copy(dst, src); err != nil {
		return fmt.Errorf("download: %w", err)
	}
	return nil
}

func (c *Client) resolveRemote(p string) string {
	if path.IsAbs(p) {
		return p
	}
	return path.Join(c.remote, p)
}

func buildAuth(cfg config.SFTPConfig) ([]ssh.AuthMethod, error) {
	var methods []ssh.AuthMethod

	if cfg.Password != "" {
		methods = append(methods, ssh.Password(cfg.Password))
	}

	if cfg.PrivateKeyPath != "" {
		key, err := os.ReadFile(cfg.PrivateKeyPath)
		if err != nil {
			return nil, fmt.Errorf("private key lesen: %w", err)
		}
		signer, err := ssh.ParsePrivateKey(key)
		if err != nil {
			return nil, fmt.Errorf("private key parsen: %w", err)
		}
		methods = append(methods, ssh.PublicKeys(signer))
	}

	if len(methods) == 0 {
		return nil, fmt.Errorf("sftp authentifizierung nicht konfiguriert")
	}
	return methods, nil
}

func buildHostKeyCallback(cfg config.SFTPConfig) (ssh.HostKeyCallback, error) {
	if cfg.KnownHostsPath != "" {
		return knownhosts.New(cfg.KnownHostsPath)
	}
	// Entwicklung: InsecureSkipVerify vermeiden in Produktion – KnownHosts empfohlen.
	return ssh.InsecureIgnoreHostKey(), nil //nolint:gosec
}
