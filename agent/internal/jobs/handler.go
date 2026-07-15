package jobs

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gamepanel/agent/internal/api"
	"github.com/gamepanel/agent/internal/backups"
	"github.com/gamepanel/agent/internal/config"
	"github.com/gamepanel/agent/internal/database"
	"github.com/gamepanel/agent/internal/files"
	"github.com/gamepanel/agent/internal/firewall"
	ftpaccount "github.com/gamepanel/agent/internal/ftp"
	"github.com/gamepanel/agent/internal/images"
	"github.com/gamepanel/agent/internal/minecraft"
	"github.com/gamepanel/agent/internal/process"
	"github.com/gamepanel/agent/internal/steamcmd"
	"github.com/gamepanel/agent/internal/systemd"
	"github.com/gamepanel/agent/internal/users"
)

type Handler struct {
	cfg      *config.Config
	api      *api.Client
	systemd  *systemd.Manager
	users    *users.Manager
	files    *files.Manager
	images   *images.Downloader
	backups  *backups.Manager
	firewall *firewall.Manager
	steamcmd *steamcmd.Runner
	db       *database.Manager
	ftp      *ftpaccount.Manager
	log      *slog.Logger
}

func NewHandler(cfg *config.Config, client *api.Client, log *slog.Logger) *Handler {
	return &Handler{
		cfg:      cfg,
		api:      client,
		systemd:  systemd.NewManager(cfg.Systemd.UnitPrefix, cfg.Systemd.Slice),
		users:    users.NewManager(cfg.Paths.ServersDir),
		files:    files.NewManager(cfg.Paths.ServersDir),
		images:   images.NewDownloader(cfg),
		backups:  backups.NewManager(cfg.Paths.BackupsDir),
		firewall: firewall.NewManager(cfg.Firewall.Backend, cfg.Firewall.Table, cfg.Firewall.Chain),
		steamcmd: steamcmd.New(steamcmd.Options{InstallDir: cfg.Paths.SteamCMDDir}),
		db: database.NewManager(database.Options{
			Host:     cfg.Database.Host,
			Port:     cfg.Database.Port,
			Username: cfg.Database.Username,
			Password: cfg.Database.Password,
		}),
		ftp: ftpaccount.NewManager(),
		log: log,
	}
}

func normalizeType(t string) string {
	t = strings.TrimSpace(t)
	t = strings.TrimPrefix(t, "server.")
	return t
}

func serverIDString(job api.Job) string {
	var payload struct {
		ServerID   any    `json:"server_id"`
		ServerUUID string `json:"server_uuid"`
	}
	_ = json.Unmarshal(job.Payload, &payload)

	if payload.ServerUUID != "" {
		return payload.ServerUUID
	}
	switch v := payload.ServerID.(type) {
	case float64:
		return strconv.FormatInt(int64(v), 10)
	case string:
		if v != "" {
			return v
		}
	}
	if job.ServerID != nil {
		return strconv.FormatUint(*job.ServerID, 10)
	}
	return ""
}

func numericServerID(job api.Job) uint64 {
	if job.ServerID != nil {
		return *job.ServerID
	}
	var payload struct {
		ServerID float64 `json:"server_id"`
	}
	_ = json.Unmarshal(job.Payload, &payload)
	return uint64(payload.ServerID)
}

func installRoot(job api.Job, cfg *config.Config, sid string) string {
	var payload struct {
		InstallPath string `json:"install_path"`
	}
	_ = json.Unmarshal(job.Payload, &payload)
	if payload.InstallPath != "" {
		return payload.InstallPath
	}
	if sid != "" {
		return cfg.ServerPath("server-" + sid)
	}
	return cfg.ServerPath(sid)
}

