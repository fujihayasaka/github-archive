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
	"google.golang.org/protobuf/types/known/wrapperspb"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1/entities"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/semconv"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

// PolicyAction represents the type of change made to a policy.
type PolicyAction = dependencygraphv1.LicensePolicyChanged_PolicyAction

// PolicyAction constants for policy change events.
const (
	PolicyActionPolicyCreated           = dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_POLICY_CREATED
	PolicyActionLicenseAdded            = dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_LICENSE_ADDED
	PolicyActionLicenseRemoved          = dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_LICENSE_REMOVED
	PolicyActionPackageExemptionAdded   = dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_PACKAGE_EXEMPTION_ADDED
	PolicyActionPackageExemptionRemoved = dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_PACKAGE_EXEMPTION_REMOVED
)

// PolicyLevel represents the level at which a policy exists.
type PolicyLevel = dependencygraphv1.LicensePolicyChanged_PolicyLevel

// PolicyLevel constants for policy levels.
const (
	PolicyLevelRepository   = dependencygraphv1.LicensePolicyChanged_POLICY_LEVEL_REPOSITORY
	PolicyLevelOrganization = dependencygraphv1.LicensePolicyChanged_POLICY_LEVEL_ORGANIZATION
	PolicyLevelEnterprise   = dependencygraphv1.LicensePolicyChanged_POLICY_LEVEL_ENTERPRISE
)

// PolicyChangedEvent represents a change to a license policy.
type PolicyChangedEvent struct {
	Action               PolicyAction
	Level                PolicyLevel
	EntityID             uint64
	DistributionContexts []string
}

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
		err := ep.hydroPublisher.Close()
		if err != nil {
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
			EnterpriseId:          wrapEnterpriseID(alert.EnterpriseID),
			PullRequestNumber:     int32(pullRequestNumber), // #nosec G115 -- PullRequestNumber conversion is safe within expected range
			PullRequestId:         int64(pullRequestID),     // #nosec G115 -- PullRequestID conversion is safe within expected range
			ManifestName:          alert.ManifestName,
			PackageManager:        ModelToProtoPackageManager(alert.PackageEcosystem),
			PackageName:           alert.PackageName,
			PackageVersion:        alert.PackageVersion,
			SpdxLicenseExpression: alert.SPDXLicenseExpression,
			ClosureReason:         modelToProtoClosureReason(alert.ClosureReason),
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
	err := ep.hydroPublisher.Publish(event)
	if err != nil {
		ep.logger.WithError(err).Error("failed to publish PullRequestLicenseCheckComplete event")
		ep.metrics.Counter("eventpublisher.publish.failure", tags, 1)
		return fmt.Errorf("failed to publish event: %w", err)
	}

	ep.metrics.Counter("eventpublisher.publish.success", tags, 1)

	ep.logger.Info("successfully published PullRequestLicenseCheckComplete event",
		semconv.RepositoryID(repositoryID),
		semconv.PullRequestID(pullRequestID),
		semconv.PullRequestNumber(pullRequestNumber),
		kvp.Int("open_alerts_count", len(protoAlerts)),
	)

	return nil
}

// PublishAlertStatusChanged publishes a LicenseComplianceAlertStatusChanged event to Hydro
// when an alert's status changes.
func (ep *Publisher) PublishAlertStatusChanged(
	ctx context.Context,
	alert *models.Alert,
	previousStatus models.AlertStatus,
	pullRequestID uint64,
	opts ...AlertStatusChangedOption,
) error {
	var options alertStatusChangedOptions
	for _, opt := range opts {
		if opt != nil {
			opt(&options)
		}
	}

	var prNumber int32
	if alert.PullRequestNumber != nil {
		prNumber = int32(*alert.PullRequestNumber) // #nosec G115
	}

	protoAlert := &entities.LicenseComplianceAlert{
		AlertId:               int64(alert.ID),     // #nosec G115
		AlertNumber:           int32(alert.Number), // #nosec G115
		Status:                modelToProtoAlertStatus(alert.Status),
		CreatedAt:             timestamppb.New(alert.CreatedAt),
		RepositoryId:          int64(alert.RepositoryID),   // #nosec G115
		OrganizationId:        int64(alert.OrganizationID), // #nosec G115
		EnterpriseId:          wrapEnterpriseID(alert.EnterpriseID),
		PullRequestNumber:     prNumber,
		PullRequestId:         int64(pullRequestID), // #nosec G115
		ManifestName:          alert.ManifestName,
		PackageManager:        ModelToProtoPackageManager(alert.PackageEcosystem),
		PackageName:           alert.PackageName,
		PackageVersion:        alert.PackageVersion,
		SpdxLicenseExpression: alert.SPDXLicenseExpression,
		ClosureReason:         modelToProtoClosureReason(alert.ClosureReason),
	}

	var uid int64
	if options.userID != nil {
		uid = int64(*options.userID) // #nosec G115
	}

	// Closure user is optional and only set when provided.
	var closureUIDWrapper *wrapperspb.Int64Value
	if options.closureUserID != nil {
		closureUIDWrapper = wrapperspb.Int64(int64(*options.closureUserID)) // #nosec G115
	}

	var commentWrapper *wrapperspb.StringValue
	if options.comment != nil && *options.comment != "" {
		commentWrapper = &wrapperspb.StringValue{Value: *options.comment}
	}

	event := &dependencygraphv1.LicenseComplianceAlertStatusChanged{
		Alert:          protoAlert,
		PreviousStatus: modelToProtoAlertStatus(previousStatus),
		UserId:         uid,
		Comment:        commentWrapper,
		ClosureUserId:  closureUIDWrapper,
	}

	tags := stats.Tags{"event": "LicenseComplianceAlertStatusChanged"}
	err := ep.hydroPublisher.Publish(event)
	if err != nil {
		ep.logger.WithError(err).Error("failed to publish LicenseComplianceAlertStatusChanged event")
		ep.metrics.Counter("eventpublisher.publish.failure", tags, 1)
		return fmt.Errorf("failed to publish event: %w", err)
	}

	ep.metrics.Counter("eventpublisher.publish.success", tags, 1)

	ep.logger.Info("successfully published LicenseComplianceAlertStatusChanged event",
		kvp.Uint64("gh.osslicensecompliance.alert_id", alert.ID),
		semconv.AlertNumber(alert.Number),
		semconv.PullRequestID(pullRequestID),
		semconv.PullRequestNumber(uint32(prNumber)), // #nosec G115 -- PR numbers are always non-negative
		semconv.RepositoryID(alert.RepositoryID),
	)

	return nil
}

