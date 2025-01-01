package managed_analyses

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func (r *Service) GetManagedAnalysisInfo(ctx context.Context, req *proto.GetManagedAnalysisInfoRequest) (*proto.GetManagedAnalysisInfoResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	appctx.Logger(ctx).Info("request received")

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	codeqlRepo, nextScheduledRunAt, activeRepo, err := r.ma.GetInfo(ctx, ts.RepositoryEID(req.RepositoryId))
	if errors.Is(err, ts.ErrCodeqlRepoNotFound) {
		resp := &proto.GetManagedAnalysisInfoResponse{
			StatusV2: proto.OnboardingStatusV2_DISABLED,
		}
		return resp, nil
	} else if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	runnerLabel := codeqlRepo.RunnerLabel

	resp := &proto.GetManagedAnalysisInfoResponse{
		StatusV2:    serializeOnboardingStatus(codeqlRepo.OnboardingStatus()),
		ThreatModel: serializeThreatModel(codeqlRepo.ThreatModel),
		QuerySuite:  serializeQuerySuite(codeqlRepo.QuerySuite),
		RunnerLabel: runnerLabel,
	}

	if codeqlRepo.CurrentConfig != nil {
		resp.CurrentConfig = serializeCodeQLConfig(codeqlRepo.CurrentConfig)
	}

	debuggableConfig := codeqlRepo.DebuggableConfig()
	if debuggableConfig != nil {
		resp.Workflow = debuggableConfig.Workflow
		run := debuggableConfig.LatestRun
		if run != nil {
			resp.DebuggableWorkflowRunId = uint64(run.WorkflowRunID)
			resp.DebuggableConfig = serializeCodeQLConfig(debuggableConfig)

			if run.Status == ts.CodeqlRunStatus_FAILED {
				resp.Error = "Workflow run has failed"
			}
		}
	}

	if nextScheduledRunAt != nil {
		resp.NextScheduledRunAt = timestamppb.New(*nextScheduledRunAt)
	}
	resp.ActiveRepo = activeRepo
	resp.HasFailedUpdate = codeqlRepo.HasFailedUpdate()

	return resp, nil
}
