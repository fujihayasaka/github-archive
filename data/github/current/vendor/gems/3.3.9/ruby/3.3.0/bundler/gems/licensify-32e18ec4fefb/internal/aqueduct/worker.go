package aqueduct

import (
	"fmt"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

// NewWorker creates a new aqueduct worker.
func NewWorker(client aqueduct.Client, handler aqueduct.JobHandler, app string, queues []string, logger log.Logger, statter stats.Client) (*aqueduct.Worker, error) {
	logger.Info("Initializing aqueduct worker")

	statsConfig, err := aqueduct.NewStatsConfig(
		aqueduct.WithStatsClient(statter),
	)
	if err != nil {
		return nil, fmt.Errorf("could not create stats config for aqueduct worker: %w", err)
	}

	const heartBeatInterval = 5 * time.Second
	heartBeatConfig, err := aqueduct.NewHeartbeatConfig(
		aqueduct.WithHeartbeatInterval(heartBeatInterval),
	)
	if err != nil {
		return nil, fmt.Errorf("could not create heartbeat config for aqueduct worker: %w", err)
	}

	worker, err := aqueduct.NewWorker(
		client,
		app,
		queues,
		handler,
		aqueduct.WithWorkerStats(statsConfig),
		aqueduct.WithJobErrorPolicy(aqueduct.IgnoreJobErr), // not sending a Failure ack will trigger a retry
		aqueduct.WithHeartbeatConfig(heartBeatConfig),
	)
	if err != nil {
		return nil, fmt.Errorf("could not create aqueduct worker: %w", err)
	}

	return worker, nil
}
