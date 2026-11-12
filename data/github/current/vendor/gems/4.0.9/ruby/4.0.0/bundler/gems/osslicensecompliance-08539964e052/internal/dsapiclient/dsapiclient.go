// Package dsapiclient provides a client for interacting with the Dependency Snapshots API (DS-API).
package dsapiclient

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	ds "github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	twirpAuth "github.com/github/go-twirp/client/auth"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/dependencies"
)

// StatusGetter is a struct that contains the DS-API client
type StatusGetter struct {
	SnapshotsDiffStatusGetter DiffStatusGetter
	Logger                    log.Logger
	Metrics                   stats.Client
}

// DiffStatusGetter is an interface for direct calls to DS API
type DiffStatusGetter interface {
	GetSnapshotDiffStatus(context.Context, *ds.GetSnapshotDiffStatusRequest) (*ds.GetSnapshotDiffStatusResponse, error)
}

// New creates a new StatusGetter for DS API
func New(cfg *config.Config, logger log.Logger, metrics stats.Client) (*StatusGetter, error) {
	logger = logger.Named("diffstatusgetter")
	client := ds.HTTPClient(http.DefaultClient)
	var err error
	if cfg.DependencyGraphHMACSecret != "" {
		client, err = twirpAuth.NewRequestHMACSigner(cfg.DependencyGraphHMACSecret, http.DefaultClient)
		if err != nil {
			return nil, fmt.Errorf("failed to create HMAC auth client: %w", err)
		}
	}
	if cfg.DependencyGraphHMACKey != "" {
		client, err = dependencies.NewRequestHMACClient(cfg.DependencyGraphHMACKey, http.DefaultClient)
		if err != nil {
			return nil, fmt.Errorf("failed to create local HMAC client: %w", err)
		}
	}
	if client == nil {
		return nil, errors.New("no DG HMAC provided, cannot create HTTP Client")
	}

	return &StatusGetter{
		SnapshotsDiffStatusGetter: ds.NewSnapshotsServiceProtobufClient(
			cfg.DependencySnapshotEndpoint,
			client,
		),
		Logger:  logger,
		Metrics: metrics,
	}, nil
}
