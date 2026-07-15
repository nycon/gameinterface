package ftpclient

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/gamepanel/agent/internal/config"
)

type Client struct {
	conn   net.Conn
	reader *bufReader
	cfg    config.FTPConfig
}

type bufReader struct {
	r io.Reader
}

func New(cfg config.FTPConfig) (*Client, error) {
	if cfg.Host == "" {
		return nil, fmt.Errorf("ftp.host fehlt")
	}
	if cfg.Port == 0 {
		cfg.Port = 21
	}

	addr := net.JoinHostPort(cfg.Host, fmt.Sprintf("%d", cfg.Port))
	var conn net.Conn
	var err error

	if cfg.UseTLS {
		conn, err = tls.DialWithDialer(&net.Dialer{Timeout: 30 * time.Second}, "tcp", addr, &tls.Config{
			MinVersion: tls.VersionTLS12,
			ServerName: cfg.Host,
		})
	} else {
		conn, err = net.DialTimeout("tcp", addr, 30*time.Second)
	}
	if err != nil {
		return nil, fmt.Errorf("ftp verbindung: %w", err)
	}

	c := &Client{conn: conn, cfg: cfg, reader: &bufReader{r: conn}}
	if err := c.login(); err != nil {
		conn.Close()
		return nil, err
	}
	return c, nil
}

func (c *Client) Close() error {
	if c.conn == nil {
		return nil
	}
	_, _ = c.command("QUIT")
	return c.conn.Close()
}

func (c *Client) Download(ctx context.Context, remotePath, localPath string) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	remote := c.resolveRemote(remotePath)
	if err := os.MkdirAll(filepath.Dir(localPath), 0o750); err != nil {
		return err
	}

	dataConn, err := c.enterPassive()
	if err != nil {
		return err
	}
	defer dataConn.Close()

	if _, err := c.command("RETR " + remote); err != nil {
		return fmt.Errorf("retr: %w", err)
	}

	dst, err := os.Create(localPath)
	if err != nil {
		return err
	}
	defer dst.Close()

	if _, err := io.Copy(dst, dataConn); err != nil {
		return fmt.Errorf("download: %w", err)
	}

	_, _ = c.readResponse()
	return nil
}

func (c *Client) login() error {
	if _, err := c.readResponse(); err != nil {
		return err
	}
	if _, err := c.command("USER " + c.cfg.Username); err != nil {
		return err
	}
	if c.cfg.Password != "" {
		if _, err := c.command("PASS " + c.cfg.Password); err != nil {
			return err
		}
	}
	return nil
}

func (c *Client) enterPassive() (net.Conn, error) {
	resp, err := c.command("PASV")
	if err != nil {
		return nil, err
	}

	host, port, err := parsePASV(resp)
	if err != nil {
		return nil, err
	}
	return net.DialTimeout("tcp", net.JoinHostPort(host, fmt.Sprintf("%d", port)), 30*time.Second)
}

func (c *Client) command(cmd string) (string, error) {
	if _, err := fmt.Fprintf(c.conn, "%s\r\n", cmd); err != nil {
		return "", err
	}
	return c.readResponse()
}

func (c *Client) readResponse() (string, error) {
	buf := make([]byte, 4096)
	n, err := c.conn.Read(buf)
	if err != nil {
		return "", err
	}
	resp := string(buf[:n])
	if len(resp) >= 3 && resp[0] >= '4' {
		return resp, fmt.Errorf("ftp fehler: %s", strings.TrimSpace(resp))
	}
	return resp, nil
}

func (c *Client) resolveRemote(p string) string {
	if strings.HasPrefix(p, "/") {
		return p
	}
	return path.Join(c.cfg.RemoteBase, p)
}

func parsePASV(resp string) (string, int, error) {
	start := strings.Index(resp, "(")
	end := strings.Index(resp, ")")
	if start < 0 || end < 0 {
		return "", 0, fmt.Errorf("pasv antwort ungültig")
	}
	parts := strings.Split(resp[start+1:end], ",")
	if len(parts) < 6 {
		return "", 0, fmt.Errorf("pasv parameter ungültig")
	}

	host := strings.Join(parts[0:4], ".")
	p1, _ := parseOctet(parts[4])
	p2, _ := parseOctet(parts[5])
	return host, p1*256 + p2, nil
}

func parseOctet(s string) (int, error) {
	var v int
	_, err := fmt.Sscanf(strings.TrimSpace(s), "%d", &v)
	return v, err
}
