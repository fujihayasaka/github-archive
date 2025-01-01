package freno

import (
	"context"
	"time"

	"github.com/github/dependency-snapshots-api/internal/config"
	throttler "github.com/github/go-freno-client"
)

const (
	defaultTimeout = 30 * time.Second
)

type FrenoClient struct {
	Client throttler.Throttler
}

func NewFrenoClient(cfg *config.Config) *FrenoClient {
	client := throttler.DefaultThrottler
	if len(cfg.FrenoAddr) > 0 {
		client = throttler.NewFrenoThrottler(cfg.FrenoAddr, cfg.ServiceName, cfg.FrenoCluster)
	}
	return &FrenoClient{Client: client}
}

func (f *FrenoClient) WaitForReplication(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, defaultTimeout)
	defer cancel()

	return throttler.WaitOnThrottler(ctx, f.Client)
}
