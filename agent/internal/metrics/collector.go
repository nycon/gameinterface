package metrics

import (
	"bufio"
	"fmt"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"
)

type Snapshot struct {
	Timestamp   time.Time `json:"timestamp"`
	CPUPercent  float64   `json:"cpu_percent"`
	MemoryUsed  uint64    `json:"memory_used_bytes"`
	MemoryTotal uint64    `json:"memory_total_bytes"`
	Load1       float64   `json:"load_1"`
	Load5       float64   `json:"load_5"`
	Load15      float64   `json:"load_15"`
	DiskUsed    uint64    `json:"disk_used_bytes"`
	DiskTotal   uint64    `json:"disk_total_bytes"`
	Goroutines  int       `json:"goroutines"`
}

type Collector struct {
	lastCPU idleSample
}

type idleSample struct {
	total uint64
	idle  uint64
	time  time.Time
}

func NewCollector() *Collector {
	return &Collector{}
}

func (c *Collector) Collect() (Snapshot, error) {
	snap := Snapshot{
		Timestamp:  time.Now().UTC(),
		Goroutines: runtime.NumGoroutine(),
	}

	if cpu, err := c.cpuPercent(); err == nil {
		snap.CPUPercent = cpu
	}

	if used, total, err := readMemInfo(); err == nil {
		snap.MemoryUsed = used
		snap.MemoryTotal = total
	}

	if l1, l5, l15, err := readLoadAvg(); err == nil {
		snap.Load1, snap.Load5, snap.Load15 = l1, l5, l15
	}

	if used, total, err := readDiskUsage("/"); err == nil {
		snap.DiskUsed = used
		snap.DiskTotal = total
	}

	return snap, nil
}

func (c *Collector) cpuPercent() (float64, error) {
	total, idle, err := readProcStat()
	if err != nil {
		return 0, err
	}

	now := time.Now()
	if !c.lastCPU.time.IsZero() {
		totalDelta := float64(total - c.lastCPU.total)
		idleDelta := float64(idle - c.lastCPU.idle)
		if totalDelta > 0 {
			usage := (1.0 - idleDelta/totalDelta) * 100.0
			c.lastCPU = idleSample{total: total, idle: idle, time: now}
			return usage, nil
		}
	}

	c.lastCPU = idleSample{total: total, idle: idle, time: now}
	return 0, nil
}

func readProcStat() (total, idle uint64, err error) {
	data, err := os.ReadFile("/proc/stat")
	if err != nil {
		return 0, 0, err
	}
	line := strings.Split(string(data), "\n")[0]
	fields := strings.Fields(line)
	if len(fields) < 5 || fields[0] != "cpu" {
		return 0, 0, fmt.Errorf("ungültige /proc/stat zeile")
	}

	for i := 1; i < len(fields); i++ {
		v, err := strconv.ParseUint(fields[i], 10, 64)
		if err != nil {
			return 0, 0, err
		}
		total += v
		if i == 4 {
			idle = v
		}
	}
	return total, idle, nil
}

func readMemInfo() (used, total uint64, err error) {
	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0, 0, err
	}
	defer f.Close()

	var memTotal, memAvailable uint64
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case strings.HasPrefix(line, "MemTotal:"):
			memTotal = parseKB(line)
		case strings.HasPrefix(line, "MemAvailable:"):
			memAvailable = parseKB(line)
		}
	}
	if err := scanner.Err(); err != nil {
		return 0, 0, err
	}
	if memTotal == 0 {
		return 0, 0, fmt.Errorf("memtotal nicht gefunden")
	}
	if memAvailable > memTotal {
		memAvailable = 0
	}
	return (memTotal - memAvailable) * 1024, memTotal * 1024, nil
}

func parseKB(line string) uint64 {
	fields := strings.Fields(line)
	if len(fields) < 2 {
		return 0
	}
	v, _ := strconv.ParseUint(fields[1], 10, 64)
	return v
}

func readLoadAvg() (l1, l5, l15 float64, err error) {
	data, err := os.ReadFile("/proc/loadavg")
	if err != nil {
		return 0, 0, 0, err
	}
	fields := strings.Fields(string(data))
	if len(fields) < 3 {
		return 0, 0, 0, fmt.Errorf("ungültige loadavg")
	}
	l1, _ = strconv.ParseFloat(fields[0], 64)
	l5, _ = strconv.ParseFloat(fields[1], 64)
	l15, _ = strconv.ParseFloat(fields[2], 64)
	return l1, l5, l15, nil
}

func readDiskUsage(path string) (used, total uint64, err error) {
	var stat syscallStatfs
	if err := statfs(path, &stat); err != nil {
		return 0, 0, err
	}
	blockSize := uint64(stat.Bsize)
	total = stat.Blocks * blockSize
	free := stat.Bfree * blockSize
	if total < free {
		return 0, total, nil
	}
	return total - free, total, nil
}