func (h *Handler) Handle(ctx context.Context, job api.Job) error {
	sid := serverIDString(job)
	jobType := normalizeType(job.Type)
	h.log.Info("job gestartet", "uuid", job.UUID, "type", jobType, "server", sid)

	jobCtx, cancel := context.WithTimeout(ctx, 30*time.Minute)
	defer cancel()

	var (
		err          error
		serverStatus string
		result       = map[string]any{"ok": true}
	)

	switch jobType {
	case "install":
		err = h.handleInstall(jobCtx, job, sid)
		serverStatus = "offline"
	case "start":
		err = h.handleStart(jobCtx, sid)
		serverStatus = "online"
	case "stop":
		err = h.handleStop(jobCtx, sid)
		serverStatus = "offline"
	case "restart":
		err = h.handleRestart(jobCtx, sid)
		serverStatus = "online"
	case "update":
		err = h.handleUpdate(jobCtx, job, sid)
		serverStatus = "offline"
	case "backup":
		result, err = h.handleBackup(jobCtx, job, sid)
	case "restore":
		result, err = h.handleRestore(jobCtx, job, sid)
	case "kill":
		err = h.handleKill(jobCtx, sid)
		serverStatus = "offline"
	case "uninstall", "delete":
		err = h.handleUninstall(jobCtx, job, sid)
		serverStatus = "deleted"
	case "files.list":
		result, err = h.handleFilesList(jobCtx, job, sid)
	case "files.read":
		result, err = h.handleFilesRead(jobCtx, job, sid)
	case "files.write":
		result, err = h.handleFilesWrite(jobCtx, job, sid)
	case "console.command":
		result, err = h.handleConsoleCommand(jobCtx, job, sid)
	case "database.create":
		result, err = h.handleDatabaseCreate(jobCtx, job)
	case "database.delete":
		result, err = h.handleDatabaseDelete(jobCtx, job)
	case "ftp.sync":
		result, err = h.handleFtpSync(jobCtx, job)
	default:
		err = fmt.Errorf("unbekannter job-typ: %s", job.Type)
	}

	if err != nil {
		h.log.Error("job fehlgeschlagen", "uuid", job.UUID, "error", err)
		return err
	}

	if result == nil {
		result = map[string]any{"ok": true}
	}

	if reportErr := h.api.CompleteJob(ctx, job.UUID, result, serverStatus); reportErr != nil {
		h.log.Warn("job-status melden fehlgeschlagen", "error", reportErr)
	}
	h.log.Info("job abgeschlossen", "uuid", job.UUID)
	return nil
}

type installPayload struct {
	ManifestRemote  string `json:"manifest_remote"`
	ArchiveRemote   string `json:"archive_remote"`
	ArchivePath     string `json:"archive_path"`
	SteamAppID      string `json:"steam_app_id"`
	MemoryMax       string `json:"memory_max"`
	MemoryMin       string `json:"memory_min"`
	CPUPercent      int    `json:"cpu_percent"`
	Port            int    `json:"port"`
	Protocol        string `json:"protocol"`
	StartupCommand  string `json:"startup_command"`
	InstallPath     string `json:"install_path"`
	LinuxUser       string `json:"linux_user"`
	TemplateSlug    string `json:"template_slug"`
	InstallStrategy string `json:"install_strategy"`
	MinecraftVer    string `json:"minecraft_version"`
	WorkDir         string `json:"work_dir"`
	Motd            string `json:"motd"`
	MaxPlayers      string `json:"max_players"`
	OnlineMode      string `json:"online_mode"`
}

