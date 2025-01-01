package api

import (
	"context"
	"strconv"

	"github.com/github/actions-usage-metrics/internal/projections/usage_workflow"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

// GetUsageByRepoWorkflowRunner is used to query workflow-level usage data (at various time ranges).
func (u *UsageApi) GetUsageByRepoWorkflowRunner(ctx context.Context, req *proto.GetUsageByRepoWorkflowRunnerRequest) (*proto.GetUsageByRepoWorkflowRunnerResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetUsageByRepoWorkflowRunner")
	defer span.End()

	getItemsResult, err := getMetrics[usage_workflow.RepoWorkflowRunnerItem](u, ctx, usage_workflow.RepoWorkflowRunnerProjection, req.RequestOptions)
	if err != nil {
		return nil, err
	}

	convertedItems, err := convertWorkflowUsageItemsToProto(ctx, getItemsResult.Items)
	if err != nil {
		return nil, err
	}

	return &proto.GetUsageByRepoWorkflowRunnerResponse{
		Items:      convertedItems,
		TotalItems: getItemsResult.TotalItems,
		Offset:     *req.RequestOptions.Offset,
		DateRange:  *req.RequestOptions.DateRange,
		StartTime:  &getItemsResult.TimeRange.StartTime,
		EndTime:    &getItemsResult.TimeRange.EndTime,
	}, err
}

func convertWorkflowUsageItemsToProto(ctx context.Context, resultItems []usage_workflow.RepoWorkflowRunnerItem) ([]*proto.RepoWorkflowRunnerUsageItem, error) {
	items := make([]*proto.RepoWorkflowRunnerUsageItem, 0, len(resultItems))
	for _, item := range resultItems {
		var workflowExecutions *proto.CardinalityField
		var jobs *proto.CardinalityField
		workflowExecutions = getKustoCardinalityAggregateResponse(item.WorkflowExecutions)
		jobs = getKustoCardinalityAggregateResponse(item.Jobs)
		ownerId, err := strconv.ParseInt(item.RepositoryOwnerId, 10, 0)
		if err != nil {
			return nil, err
		}

		items = append(items, &proto.RepoWorkflowRunnerUsageItem{
			RepositoryId:       item.RepositoryId,
			WorkflowFilePath:   item.WorkflowFilePath,
			RunnerType:         proto.RunnerType(proto.RunnerType_value[item.RunnerType]),
			RunnerRuntime:      proto.RunnerRuntime(proto.RunnerRuntime_value[item.RunnerRuntime]),
			TotalMinutes:       item.TotalMinutes,
			WorkflowExecutions: workflowExecutions,
			Jobs:               jobs,
			OwnerId:            ownerId,
		})
	}
	return items, nil
}
