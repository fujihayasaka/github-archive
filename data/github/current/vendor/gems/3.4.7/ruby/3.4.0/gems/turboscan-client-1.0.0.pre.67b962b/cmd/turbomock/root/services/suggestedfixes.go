package services

import (
	"context"

	"github.com/github/turboscan/cmd/turbomock/data"
	"github.com/github/turboscan/ts/proto"
)

type SuggestedFixesResponses struct {
}

func (r *SuggestedFixesResponses) GetSuggestedFix(ctx context.Context, request *proto.GetSuggestedFixRequest) (resp *proto.GetSuggestedFixResponse, err error) {
	resp, err = data.LoadCassette(ctx, "reflected-xss-suggested-fix.yml", resp)

	rewritten := make(map[uint32]*proto.SuggestedFixAlert, len(request.AlertNumbers))

	for _, requestedNumber := range request.AlertNumbers {
		rewritten[requestedNumber] = resp.SuggestedFixAlerts[1]
	}
	resp.SuggestedFixAlerts = rewritten

	return
}

func (r *SuggestedFixesResponses) GenerateSuggestedFix(context.Context, *proto.GenerateSuggestedFixRequest) (*proto.GenerateSuggestedFixResponse, error) {
	return &proto.GenerateSuggestedFixResponse{
		Success: true,
	}, nil
}

func (r *SuggestedFixesResponses) GenerateDependabotFix(context.Context, *proto.GenerateDependabotFixRequest) (*proto.GenerateDependabotFixResponse, error) {
	return &proto.GenerateDependabotFixResponse{
		Success: true,
	}, nil
}

func (r *SuggestedFixesResponses) GenerateSyncFix(context.Context, *proto.GenerateSyncFixRequest) (*proto.GenerateSyncFixResponse, error) {
	return &proto.GenerateSyncFixResponse{
		State: proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_ERROR,
	}, nil
}

func (r *SuggestedFixesResponses) ApplySuggestedFix(context.Context, *proto.ApplySuggestedFixRequest) (*proto.ApplySuggestedFixResponse, error) {
	return &proto.ApplySuggestedFixResponse{
		Success: true,
	}, nil
}

func (r *SuggestedFixesResponses) GetSuggestedFixStatesForOrg(ctx context.Context, request *proto.GetSuggestedFixStatesForOrgRequest) (resp *proto.GetSuggestedFixStatesForOrgResponse, err error) {
	return data.LoadCassette(ctx, "get-suggested-fix-states-for-org.yml", resp)
}

func (r *SuggestedFixesResponses) GetSuggestedFixValidationCheck(ctx context.Context, request *proto.GetSuggestedFixValidationCheckRequest) (resp *proto.GetSuggestedFixValidationCheckResponse, err error) {
	return &proto.GetSuggestedFixValidationCheckResponse{
		ValidationCheck: &proto.ValidationCheck{
			ValidationType: request.ValidationType,
			Status:         proto.ValidationCheckStatus_VALIDATION_CHECK_STATUS_SUCCESS,
			WorkflowRunId:  request.WorkflowRunId,
		},
	}, nil
}