func (h *Handler) handleInstall(ctx context.Context, job api.Job, serverID string) error {
	if serverID == "" {
		return fmt.Errorf("server_id fehlt")
	}

	var payload installPayload
	if err := json.Unmarshal(job.Payload, &payload); err != nil {
		return fmt.Errorf("payload parsen: %w", err)
	}

	// Numerische ID bevorzugen für Usernamen
	keyForUser := serverID
	if id := numericServerID(job); id > 0 {
		keyForUser = strconv.FormatUint(id, 10)
	}
	username, err := h.users.EnsureNamed(keyForUser, payload.LinuxUser)
	if err != nil {
		return err
	}

	serverDir, err := h.files.EnsureServerDir(serverID)
	if err != nil {
		return err
	}
	if payload.InstallPath != "" {
		serverDir = payload.InstallPath
		_ = os.MkdirAll(serverDir, 0o750)
	}

	var manifest *images.Manifest
	if payload.ManifestRemote != "" {
		manifest, err = h.images.DownloadManifest(ctx, payload.ManifestRemote)
		if err != nil {
			return err
		}
	}

	remote := payload.ArchiveRemote
	if remote == "" {
		remote = payload.ArchivePath
	}
	if manifest != nil && remote == "" {
		remote = manifest.Archive
	}

	installedViaArchive := false
	if remote != "" {
		result, err := h.images.Download(ctx, images.DownloadRequest{
			RemotePath: remote,
			Manifest:   manifest,
		})
		if err != nil {
			return err
		}
		if result.Extracted {
			serverDir = result.LocalPath
			installedViaArchive = true
		}
	}

	if payload.SteamAppID != "" {
		if _, err := h.steamcmd.Install(ctx, steamcmd.InstallRequest{
			AppID:      payload.SteamAppID,
			InstallDir: serverDir,
			Validate:   true,
		}); err != nil {
			return err
		}
	}

	// Minecraft ohne Image: offizielles JAR laden
	needsMinecraft := !installedViaArchive && payload.SteamAppID == "" && (
		payload.InstallStrategy == "script" ||
			minecraft.LooksLikeMinecraft(payload.StartupCommand, payload.TemplateSlug) ||
			strings.EqualFold(payload.TemplateSlug, "minecraft"))
	if needsMinecraft {
		h.log.Info("minecraft install", "dir", serverDir, "version", payload.MinecraftVer)
		if err := minecraft.Install(ctx, minecraft.InstallRequest{
			ServerDir: serverDir,
			Version:   payload.MinecraftVer,
			JarName:   "server.jar",
		}); err != nil {
			return fmt.Errorf("minecraft install: %w", err)
		}
		if err := minecraft.WriteServerProperties(serverDir, minecraft.Properties{
			Motd:       payload.Motd,
			MaxPlayers: payload.MaxPlayers,
			OnlineMode: payload.OnlineMode,
			ServerPort: payload.Port,
		}); err != nil {
			h.log.Warn("server.properties schreiben fehlgeschlagen", "error", err)
		}
	}

	workDir := serverDir
	if payload.WorkDir != "" && payload.WorkDir != "/server" {
		// relative work_dir under serverDir
		if !filepath.IsAbs(payload.WorkDir) {
			workDir = filepath.Join(serverDir, payload.WorkDir)
		}
	}
	// Legacy "serverfiles" nur wenn vorhanden
	if _, err := os.Stat(filepath.Join(serverDir, "serverfiles")); err == nil && payload.WorkDir == "" && !needsMinecraft {
		workDir = filepath.Join(serverDir, "serverfiles")
	}

	execPath := ""
	var args []string
	env := map[string]string{}
	if payload.StartupCommand != "" {
		parts := strings.Fields(payload.StartupCommand)
		if len(parts) > 0 {
			execPath = parts[0]
			args = parts[1:]
		}
	} else if manifest != nil {
		execPath = filepath.Join(workDir, manifest.Startup.Executable)
		args = manifest.Startup.Args
		env = manifest.Environment
	}

	if needsMinecraft && (execPath == "" || execPath == "java") {
		memMin := payload.MemoryMin
		memMax := payload.MemoryMax
		if memMin == "" {
			memMin = "1024M"
		}
		if memMax == "" {
			memMax = "2048M"
		}
		execPath = "java"
		args = []string{"-Xms" + memMin, "-Xmx" + memMax, "-jar", "server.jar", "nogui"}
	}

	if execPath == "" {
		return fmt.Errorf("kein startup executable konfiguriert")
	}

	// Relative jars from workDir
	if execPath != "java" && !filepath.IsAbs(execPath) && !strings.Contains(execPath, "/") {
		// keep as-is for PATH binaries
	}

	_ = h.users.ChownTree(serverDir, username)

	spec := systemd.ServerSpec{
		ServerID:    serverID,
		Username:    username,
		WorkingDir:  workDir,
		Executable:  execPath,
		Args:        args,
		Environment: env,
		MemoryMax:   payload.MemoryMax,
		CPUPercent:  payload.CPUPercent,
		Port:        payload.Port,
	}
	if err := h.systemd.Install(spec); err != nil {
		return err
	}

	if payload.Port > 0 {
		proto := payload.Protocol
		if proto == "" {
			proto = "tcp"
		}
		if err := h.firewall.Allow(firewall.Allocation{
			ServerID: serverID,
			Protocol: proto,
			Port:     payload.Port,
		}); err != nil {
			h.log.Warn("firewall-regel fehlgeschlagen", "error", err)
		}
	}

	return nil
}

func (h *Handler) handleStart(_ context.Context, serverID string) error {
	return h.systemd.Start(serverID)
}

func (h *Handler) handleStop(_ context.Context, serverID string) error {
	return h.systemd.Stop(serverID)
}

func (h *Handler) handleRestart(_ context.Context, serverID string) error {
	return h.systemd.Restart(serverID)
}

func (h *Handler) handleKill(_ context.Context, serverID string) error {
	return h.systemd.Kill(serverID)
}

