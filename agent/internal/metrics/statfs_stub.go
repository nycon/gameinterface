//go:build !linux

package metrics

import "fmt"

type syscallStatfs struct {
	Bsize  int64
	Blocks uint64
	Bfree  uint64
}

func statfs(path string, buf *syscallStatfs) error {
	return fmt.Errorf("disk-metriken nur auf linux verfügbar")
}
