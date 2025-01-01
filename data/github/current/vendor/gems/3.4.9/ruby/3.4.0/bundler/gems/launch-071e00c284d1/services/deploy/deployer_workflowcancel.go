package deploy

import (
	"context"

	"github.com/golang/protobuf/ptypes/empty"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
)

func (s *service) WorkflowCancel(ctx context.Context, req *pb.WorkflowCancelRequest) (*empty.Empty, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	checkSuiteGID, err := s.GetGlobalIDFromIdentity(ctx, req.GetCheckSuiteId(), "WorkflowCancel")
	if err != nil {
		return nil, tracing.RecordError(span, errors.NewInternalError(err.Error()))
	}
	canceledByGID, err := s.GetGlobalIDFromIdentity(ctx, req.GetCanceledByGlobalId(), "WorkflowCancel")
	if err != nil {
		return nil, tracing.RecordError(span, errors.NewInternalError(err.Error()))
	}

	fields := []kvp.Field{
		kvp.String("gh.check_suite.global_id", checkSuiteGID.String()),
		kvp.Int64("gh.launch.cancelled_by_id", req.CanceledById),
		kvp.String("gh.launch.cancelled_by_name", req.CanceledByName),
		kvp.String("gh.launch.cancelled_by_global_id", canceledByGID.String()),
	}
	s.cfg.Log.Log(ctx, "cancel requested", fields...)

	if checkSuiteGID.IsZeroValue() {
		return nil, tracing.RecordError(span, errors.NewInvalidArgumentError("The Check Suite ID supplied is invalid"))
	}
	var actorName *string
	if !canceledByGID.IsZeroValue() {
		actorName = &req.CanceledByName
	}

	wfBuildState, ok, err := s.cfg.WorkflowBuilds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkSuiteGID)
	if err != nil {
		return nil, tracing.RecordError(span, errors.NewInternalError("Could not determine the execution details for the Workflow"))
	}
	if !ok {
		return nil, tracing.RecordError(span, errors.NewNotFoundError("No Workflow could be found for the supplied Check Suite ID"))
	}

	err = s.cfg.WorkflowCanceler.Cancel(ctx, wfBuildState, &azp.CancelOptions{
		ActorName: actorName,
		Force:     req.Force,
	})
	if err != nil {
		s.cfg.Log.Report(ctx, err)
		return nil, tracing.RecordError(span, errors.NewInternalError("Could not cancel the execution of the Workflow"))
	}

	return &empty.Empty{}, nil
}
