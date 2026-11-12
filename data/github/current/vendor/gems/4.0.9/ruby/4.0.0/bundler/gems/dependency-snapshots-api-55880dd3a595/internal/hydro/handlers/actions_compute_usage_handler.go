package handlers

import (
	"context"
	"fmt"
	"strings"

	actionsv0 "github.com/github/dependency-snapshots-api/hydro/schemas/github/actions/v0"
	"github.com/github/dependency-snapshots-api/internal/aqueduct"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/dependency-snapshots-api/internal/semconv"
	"github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	hydroclient "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/proto"
)

// compile-time assertion that ActionsComputeUsageHandler implements hydro.EnvelopeHandler
var _ hydro.EnvelopeHandler = &ActionsComputeUsageHandler{}

type ActionsComputeUsageHandler struct {
	config   *config.Config
	logger   log.Logger
	statter  stats.Client
	enqueuer aqueduct.Enqueuer
}

func NewActionsComputeUsageHandler(
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
	enqueuer aqueduct.Enqueuer,
) *ActionsComputeUsageHandler {
	return &ActionsComputeUsageHandler{
		config:   cfg,
		logger:   logger,
		statter:  statter,
		enqueuer: enqueuer,
	}
}

const computeUsageStatsPrefix = "hydro.consumer.compute_usage."

func (h *ActionsComputeUsageHandler) HandleEnvelope(ctx context.Context, envelope *hydroclient.Envelope) error {
	coords := hydro.GetKafkaEventCoords(ctx)
	logger := h.logger.WithFields(coords.Fields()...)

	msg := &actionsv0.ComputeUsage{}
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		h.statter.Counter(computeUsageStatsPrefix+"dropped_event", stats.Tags{"reason": "unmarshal"}, 1)
		return errors.Wrap(err, "Failed to unmarshal envelope message")
	}

	// We only care about update graph events. Any other messages should just be silently ack'd
	if !isUpdateGraphWorkflow(string(msg.GetWorkflowFilePath())) {
		h.statter.Counter(computeUsageStatsPrefix+"dropped_event", stats.Tags{"reason": "unsupported"}, 1)
		return nil
	}

	// extract fields for logging/stats
	workflowRunID := msg.GetWorkflowRunId()
	workflowJobID := msg.GetWorkflowJobId()
	repoID := uint64(msg.GetRepositoryId())
	repoVis := msg.GetRepositoryVisibility()
	ownerID := uint64(msg.GetRepositoryOwnerId())

	logger = logger.WithFields(
		semconv.DynamicWorkflowRunID(workflowRunID),
		semconv.DynamicWorkflowJobID(workflowJobID),
		semconv.RepoID(repoID),
		semconv.RepoVisibility(repoVis.String()),
		semconv.OwnerID(ownerID),
	)

	err := h.submitUpdateGraphComputeUsageJob(ctx, logger, msg)
	if err != nil {
		logger.WithError(err).Error("failed to enqueue job")
		h.statter.Counter(computeUsageStatsPrefix+"dropped_event", stats.Tags{"reason": "enqueue_failed"}, 1)
		return nil // swallow error to avoid topic getting stuck
	}

	h.statter.Counter(computeUsageStatsPrefix+"success", nil, 1)
	return nil
}

const (
	updateGraphIntegrationName = "dependabot"
	updateGraphSlug            = "update-graph"
)

var (
	updateGraphWorkflowPrefix = fmt.Sprintf("dynamic/%s/%s", updateGraphIntegrationName, updateGraphSlug)
)

func isUpdateGraphWorkflow(filePath string) bool {
	return strings.HasPrefix(filePath, updateGraphWorkflowPrefix)
}