// PublishPolicyChanged publishes a policy change event to Hydro.
func (ep *Publisher) PublishPolicyChanged(ctx context.Context, event PolicyChangedEvent) error {
	hydroEvent := &dependencygraphv1.LicensePolicyChanged{
		Action:               event.Action,
		Level:                event.Level,
		EntityId:             int64(event.EntityID), // #nosec G115 -- entity IDs are always non-negative
		DistributionContexts: event.DistributionContexts,
	}

	tags := stats.Tags{"event": "LicensePolicyChanged", "action": event.Action.String(), "level": event.Level.String()}
	err := ep.hydroPublisher.Publish(hydroEvent)
	if err != nil {
		ep.logger.WithError(err).Error("failed to publish LicensePolicyChanged event")
		ep.metrics.Counter("eventpublisher.publish.failure", tags, 1)
		return fmt.Errorf("failed to publish policy changed event: %w", err)
	}

	ep.metrics.Counter("eventpublisher.publish.success", tags, 1)

	ep.logger.Info("policy changed event published",
		kvp.String("action", event.Action.String()),
		kvp.String("level", event.Level.String()),
		kvp.Uint64("entity_id", event.EntityID),
	)

	return nil
}

// modelToProtoClosureReason converts a model ClosureReason to a proto ClosureReason.
func modelToProtoClosureReason(reason *string) entities.ClosureReason {
	if reason == nil {
		return entities.ClosureReason_CLOSURE_REASON_UNKNOWN
	}
	switch *reason {
	case models.ClosureReasonAmendment:
		return entities.ClosureReason_CLOSURE_REASON_AMENDMENT
	case models.ClosureReasonPrivatePackage:
		return entities.ClosureReason_CLOSURE_REASON_PRIVATE_PACKAGE
	case models.ClosureReasonInaccurateLicense:
		return entities.ClosureReason_CLOSURE_REASON_INACCURATE_LICENSE
	case models.ClosureReasonPolicyEdited:
		return entities.ClosureReason_CLOSURE_REASON_POLICY_EDITED
	case models.ClosureReasonFixed:
		return entities.ClosureReason_CLOSURE_REASON_FIXED
	default:
		return entities.ClosureReason_CLOSURE_REASON_UNKNOWN
	}
}

func modelToProtoAlertStatus(status models.AlertStatus) entities.AlertStatus {
	switch status {
	case models.AlertStatusOpen:
		return entities.AlertStatus_ALERT_STATUS_OPEN
	case models.AlertStatusReviewRequested:
		return entities.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED
	case models.AlertStatusReviewDenied:
		return entities.AlertStatus_ALERT_STATUS_REVIEW_DENIED
	case models.AlertStatusClosed:
		return entities.AlertStatus_ALERT_STATUS_CLOSED
	default:
		return entities.AlertStatus_ALERT_STATUS_UNKNOWN
	}
}

func wrapEnterpriseID(enterpriseID *uint64) *wrapperspb.Int64Value {
	if enterpriseID == nil {
		return nil
	}
	return &wrapperspb.Int64Value{Value: int64(*enterpriseID)} // #nosec G115
}

// ModelToProtoPackageManager converts an OLC PackageManager enum to a Hydro PackageManager enum.
// The two enums have identical numeric values so a direct cast is safe.
func ModelToProtoPackageManager(pm proto.PackageManager) entities.PackageManager {
	return entities.PackageManager(pm)
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
