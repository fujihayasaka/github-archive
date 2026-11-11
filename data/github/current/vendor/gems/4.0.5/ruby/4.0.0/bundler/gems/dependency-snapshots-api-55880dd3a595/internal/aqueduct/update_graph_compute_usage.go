package aqueduct

import (
	"context"
	"regexp"
	"time"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/ecosystems"
	"github.com/github/dependency-snapshots-api/internal/semconv"
	jobsproto "github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const updateGraphMetricsPrefix = "aqueduct.handler.update_graph_compute_usage."

var updateGraphJobEcosystemRegex = regexp.MustCompile(`^update-(.*?)-graph$`)

// HandleUpdateGraphComputeUsageJob records compute usage metrics for update-graph workflows.
// Metrics are emitted only when the Parse Once feature flag is enabled for the repository.
func HandleUpdateGraphComputeUsageJob(
	ctx context.Context,
	_ *config.Config,
	logger log.Logger,
	statter stats.Client,
	job *jobsproto.UpdateGraphComputeUsageJob,
) error {
	logger = logger.WithFields(
		semconv.RepoID(job.GetRepositoryId()),
		semconv.OwnerID(job.GetRepositoryOwnerId()),
		semconv.DynamicWorkflowRunID(job.GetWorkflowRunId()),
		semconv.DynamicWorkflowJobID(job.GetWorkflowJobId()),
	)

	tags := stats.Tags{
		"ecosystem":      updateGraphJobEcosystem(job.GetJobName()).String(),
		"conclusion":     job.GetConclusion().String(),
		"runner_runtime": job.GetRunnerRuntime(),
		"runner_type":    job.GetRunnerType(),
	}

	if job.GetWorkflowRunAttempt() > 1 {
		outcomeTags := mergeTags(tags, stats.Tags{"outcome": "ignored", "ignore_reason": "retry"})
		emitUpdateGraphMetrics(statter, job, outcomeTags)
		logOutcome(logger, "ignored", kvp.String("gh.dgp.dynamic_workflow.ignore_reason", "retry"))
		return nil
	}

	switch job.GetConclusion() {
	case jobsproto.UpdateGraphComputeUsageJob_CONCLUSION_SUCCESS:
		outcomeTags := mergeTags(tags, stats.Tags{"outcome": "success"})
		emitUpdateGraphMetrics(statter, job, outcomeTags)
		logOutcome(logger, "success")
		return nil

	case jobsproto.UpdateGraphComputeUsageJob_CONCLUSION_FAILURE:
		failureReason := "run_dependabot"
		outcomeTags := mergeTags(tags, stats.Tags{
			"outcome":        "failed",
			"failure_reason": failureReason,
		})
		emitUpdateGraphMetrics(statter, job, outcomeTags)
		logOutcome(logger, "failed", kvp.String("gh.dgp.dynamic_workflow.failure_reason", failureReason))
		return nil

	case jobsproto.UpdateGraphComputeUsageJob_CONCLUSION_SKIPPED:
		outcomeTags := mergeTags(tags, stats.Tags{"outcome": "ignored", "ignore_reason": "workflow_skipped"})
		emitUpdateGraphMetrics(statter, job, outcomeTags)
		logOutcome(logger, "ignored", kvp.String("gh.dgp.dynamic_workflow.ignore_reason", "workflow_skipped"))
		return nil

	case jobsproto.UpdateGraphComputeUsageJob_CONCLUSION_CANCELLED:
		outcomeTags := mergeTags(tags, stats.Tags{"outcome": "ignored", "ignore_reason": "workflow_cancelled"})
		emitUpdateGraphMetrics(statter, job, outcomeTags)
		logOutcome(logger, "ignored", kvp.String("gh.dgp.dynamic_workflow.ignore_reason", "workflow_cancelled"))
		return nil

	default:
		failureReason := "unexpected_workflow_conclusion"
		outcomeTags := mergeTags(tags, stats.Tags{
			"outcome":        "failed",
			"failure_reason": failureReason,
		})
		emitUpdateGraphMetrics(statter, job, outcomeTags)
		logOutcome(logger, "failed", kvp.String("gh.dgp.dynamic_workflow.failure_reason", failureReason))
		return nil
	}
}

func emitUpdateGraphMetrics(statter stats.Client, job *jobsproto.UpdateGraphComputeUsageJob, tags stats.Tags) {
	statter.Counter(updateGraphMetricsPrefix+"complete", tags, 1)
	statter.DistributionMs(updateGraphMetricsPrefix+"time_in_queue", tags, durationOrZero(toTime(job.GetQueuedAt()), toTime(job.GetStartedAt())))
	statter.DistributionMs(updateGraphMetricsPrefix+"execution_time", tags, durationOrZero(toTime(job.GetStartedAt()), toTime(job.GetCompletedAt())))
}

func durationOrZero(start time.Time, end time.Time) time.Duration {
	if start.IsZero() || end.IsZero() {
		return 0
	}
	return end.Sub(start)
}

func toTime(ts *timestamppb.Timestamp) time.Time {
	if ts == nil {
		return time.Time{}
	}
	return ts.AsTime()
}

func updateGraphJobEcosystem(jobName string) ecosystems.Ecosystem {
	ecMatches := updateGraphJobEcosystemRegex.FindStringSubmatch(jobName)
	if len(ecMatches) <= 1 {
		return ecosystems.Unknown
	}

	switch ecMatches[1] {
	case "npm_and_yarn":
		return ecosystems.NPM
	case "maven":
		return ecosystems.Maven
	case "gradle":
		return ecosystems.Gradle
	case "go_modules":
		return ecosystems.Golang
	case "nuget":
		return ecosystems.Nuget
	case "pip":
		return ecosystems.PyPi
	default:
		return ecosystems.Unknown
	}
}

func mergeTags(base stats.Tags, extra stats.Tags) stats.Tags {
	merged := stats.Tags{}
	for k, v := range base {
		merged[k] = v
	}
	for k, v := range extra {
		merged[k] = v
	}
	return merged
}

func logOutcome(logger log.Logger, outcome string, extra ...kvp.Field) {
	fields := []kvp.Field{kvp.String("gh.dgp.dynamic_workflow.outcome", outcome)}
	fields = append(fields, extra...)
	logger.WithFields(fields...).Info("update-graph compute usage processed")
}
