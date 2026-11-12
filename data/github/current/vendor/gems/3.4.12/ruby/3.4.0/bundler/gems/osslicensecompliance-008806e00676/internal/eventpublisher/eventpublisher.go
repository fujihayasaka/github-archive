// Package eventpublisher provides event publishing capabilities for the OSS License Compliance service.
package eventpublisher

import (
	"context"
	"fmt"
	stdlog "log"
	"os"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/types/known/timestamppb"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1/entities"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/models"
)

// Publisher encapsulates the Hydro publisher for publishing OSS License Compliance events.
type Publisher struct {
	hydroPublisher *hydro.Publisher
	logger         log.Logger
	metrics        stats.Client
}

// New creates a new EventPublisher with a production-ready Hydro publisher.
func New(cfg *config.Config, logger log.Logger, statsClient stats.Client) (*Publisher, error) {
	hydroPublisher, err := newHydroPublisher(cfg, logger, statsClient)
	if err != nil {
		return nil, fmt.Errorf("failed to create hydro publisher: %w", err)
	}

	return &Publisher{
		hydroPublisher: hydroPublisher,
		logger:         logger.Named("eventpublisher"),
		metrics:        statsClient,
	}, nil
}

// NullOption defines functional options for NewNull.
type NullOption func(*Publisher)

// WithPublisher allows injection of a custom Hydro publisher mainly for testing.
func WithPublisher(publisher *hydro.Publisher) NullOption {
	return func(p *Publisher) {
		p.hydroPublisher = publisher
	}
}

// NewNull creates a new EventPublisher with a log-based publisher for development/testing.
func NewNull(logger log.Logger, statsClient stats.Client, opts ...NullOption) (*Publisher, error) {
	ep := &Publisher{
		logger:  logger.Named("eventpublisher"),
		metrics: statsClient,
	}

	for _, opt := range opts {
		opt(ep)
	}

	if ep.hydroPublisher == nil {
		hydroPublisher, err := newNullHydroPublisher(logger, statsClient)
		if err != nil {
			return nil, fmt.Errorf("failed to create null hydro publisher: %w", err)
		}
		ep.hydroPublisher = hydroPublisher
	}

	return ep, nil
}

// Close closes the EventPublisher and its underlying Hydro publisher.
func (ep *Publisher) Close() error {
	if ep.hydroPublisher != nil {
		if err := ep.hydroPublisher.Close(); err != nil {
			return fmt.Errorf("failed to close hydro publisher: %w", err)
		}
	}
	return nil
}

// PublishPRLicenseCheckCompleteEvent publishes a PullRequestLicenseCheckComplete event to Hydro
// when a license compliance check is completed for a pull request.
func (ep *Publisher) PublishPRLicenseCheckCompleteEvent(
	ctx context.Context,
	repositoryID,
	pullRequestID uint64,
	pullRequestNumber uint32,
	commitSHA string,
	baseSHA string,
	alerts []*models.Alert,
	remediationGuidance string,
) error {
	// Convert models.Alert to proto LicenseComplianceAlert
	protoAlerts := make([]*entities.LicenseComplianceAlert, 0, len(alerts))
	for _, alert := range alerts {
		if alert == nil {
			continue
		}

		protoAlert := &entities.LicenseComplianceAlert{
			AlertId:               int64(alert.ID),     // #nosec G115 -- ID conversion is safe within expected range
			AlertNumber:           int32(alert.Number), // #nosec G115 -- Number conversion is safe within expected range
			CreatedAt:             timestamppb.New(alert.CreatedAt),
			RepositoryId:          int64(alert.RepositoryID),   // #nosec G115 -- RepositoryID conversion is safe within expected range
			OrganizationId:        int64(alert.OrganizationID), // #nosec G115 -- OrganizationID conversion is safe within expected range
			PullRequestNumber:     int32(pullRequestNumber),    // #nosec G115 -- PullRequestNumber conversion is safe within expected range
			PullRequestId:         int64(pullRequestID),        // #nosec G115 -- PullRequestID conversion is safe within expected range
			ManifestName:          alert.ManifestName,
			PackageName:           alert.PackageName,
			PackageVersion:        alert.PackageVersion,
			SpdxLicenseExpression: alert.SPDXLicenseExpression,
		}
		protoAlerts = append(protoAlerts, protoAlert)
	}

	event := &dependencygraphv1.PullRequestLicenseCheckComplete{
		PullRequestNumber:   int32(pullRequestNumber), // #nosec G115 -- PullRequestNumber conversion is safe within expected range
		PullRequestId:       int64(pullRequestID),     // #nosec G115 -- PullRequestID conversion is safe within expected range
		RepositoryId:        int64(repositoryID),      // #nosec G115 -- RepositoryID conversion is safe within expected range
		CommitSha:           commitSHA,
		BaseSha:             baseSHA,
		OpenLicenseAlerts:   protoAlerts,
		RemediationGuidance: remediationGuidance,
	}

	tags := stats.Tags{"event": "PullRequestLicenseCheckComplete"}
	if err := ep.hydroPublisher.Publish(event); err != nil {
		ep.logger.WithError(err).Error("failed to publish PullRequestLicenseCheckComplete event")
		ep.metrics.Counter("eventpublisher.publish.failure", tags, 1)
		return fmt.Errorf("failed to publish event: %w", err)
	}

	ep.metrics.Counter("eventpublisher.publish.success", tags, 1)

	ep.logger.Info("successfully published PullRequestLicenseCheckComplete event",
		kvp.Uint64("gh.osslicensecompliance.repository_id", repositoryID),
		kvp.Uint64("gh.osslicensecompliance.pull_request_id", pullRequestID),
		kvp.Uint32("gh.osslicensecompliance.pull_request_number", pullRequestNumber),
		kvp.Int("open_alerts_count", len(protoAlerts)),
	)

	return nil
}

// newHydroPublisher creates a Hydro publisher configured for production use.
func newHydroPublisher(cfg *config.Config, logger log.Logger, statsClient stats.Client) (*hydro.Publisher, error) {
	kafkaCfg, err := cfg.NewKafkaConfig(logger, statsClient)
	if err != nil {
		return nil, fmt.Errorf("failed to create hydro kafka config: %w", err)
	}

	sink, err := hydro.NewKafkaSink(*kafkaCfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create hydro kafka sink: %w", err)
	}

	publisher, err := hydro.NewPublisher(sink,
		hydro.WithPublisherStats(statsClient),
		hydro.WithTopicFormat(hydro.TopicFormatV2), // Use modern topic format
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create hydro publisher: %w", err)
	}

	logger.Info("Hydro publisher initialized successfully")
	return publisher, nil
}

// newNullHydroPublisher creates a log-based Hydro publisher for development/testing.
func newNullHydroPublisher(logger log.Logger, statsClient stats.Client) (*hydro.Publisher, error) {
	// Create a standard logger for the log sink
	stdLogger := stdlog.New(os.Stdout, "hydro: ", stdlog.LstdFlags)
	logSink := hydro.NewLogSink(stdLogger)

	// Create publisher with log sink
	publisher, err := hydro.NewPublisher(logSink,
		hydro.WithPublisherStats(statsClient),
		hydro.WithTopicFormat(hydro.TopicFormatV2),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create null hydro publisher: %w", err)
	}

	logger.Info("Null Hydro publisher initialized successfully")
	return publisher, nil
}
