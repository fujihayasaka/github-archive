package eventpublisher

import (
	"context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1/entities"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/semconv"
)

// PublishLicenseCheckProgress publishes a progress event without title (for non-terminal statuses).
func (ep *Publisher) PublishLicenseCheckProgress(ctx context.Context, checkJob *models.CheckJob) {
	data := licenseCheckProgressedEvent{
		CheckJobStatus: checkJob.Status,
		LogMessage:     checkJob.LogMessage(),
		CommitSHA:      checkJob.CommitSHA,
		RepositoryID:   checkJob.RepositoryID,
		ProgressedAt:   time.Now().UTC(),
	}

	_ = ep.publishLicenseCheckProgressedEvent(data)
}

// PublishLicenseCheckResult publishes a progress event with title (for terminal statuses).
func (ep *Publisher) PublishLicenseCheckResult(ctx context.Context, checkJob *models.CheckJob, alertCount int) {
	data := licenseCheckProgressedEvent{
		CheckJobStatus: checkJob.Status,
		LogMessage:     checkJob.LogMessage(),
		CommitSHA:      checkJob.CommitSHA,
		RepositoryID:   checkJob.RepositoryID,
		ProgressedAt:   time.Now().UTC(),
		Title:          checkJob.Title(alertCount),
	}

	_ = ep.publishLicenseCheckProgressedEvent(data)
}

// PublishLicenseCheckPass publishes a pass event (when check passes after alert dismissal).
// This is used by remediation when all alerts are dismissed.
func (ep *Publisher) PublishLicenseCheckPass(ctx context.Context, commitSHA string, repositoryID uint64) {
	data := licenseCheckProgressedEvent{
		CommitSHA:      commitSHA,
		RepositoryID:   repositoryID,
		CheckJobStatus: models.Pass,
		LogMessage:     models.CheckProgressedLogMessagePass,
		Title:          models.CheckProgressedTitlePass,
		ProgressedAt:   time.Now().UTC(),
	}

	_ = ep.publishLicenseCheckProgressedEvent(data)
}

// PublishLicenseCheckError publishes an error event with a sanitized error message.
// This takes raw commitSHA and repositoryID because it may be called when checkJob is nil.
func (ep *Publisher) PublishLicenseCheckError(ctx context.Context, commitSHA string, repositoryID uint64, sanitizedError string) {
	data := licenseCheckProgressedEvent{
		CommitSHA:      commitSHA,
		RepositoryID:   repositoryID,
		CheckJobStatus: models.Error,
		LogMessage:     models.CheckProgressedLogMessageErrorPrefix + sanitizedError,
		Title:          models.CheckProgressedTitleError,
		ProgressedAt:   time.Now().UTC(),
	}

	_ = ep.publishLicenseCheckProgressedEvent(data)
}

// licenseCheckProgressedEvent contains the data for a license check progress event.
type licenseCheckProgressedEvent struct {
	CommitSHA      string
	RepositoryID   uint64
	CheckJobStatus models.CheckStatus
	LogMessage     string
	ProgressedAt   time.Time
	Title          string
}

func (e licenseCheckProgressedEvent) protoStatus() entities.CheckJobStatus {
	switch e.CheckJobStatus {
	case models.Starting:
		return entities.CheckJobStatus_CHECK_JOB_STATUS_STARTING
	case models.Waiting:
		return entities.CheckJobStatus_CHECK_JOB_STATUS_WAITING
	case models.Running:
		return entities.CheckJobStatus_CHECK_JOB_STATUS_RUNNING
	case models.Pass:
		return entities.CheckJobStatus_CHECK_JOB_STATUS_PASS
	case models.Fail:
		return entities.CheckJobStatus_CHECK_JOB_STATUS_FAIL
	case models.Error:
		return entities.CheckJobStatus_CHECK_JOB_STATUS_ERROR
	default:
		return entities.CheckJobStatus_CHECK_JOB_STATUS_UNKNOWN
	}
}

// publishLicenseCheckProgressedEvent publishes a PullRequestLicenseCheckProgressed event to Hydro.
func (ep *Publisher) publishLicenseCheckProgressedEvent(event licenseCheckProgressedEvent) error {
	var titleWrapper *wrapperspb.StringValue
	if event.Title != "" {
		titleWrapper = &wrapperspb.StringValue{Value: event.Title}
	}

	hydroEvent := &dependencygraphv1.PullRequestLicenseCheckProgressed{
		CommitSha:      event.CommitSHA,
		RepositoryId:   int64(event.RepositoryID), // #nosec G115 -- RepositoryID conversion is safe within expected range
		CheckJobStatus: event.protoStatus(),
		LogMessage:     event.LogMessage,
		ProgressedAt:   timestamppb.New(event.ProgressedAt),
		Title:          titleWrapper,
	}

	checkJobStatusStr := hydroEvent.CheckJobStatus.String()
	tags := stats.Tags{"event": "PullRequestLicenseCheckProgressed", "check_job_status": checkJobStatusStr}
	err := ep.hydroPublisher.Publish(hydroEvent)
	if err != nil {
		ep.logger.WithError(err).Error("failed to publish PullRequestLicenseCheckProgressed event")
		ep.metrics.Counter("eventpublisher.publish.failure", tags, 1)
		return fmt.Errorf("failed to publish license check progressed event: %w", err)
	}

	ep.metrics.Counter("eventpublisher.publish.success", tags, 1)

	ep.logger.Info("license check progressed event published",
		kvp.String("check_job_status", checkJobStatusStr),
		semconv.RepositoryID(event.RepositoryID),
		semconv.CommitSHA(event.CommitSHA),
	)

	return nil
}
