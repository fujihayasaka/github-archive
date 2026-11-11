package standardevents

import (
	"context"
	"time"

	standardpb "github.com/github/hydro-schemas-go/hydro/schemas/analytics_pipelines/v0"
	"github.com/github/sweagentd/internal/jobs"
)

// PullRequestStandardEventGenerator generates StandardEvent messages for
// pull request events. Each method takes a Job (for context) and PR-specific
// data, returning a StandardEvent ready for Hydro publishing.
type PullRequestStandardEventGenerator struct{}

// GeneratePullRequestStateChangedStandardEvent creates a StandardEvent for a
// pull_request_state_changed event (e.g. merged, closed).
func (g *PullRequestStandardEventGenerator) GeneratePullRequestStateChangedStandardEvent(
	ctx context.Context,
	job *jobs.Job,
	prState string,
	occurredAt time.Time,
) *standardpb.StandardEvent {
	jobContext := assignmentContextFromJob(job)
	sdkContext := assignmentContextFromContext(ctx, job)
	event := newBaseEvent(
		EventTypePullRequestStateChanged,
		occurredAt,
		job.ActorAnalyticsTrackingID,
		EntityTypeCopilotTrackingID,
		sdkContext,
	)

	setSessionID(event, job.ID)
	setSecondaryEntity(event, formatPullRequestID(job.PullRequestID), EntityTypePullRequestID, jobContext)
	setJobMetadata(event, job)

	event.Metadata["pr_state"] = prState

	return event
}
