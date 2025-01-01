package api

import (
	"context"

	"github.com/github/actions-usage-metrics/internal/projections/repo"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

func (u *UsageApi) GetRepoUsage(ctx context.Context, req *proto.GetRepoUsageRequest) (*proto.GetRepoUsageResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetRepoUsage")
	defer span.End()

	getItemsResult, err := getMetrics[repo.RepoUsageItem](u, ctx, repo.RepoProjection, req.RequestOptions)
	if err != nil {
		return nil, err
	}

	return &proto.GetRepoUsageResponse{
		Items:      convertRepoUsageItemsToProto(ctx, getItemsResult.Items),
		TotalItems: getItemsResult.TotalItems,
		Offset:     *req.RequestOptions.Offset,
		DateRange:  *req.RequestOptions.DateRange,
		StartTime:  &getItemsResult.TimeRange.StartTime,
		EndTime:    &getItemsResult.TimeRange.EndTime,
	}, err
}

func convertRepoUsageItemsToProto(ctx context.Context, resultItems []repo.RepoUsageItem) []*proto.RepoUsageItem {
	items := make([]*proto.RepoUsageItem, 0, len(resultItems))
	for _, item := range resultItems {
		var workflowExecutions *proto.CardinalityField
		var workflows *proto.CardinalityField
		workflowExecutions = getKustoCardinalityAggregateResponse(item.WorkflowExecutions)
		workflows = getKustoCardinalityAggregateResponse(item.Workflows)

		items = append(items, &proto.RepoUsageItem{
			RepositoryId:       item.RepositoryId,
			TotalMinutes:       item.TotalMinutes,
			JobExecutions:      item.JobExecutions,
			WorkflowExecutions: workflowExecutions,
			Workflows:          workflows,
			AverageRunTime:     uint64(item.AverageRunTime),
			AverageQueueTime:   uint64(item.AverageQueueTime),
			FailureRate:        float32(item.FailureRate),
		})
	}
	return items
}
