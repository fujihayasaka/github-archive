package jobs

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/observability"
)

// StatJobTransition records a job state transition metric.
func StatJobTransition(ctx context.Context, obsv observability.Exporters, tags stats.Tags, from, to JobStatus) {
	tags = tags.Merge(stats.Tags{
		"from": string(from),
		"to":   string(to),
	})
	obsv.Statter.Counter("jobs.state_transition", tags, 1)
}

// SLOFailureType classifies job failures for SLO tracking purposes.
type SLOFailureType string

const (
	// SLOFailureTypeExpected indicates a failure that is expected and should not
	// count against the SLO (e.g., user cancellation, payment required).
	SLOFailureTypeExpected SLOFailureType = "expected"

	// SLOFailureTypeUnexpected indicates a failure that is unexpected and should
	// count against the SLO (e.g., internal errors, infrastructure issues).
	SLOFailureTypeUnexpected SLOFailureType = "unexpected"
)

// excludeFromSLOErrorCodes defines which error codes should be excluded from SLO
// calculations. These are typically user-controlled failures or expected errors
// that should not count against the service's reliability.
var excludeFromSLOErrorCodes = map[string]bool{
	// User-initiated actions
	joberrors.ErrUserCancelled.Code: true,

	// Payment/subscription issues (customer responsibility)
	joberrors.ErrActionsBillingLocked.Code:    true,
	joberrors.ErrCAPICustomerNotSelected.Code: true,
	joberrors.ErrCAPIPaymentRequired.Code:     true,
	"quota_exceeded":                          true, // CAPI quota exceeded (not in joberrors)

	// Rate limiting
	joberrors.ErrCAPIRateLimited.Code:   true,
	joberrors.ErrRateLimitExceeded.Code: true,

	// User configuration issues
	joberrors.ErrInvalidCustomAgentConfig.Code: true,
	joberrors.ErrInsufficientPermissions.Code:  true,
	joberrors.ErrPullRequestClosed.Code:        true,
	joberrors.ErrRulesViolation.Code:           true,
	joberrors.ErrActionsNotSupported.Code:      true,
	joberrors.ErrActionsSetupSteps.Code:        true,
	joberrors.ErrActionsOutOfDiskSpace.Code:    true,
}

// ClassifyJobFailure determines whether a job failure should be classified as
// "expected" (not counting against SLO) or "unexpected" (counting against SLO).
func ClassifyJobFailure(job *Job) SLOFailureType {
	if job.Error == nil {
		return SLOFailureTypeUnexpected
	}

	if excludeFromSLOErrorCodes[job.Error.ResponseStatusCode] {
		return SLOFailureTypeExpected
	}

	return SLOFailureTypeUnexpected
}

// StatJobCompletionSLO emits a counter metric for tracking job completion success rate SLO.
// This metric is emitted for all terminal job states and includes tags for:
// - status: the final job status (completed, failed, cancelled, timed_out)
// - slo_result: "success" for completed/cancelled jobs, "failure" for failed/timed_out
// - failure_type: "expected" or "unexpected" (only present for failure outcomes)
// - error_service: the service that caused the error (only present for failures with errors)
// - error_code: the error code (only present for failures with errors)
//
// Additionally, a log entry is emitted with high-cardinality data for detailed investigation.
func StatJobCompletionSLO(ctx context.Context, obsv observability.Exporters, baseTags stats.Tags, job *Job) {
	if !job.Status.IsTerminal() {
		return
	}

	tags := baseTags.Merge(stats.Tags{
		"status": string(job.Status),
	})

	// Completed and cancelled jobs are treated as success for SLO purposes
	if job.Status == JobStatusCompleted || job.Status == JobStatusCancelled {
		tags["slo_result"] = "success"
	} else {
		tags["slo_result"] = "failure"
		tags["failure_type"] = string(ClassifyJobFailure(job))

		if job.Error == nil {
			obsv.LoggerWithTelemetry(ctx).Warn("job failed without error details",
				kvp.String("job_id", job.ID),
				kvp.String("status", string(job.Status)))
		}

		if job.Error != nil && job.Error.Service != "" {
			tags["error_service"] = job.Error.Service
		}
		if job.Error != nil && job.Error.ResponseStatusCode != "" {
			tags["error_code"] = job.Error.ResponseStatusCode
		}

		// Log jobs with incomplete error classification
		if job.Error != nil && job.Error.Service == "" && job.Error.ResponseStatusCode == "" {
			obsv.LoggerWithTelemetry(ctx).Warn("job has error with missing classification",
				kvp.String("job_id", job.ID),
				kvp.String("error_message", job.Error.Message))
		}
	}

	obsv.Statter.Counter("jobs.completion", tags, 1)

	// Also log to Splunk for high-cardinality analysis
	logFields := make([]kvp.Field, 0)
	for k, v := range tags {
		logFields = append(logFields, kvp.String(k, v))
	}
	if job.Error != nil && job.Error.Message != "" {
		logFields = append(logFields, kvp.String("error_message", job.Error.Message))
	}
	obsv.LoggerWithTelemetry(ctx).Info("job completion", logFields...)
}