func (h *ActionsComputeUsageHandler) submitUpdateGraphComputeUsageJob(ctx context.Context, logger log.Logger, msg *actionsv0.ComputeUsage) error {
	conclusion := h.getConclusionFromMsg(msg, logger)
	runnerRuntime := h.getRunnerRuntimeFromMsg(msg, logger)
	runnerType := h.getRunnerTypeFromMsg(msg, logger)

	job := &jobs.UpdateGraphComputeUsageJob{
		Conclusion:         conclusion,
		InvokingUserId:     uint64(msg.GetInvokingUserId()),
		InvokingEventType:  msg.GetInvokingEventType(),
		JobUserIdentifier:  msg.GetJobUserIdentifier(),
		JobName:            string(msg.GetJobName()),
		RepositoryId:       uint64(msg.GetRepositoryId()),
		RepositoryOwnerId:  uint64(msg.GetRepositoryOwnerId()),
		WorkflowJobId:      msg.GetWorkflowJobId(),
		WorkflowRunId:      msg.GetWorkflowRunId(),
		WorkflowRunAttempt: uint64(msg.GetWorkflowRunAttempt()),
		QueuedAt:           msg.GetQueuedAt(),
		StartedAt:          msg.GetStartedAt(),
		CompletedAt:        msg.GetCompletedAt(),
		RunnerRuntime:      runnerRuntime,
		RunnerType:         runnerType,
	}
	return submitJob(ctx, logger, h.enqueuer, job)
}

func (h *ActionsComputeUsageHandler) getConclusionFromMsg(msg *actionsv0.ComputeUsage, logger log.Logger) jobs.UpdateGraphComputeUsageJob_Conclusion {
	switch msg.GetCheckRunConclusion() {
	case actionsv0.ComputeUsage_RESULT_SUCCESS:
		return jobs.UpdateGraphComputeUsageJob_CONCLUSION_SUCCESS
	case actionsv0.ComputeUsage_RESULT_FAILURE:
		return jobs.UpdateGraphComputeUsageJob_CONCLUSION_FAILURE
	case actionsv0.ComputeUsage_RESULT_CANCELLED:
		return jobs.UpdateGraphComputeUsageJob_CONCLUSION_CANCELLED
	case actionsv0.ComputeUsage_RESULT_SKIPPED:
		return jobs.UpdateGraphComputeUsageJob_CONCLUSION_SKIPPED
	default:
		// TODO: Determine if we should handle RESULT_PARTIALLY_SUCCEEDED
		//
		// We don't expect our workflows to be partially successful right now
		// so mapping them as unknown means we will count them as failed.
		//
		// This seems like the most discoverable outcome if we were to deploy
		// a change that resulted in a surge in partial success.
		logger.WithFields(
			kvp.String("gh.check_run.conclusion", msg.GetCheckRunConclusion().String()),
		).Warn("workflow execution has an unexpected value for CheckRunConclusion")
		return jobs.UpdateGraphComputeUsageJob_CONCLUSION_UNKNOWN
	}
}

func (h *ActionsComputeUsageHandler) getRunnerRuntimeFromMsg(msg *actionsv0.ComputeUsage, logger log.Logger) string {
	switch msg.RunnerRuntime {
	case actionsv0.ComputeUsage_RUNNER_RUNTIME_LINUX:
		return "linux"
	case actionsv0.ComputeUsage_RUNNER_RUNTIME_MACOS:
		return "macos"
	case actionsv0.ComputeUsage_RUNNER_RUNTIME_WINDOWS:
		return "windows"
	default:
		logger.Warn("workflow execution has an unexpected value for RunnerRuntime")
		return "unknown"
	}
}

func (h *ActionsComputeUsageHandler) getRunnerTypeFromMsg(msg *actionsv0.ComputeUsage, logger log.Logger) string {
	switch msg.RunnerType {
	case actionsv0.ComputeUsage_RUNNER_TYPE_SELF_HOSTED:
		return "self-hosted"
	case actionsv0.ComputeUsage_RUNNER_TYPE_HOSTED:
		return "hosted"
	case actionsv0.ComputeUsage_RUNNER_TYPE_HOSTED_LARGER:
		return "hosted-large"
	default:
		logger.Warn("workflow execution has an unexpected value for RunnerType")
		return "unknown"
	}
}