func (h *Handler) handleUninstall(_ context.Context, job api.Job, serverID string) error {
	var payload struct {
		LinuxUser   string `json:"linux_user"`
		InstallPath string `json:"install_path"`
	}
	_ = json.Unmarshal(job.Payload, &payload)

	_ = h.systemd.Remove(serverID)

	dir := payload.InstallPath
	if dir == "" {
		dir = installRoot(job, h.cfg, serverID)
	}
	if dir != "" && dir != "/" {
		_ = os.RemoveAll(dir)
	}

	keyForUser := serverID
	if id := numericServerID(job); id > 0 {
		keyForUser = strconv.FormatUint(id, 10)
	}
	user := users.SanitizeUsername(payload.LinuxUser, keyForUser)
	_ = exec.Command("userdel", user).Run()

	return nil
}

type updatePayload struct {
	ManifestRemote  string `json:"manifest_remote"`
	ArchiveRemote   string `json:"archive_remote"`
	SteamAppID      string `json:"steam_app_id"`
	TemplateSlug    string `json:"template_slug"`
	InstallStrategy string `json:"install_strategy"`
	MinecraftVer    string `json:"minecraft_version"`
	StartupCommand  string `json:"startup_command"`
}

func (h *Handler) handleUpdate(ctx context.Context, job api.Job, serverID string) error {
	_ = h.handleStop(ctx, serverID)

	var payload updatePayload
	if len(job.Payload) > 0 {
		if err := json.Unmarshal(job.Payload, &payload); err != nil {
			return fmt.Errorf("payload parsen: %w", err)
		}
	}

	serverDir := installRoot(job, h.cfg, serverID)

	if payload.SteamAppID != "" {
		if _, err := h.steamcmd.Install(ctx, steamcmd.InstallRequest{
			AppID:      payload.SteamAppID,
			InstallDir: serverDir,
			Validate:   true,
		}); err != nil {
			return err
		}
	}

	if payload.ArchiveRemote != "" || payload.ManifestRemote != "" {
		var manifest *images.Manifest
		var err error
		if payload.ManifestRemote != "" {
			manifest, err = h.images.DownloadManifest(ctx, payload.ManifestRemote)
			if err != nil {
				return err
			}
		}
		remote := payload.ArchiveRemote
		if manifest != nil && remote == "" {
			remote = manifest.Archive
		}
		if _, err := h.images.Download(ctx, images.DownloadRequest{
			RemotePath: remote,
			Manifest:   manifest,
		}); err != nil {
			return err
		}
	} else if payload.SteamAppID == "" && (
		payload.InstallStrategy == "script" ||
			minecraft.LooksLikeMinecraft(payload.StartupCommand, payload.TemplateSlug) ||
			strings.EqualFold(payload.TemplateSlug, "minecraft")) {
		if err := minecraft.Install(ctx, minecraft.InstallRequest{
			ServerDir: serverDir,
			Version:   payload.MinecraftVer,
			JarName:   "server.jar",
		}); err != nil {
			return fmt.Errorf("minecraft update: %w", err)
		}
	}

	return nil
}

func (h *Handler) handleBackup(ctx context.Context, job api.Job, serverID string) (map[string]any, error) {
	source := installRoot(job, h.cfg, serverID)
	path, err := h.backups.Create(ctx, serverID, source)
	if err != nil {
		return nil, err
	}
	info, _ := os.Stat(path)
	sum, _ := fileSHA256(path)
	size := int64(0)
	if info != nil {
		size = info.Size()
	}
	h.log.Info("backup erstellt", "path", path)
	return map[string]any{
		"ok":              true,
		"path":            path,
		"size_bytes":      size,
		"checksum_sha256": sum,
	}, nil
}

type restorePayload struct {
	ArchivePath string `json:"archive_path"`
	BackupUUID  string `json:"backup_uuid"`
}

func (h *Handler) handleRestore(ctx context.Context, job api.Job, serverID string) (map[string]any, error) {
	var payload restorePayload
	if err := json.Unmarshal(job.Payload, &payload); err != nil {
		return nil, fmt.Errorf("payload parsen: %w", err)
	}
	if payload.ArchivePath == "" {
		return nil, fmt.Errorf("archive_path fehlt")
	}
	_ = h.handleStop(ctx, serverID)
	dest := installRoot(job, h.cfg, serverID)
	if err := h.backups.Restore(ctx, payload.ArchivePath, dest); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true, "backup_uuid": payload.BackupUUID}, nil
}

