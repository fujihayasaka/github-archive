package api

import (
	"context"

	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

// GetWorkflows is used to satisfy autocomplete requests for workflow file paths.
func (u *UsageApi) GetWorkflows(ctx context.Context, req *proto.GetWorkflowsRequest) (*proto.GetWorkflowsResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetWorkflows")
	defer span.End()

	searchField := "workflowFileName"
	options := req.RequestOptions

	options.SearchField = &searchField

	options.SearchField = &searchField

	autoCompleteRequest := proto.GetAutoCompleteRequest{
		RequestOptions: options,
	}
	result, err := u.getAutoComplete(ctx, &autoCompleteRequest)
	if err != nil {
		return nil, err
	}

	return &proto.GetWorkflowsResponse{Workflows: convertWorkflowsToProtoFromItems(result.Items)}, nil
}

func convertWorkflowsToProtoFromItems(items []string) []*proto.Workflow {
	workflows := make([]*proto.Workflow, 0, len(items))
	for _, item := range items {
		workflows = append(workflows, &proto.Workflow{
			FileName: item,
		})
	}
	return workflows
}
