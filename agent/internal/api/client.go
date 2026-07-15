package api

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"runtime"
	"strings"
	"time"

	"github.com/gamepanel/agent/internal/auth"
	"github.com/gamepanel/agent/internal/config"
	"github.com/gamepanel/agent/internal/metrics"
)

const (
	registerPath  = "/api/node/register"
	heartbeatPath = "/api/node/heartbeat"
	jobsPath      = "/api/node/jobs"
	jobStatusPath = "/api/node/jobs/%s/status"
	metricsPath   = "/api/node/metrics"
	eventsPath    = "/api/node/events"
)

type Client struct {
	baseURL    string
	httpClient *http.Client
	token      *auth.TokenProvider
	nodeID     string
}

type RegisterRequest struct {
	Name          string `json:"name"`
	Hostname      string `json:"hostname"`
	IPAddress     string `json:"ip_address"`
	AgentVersion  string `json:"agent_version,omitempty"`
	CPUCores      int    `json:"cpu_cores,omitempty"`
	MemoryMB      int64  `json:"memory_mb,omitempty"`
	DiskGB        int64  `json:"disk_gb,omitempty"`
	SetupToken    string `json:"setup_token,omitempty"`
	NodeUUID      string `json:"node_uuid,omitempty"`
}

type RegisterResponse struct {
	Node  NodeInfo `json:"node"`
	Token string   `json:"token"`
}

type NodeInfo struct {
	ID   uint64 `json:"id"`
	UUID string `json:"uuid"`
	Name string `json:"name"`
}

type HeartbeatRequest struct {
	AgentVersion string         `json:"agent_version,omitempty"`
	CPUCores     int            `json:"cpu_cores,omitempty"`
	MemoryMB     int64          `json:"memory_mb,omitempty"`
	DiskGB       int64          `json:"disk_gb,omitempty"`
	Meta         map[string]any `json:"meta,omitempty"`
}

type HeartbeatResponse struct {
	OK         bool   `json:"ok"`
	ServerTime string `json:"server_time,omitempty"`
}

// Job mirrors panel_jobs as returned by GET /api/node/jobs
type Job struct {
	ID       uint64          `json:"id"`
	UUID     string          `json:"uuid"`
	Type     string          `json:"type"`
	Status   string          `json:"status"`
	Payload  json.RawMessage `json:"payload"`
	ServerID *uint64         `json:"server_id"`
	NodeID   *uint64         `json:"node_id"`
	Progress int             `json:"progress"`
}

type JobStatusUpdate struct {
	Status       string         `json:"status"`
	Progress     *int           `json:"progress,omitempty"`
	Result       map[string]any `json:"result,omitempty"`
	Error        string         `json:"error,omitempty"`
	ServerStatus string         `json:"server_status,omitempty"`
}

type JobsResponse struct {
	Jobs []Job `json:"jobs"`
}

func NewClient(cfg *config.Config, token *auth.TokenProvider) *Client {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	if cfg.Panel.TLSInsecure {
		transport.TLSClientConfig = &tls.Config{InsecureSkipVerify: true} //nolint:gosec
	}

	return &Client{
		baseURL: strings.TrimRight(cfg.Panel.URL, "/"),
		httpClient: &http.Client{
			Timeout:   cfg.Panel.Timeout,
			Transport: transport,
		},
		token:  token,
		nodeID: cfg.Node.ID,
	}
}

func (c *Client) SetNodeID(id string) {
	c.nodeID = id
}

func (c *Client) Register(ctx context.Context, req RegisterRequest) (*RegisterResponse, error) {
	var resp RegisterResponse
	if err := c.doJSON(ctx, http.MethodPost, registerPath, req, &resp); err != nil {
		return nil, err
	}
	if resp.Token == "" || resp.Node.UUID == "" {
		return nil, fmt.Errorf("registrierung: unvollständige antwort vom panel")
	}
	c.nodeID = resp.Node.UUID
	c.token.SetToken(resp.Token)
	return &resp, nil
}

