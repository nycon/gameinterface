package minecraft

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const manifestURL = "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json"

type InstallRequest struct {
	ServerDir string
	Version   string // latest or 1.21.1
	JarName   string
}

// Install downloads the official Mojang server.jar into ServerDir and writes eula.txt.
func Install(ctx context.Context, req InstallRequest) error {
	if req.ServerDir == "" {
		return fmt.Errorf("server dir fehlt")
	}
	if req.JarName == "" {
		req.JarName = "server.jar"
	}
	if req.Version == "" {
		req.Version = "latest"
	}
	if err := os.MkdirAll(req.ServerDir, 0o750); err != nil {
		return err
	}

	client := &http.Client{Timeout: 5 * time.Minute}
	versionURL, err := resolveVersionURL(ctx, client, req.Version)
	if err != nil {
		return err
	}

	serverURL, err := resolveServerJarURL(ctx, client, versionURL)
	if err != nil {
		return err
	}

	jarPath := filepath.Join(req.ServerDir, req.JarName)
	tmp := jarPath + ".tmp"
	if err := downloadFile(ctx, client, serverURL, tmp); err != nil {
		return err
	}
	if err := os.Rename(tmp, jarPath); err != nil {
		_ = os.Remove(tmp)
		return err
	}

	eula := filepath.Join(req.ServerDir, "eula.txt")
	if _, err := os.Stat(eula); os.IsNotExist(err) {
		if err := os.WriteFile(eula, []byte("eula=true\n"), 0o644); err != nil {
			return err
		}
	}
	return nil
}

func resolveVersionURL(ctx context.Context, client *http.Client, version string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, manifestURL, nil)
	if err != nil {
		return "", err
	}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("version manifest http %d", resp.StatusCode)
	}
	var body struct {
		Latest struct {
			Release string `json:"release"`
		} `json:"latest"`
		Versions []struct {
			ID  string `json:"id"`
			URL string `json:"url"`
		} `json:"versions"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return "", err
	}
	want := version
	if want == "latest" {
		want = body.Latest.Release
	}
	for _, v := range body.Versions {
		if v.ID == want {
			return v.URL, nil
		}
	}
	return "", fmt.Errorf("minecraft version nicht gefunden: %s", version)
}

func resolveServerJarURL(ctx context.Context, client *http.Client, versionURL string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, versionURL, nil)
	if err != nil {
		return "", err
	}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("version json http %d", resp.StatusCode)
	}
	var body struct {
		Downloads struct {
			Server struct {
				URL string `json:"url"`
			} `json:"server"`
		} `json:"downloads"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return "", err
	}
	if body.Downloads.Server.URL == "" {
		return "", fmt.Errorf("kein server download url")
	}
	return body.Downloads.Server.URL, nil
}

func downloadFile(ctx context.Context, client *http.Client, url, dest string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download http %d", resp.StatusCode)
	}
	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, resp.Body)
	return err
}

// LooksLikeMinecraft erkennt Minecraft anhand Startup/Payload-Hinweisen.
func LooksLikeMinecraft(startup, slug string) bool {
	s := strings.ToLower(startup + " " + slug)
	return strings.Contains(s, "server.jar") || strings.Contains(s, "minecraft")
}