func (h *Handler) handleFilesList(_ context.Context, job api.Job, sid string) (map[string]any, error) {
	var payload struct {
		Path string `json:"path"`
	}
	_ = json.Unmarshal(job.Payload, &payload)
	root := installRoot(job, h.cfg, sid)
	entries, err := h.files.ListIn(root, payload.Path)
	if err != nil {
		return nil, err
	}
	list := make([]map[string]any, 0, len(entries))
	for _, e := range entries {
		list = append(list, map[string]any{
			"name":     e.Name,
			"path":     e.Path,
			"size":     e.Size,
			"is_dir":   e.IsDir,
			"type":     map[bool]string{true: "directory", false: "file"}[e.IsDir],
			"mod_time": e.ModTime,
		})
	}
	return map[string]any{"ok": true, "entries": list, "path": payload.Path}, nil
}

func (h *Handler) handleFilesRead(_ context.Context, job api.Job, sid string) (map[string]any, error) {
	var payload struct {
		Path string `json:"path"`
	}
	_ = json.Unmarshal(job.Payload, &payload)
	root := installRoot(job, h.cfg, sid)
	data, err := h.files.ReadIn(root, payload.Path, 2<<20)
	if err != nil {
		return nil, err
	}
	return map[string]any{"ok": true, "path": payload.Path, "content": string(data)}, nil
}

func (h *Handler) handleFilesWrite(_ context.Context, job api.Job, sid string) (map[string]any, error) {
	var payload struct {
		Path    string `json:"path"`
		Content string `json:"content"`
	}
	if err := json.Unmarshal(job.Payload, &payload); err != nil {
		return nil, err
	}
	root := installRoot(job, h.cfg, sid)
	if err := h.files.WriteIn(root, payload.Path, []byte(payload.Content), 0o640); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true, "path": payload.Path}, nil
}

func (h *Handler) handleConsoleCommand(ctx context.Context, job api.Job, sid string) (map[string]any, error) {
	var payload struct {
		Command string `json:"command"`
	}
	_ = json.Unmarshal(job.Payload, &payload)
	unit := h.systemd.UnitName(sid)

	// Prefer systemd-run / stdin dump into journal as console echo
	serverID := numericServerID(job)
	_ = h.api.PostEvent(ctx, serverID, "console.output", "> "+payload.Command, nil)

	cmd := exec.CommandContext(ctx, "bash", "-c", fmt.Sprintf("echo %q | systemd-cat -t %s", payload.Command, unit))
	out, err := cmd.CombinedOutput()
	msg := strings.TrimSpace(string(out))
	if err != nil {
		_ = h.api.PostEvent(ctx, serverID, "console.output", "command failed: "+err.Error()+" "+msg, nil)
		return nil, fmt.Errorf("console command: %w: %s", err, msg)
	}

	lines, jerr := process.JournalLogs(ctx, unit, 20)
	if jerr == nil {
		for _, line := range lines {
			_ = h.api.PostEvent(ctx, serverID, "console.output", line, nil)
		}
	}

	return map[string]any{"ok": true, "output": msg}, nil
}

func (h *Handler) handleDatabaseCreate(ctx context.Context, job api.Job) (map[string]any, error) {
	var payload struct {
		Name     string `json:"name"`
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.Unmarshal(job.Payload, &payload); err != nil {
		return nil, err
	}
	if err := h.db.Create(ctx, payload.Name, payload.Username, payload.Password); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true, "name": payload.Name}, nil
}

func (h *Handler) handleDatabaseDelete(ctx context.Context, job api.Job) (map[string]any, error) {
	var payload struct {
		Name     string `json:"name"`
		Username string `json:"username"`
	}
	if err := json.Unmarshal(job.Payload, &payload); err != nil {
		return nil, err
	}
	if err := h.db.Delete(ctx, payload.Name, payload.Username); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func (h *Handler) handleFtpSync(_ context.Context, job api.Job) (map[string]any, error) {
	var payload struct {
		Action   string `json:"action"`
		Username string `json:"username"`
		Password string `json:"password"`
		HomePath string `json:"home_path"`
	}
	if err := json.Unmarshal(job.Payload, &payload); err != nil {
		return nil, err
	}
	switch payload.Action {
	case "delete":
		if err := h.ftp.Delete(payload.Username); err != nil {
			return nil, err
		}
	default:
		if err := h.ftp.Ensure(payload.Username, payload.Password, payload.HomePath); err != nil {
			return nil, err
		}
	}
	return map[string]any{"ok": true, "username": payload.Username}, nil
}

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