func (c *Client) Heartbeat(ctx context.Context, snap metrics.Snapshot, _ time.Duration) (*HeartbeatResponse, error) {
	req := HeartbeatRequest{
		CPUCores: runtimeNumCPU(),
		MemoryMB: int64(snap.MemoryTotal / (1024 * 1024)),
		DiskGB:   int64(snap.DiskTotal / (1024 * 1024 * 1024)),
		Meta: map[string]any{
			"cpu_percent":        snap.CPUPercent,
			"memory_used_bytes":  snap.MemoryUsed,
			"memory_total_bytes": snap.MemoryTotal,
			"disk_used_bytes":    snap.DiskUsed,
			"disk_total_bytes":   snap.DiskTotal,
			"load_1":             snap.Load1,
		},
	}

	var resp HeartbeatResponse
	if err := c.doJSON(ctx, http.MethodPost, heartbeatPath, req, &resp); err != nil {
		return nil, err
	}
	return &resp, nil
}

func (c *Client) PollJobs(ctx context.Context) ([]Job, error) {
	var resp JobsResponse
	if err := c.doJSON(ctx, http.MethodGet, jobsPath, nil, &resp); err != nil {
		return nil, err
	}
	return resp.Jobs, nil
}

func (c *Client) ReportJobStatus(ctx context.Context, jobUUID string, update JobStatusUpdate) error {
	path := fmt.Sprintf(jobStatusPath, jobUUID)
	return c.doJSON(ctx, http.MethodPost, path, update, nil)
}

func (c *Client) CompleteJob(ctx context.Context, jobUUID string, result map[string]any, serverStatus string) error {
	return c.ReportJobStatus(ctx, jobUUID, JobStatusUpdate{
		Status:       "completed",
		Progress:     intPtr(100),
		Result:       result,
		ServerStatus: serverStatus,
	})
}

func (c *Client) FailJob(ctx context.Context, jobUUID string, errMsg string) error {
	return c.ReportJobStatus(ctx, jobUUID, JobStatusUpdate{
		Status: "failed",
		Error:  errMsg,
	})
}

func (c *Client) PostEvent(ctx context.Context, serverID uint64, eventType, message string, meta map[string]any) error {
	body := map[string]any{
		"server_id": serverID,
		"type":      eventType,
		"message":   message,
	}
	if meta != nil {
		body["meta"] = meta
	}
	return c.doJSON(ctx, http.MethodPost, eventsPath, body, nil)
}

func (c *Client) PostMetrics(ctx context.Context, meta map[string]any, servers any) error {
	return c.doJSON(ctx, http.MethodPost, metricsPath, map[string]any{
		"meta":    meta,
		"servers": servers,
	}, nil)
}

func (c *Client) doJSON(ctx context.Context, method, path string, body any, out any) error {
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("request serialisieren: %w", err)
		}
		reader = bytes.NewReader(data)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, reader)
	if err != nil {
		return fmt.Errorf("request erstellen: %w", err)
	}

	req.Header.Set("Accept", "application/json")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "gamepanel-agent/1.0")
	c.token.Apply(req)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("request fehlgeschlagen: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return fmt.Errorf("response lesen: %w", err)
	}

	if resp.StatusCode >= 400 {
		return fmt.Errorf("panel antwortete %d: %s", resp.StatusCode, strings.TrimSpace(string(respBody)))
	}

	if out == nil || len(respBody) == 0 {
		return nil
	}

	if err := json.Unmarshal(respBody, out); err != nil {
		return fmt.Errorf("response parsen: %w", err)
	}
	return nil
}

func (c *Client) RunHeartbeatLoop(ctx context.Context, interval time.Duration, collector *metrics.Collector, start time.Time) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	send := func() {
		snap, err := collector.Collect()
		if err != nil {
			return
		}
		_, _ = c.Heartbeat(ctx, snap, time.Since(start))
	}
	send()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			send()
		}
	}
}

func (c *Client) RunJobPollLoop(ctx context.Context, interval time.Duration, handler func(context.Context, Job) error) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			jobs, err := c.PollJobs(ctx)
			if err != nil {
				continue
			}
			for _, job := range jobs {
				if err := handler(ctx, job); err != nil {
					_ = c.FailJob(ctx, job.UUID, err.Error())
					continue
				}
			}
		}
	}
}

func intPtr(v int) *int { return &v }

func runtimeNumCPU() int { return runtime.NumCPU() }
