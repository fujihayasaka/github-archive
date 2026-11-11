package hydro

import (
	"context"
	"fmt"

	"github.com/github/dependency-snapshots-api/internal/config"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"

	"github.com/pkg/errors"
	"google.golang.org/protobuf/proto"
)

// Publisher interface for publishing Hydro messages
type Publisher interface {
	Publish(ctx context.Context, msg proto.Message) error
	Close() error
}

// HydroPublisher is a wrapper around the Hydro publisher that provides methods to send hydro messages
type HydroPublisher struct {
	publisher *hydro.Publisher
}

// NewPublisher creates a new wrapper around the Hydro publisher.
// It refuses to create a real publisher in GHES (enterprise) environments;
// callers should use NewNoopPublisher instead.
func NewPublisher(cfg *config.Config, logger log.Logger, statter stats.Client) (*HydroPublisher, error) {
	if cfg.Enterprise {
		return nil, fmt.Errorf("hydro publisher is not supported in GHES; use NewNoopPublisher")
	}

	kafkaConfig, err := NewKafkaPublisherConfig(cfg, logger, statter)
	if err != nil {
		return nil, errors.Wrap(err, "creating Kafka config")
	}

	sink, err := hydro.NewKafkaSink(*kafkaConfig)
	if err != nil {
		return nil, errors.Wrap(err, "creating Kafka sink")
	}

	publisher, err := hydro.NewPublisher(sink,
		// Use V2 topic format for consistency with DGP
		hydro.WithTopicFormat(hydro.TopicFormatV2),
	)
	if err != nil {
		return nil, errors.Wrap(err, "creating Hydro publisher")
	}

	return &HydroPublisher{
		publisher: publisher,
	}, nil
}

// Publish sets custom headers for multi-tenancy and publishes the message
func (p *HydroPublisher) Publish(ctx context.Context, msg proto.Message) error {
	// Multi-Tenancy in Proxima requires using a "X-GitHub-Tenant" or "X-GitHub-Tenant-ID" request header across services
	customHeaders := map[string]string{}
	if slug := tenant.GetTenant(ctx); slug != "" {
		customHeaders[headers.Tenant] = slug
	}
	if tenantID := tenant.GetTenantID(ctx); tenantID != "" {
		customHeaders[headers.TenantID] = tenantID
	}

	return p.publisher.Publish(msg, hydro.WithCustomHeaders(customHeaders))
}

// Close closes the underlying publisher
func (p *HydroPublisher) Close() error {
	return p.publisher.Close()
}

// NoopPublisher is a no-operation implementation of the Publisher interface.
// It can be used in GHES until dependabot snapshot submission and publishing is supported.
type NoopPublisher struct{}

// NewNoopPublisher creates a new noop publisher
func NewNoopPublisher() *NoopPublisher {
	return &NoopPublisher{}
}

// Publish sets custom headers for multi-tenancy and publishes the message
func (p *NoopPublisher) Publish(ctx context.Context, msg proto.Message) error {
	return nil
}

// Close closes the underlying publisher
func (p *NoopPublisher) Close() error {
	return nil
}
