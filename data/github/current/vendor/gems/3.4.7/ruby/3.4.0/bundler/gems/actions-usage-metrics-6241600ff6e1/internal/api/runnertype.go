package api

import (
	"context"

	"github.com/github/actions-usage-metrics/internal/projections/runnertype"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

func (u *UsageApi) GetRunnerTypeUsage(ctx context.Context, req *proto.GetRunnerTypeUsageRequest) (*proto.GetRunnerTypeUsageResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetRunnerTypeUsage")
	defer span.End()

	getItemsResult, err := getMetrics[runnertype.RunnerTypeUsageItem](u, ctx, runnertype.RunnerTypeProjection, req.RequestOptions)
	if err != nil {
		return nil, err
	}

	return &proto.GetRunnerTypeUsageResponse{
		Items:      convertRunnerTypeUsageItemsToProto(ctx, getItemsResult.Items),
		TotalItems: getItemsResult.TotalItems,
		Offset:     *req.RequestOptions.Offset,
		DateRange:  *req.RequestOptions.DateRange,
		StartTime:  &getItemsResult.TimeRange.StartTime,
		EndTime:    &getItemsResult.TimeRange.EndTime,
	}, err
}

func convertRunnerTypeUsageItemsToProto(ctx context.Context, resultItems []runnertype.RunnerTypeUsageItem) []*proto.RunnerTypeUsageItem {
	items := make([]*proto.RunnerTypeUsageItem, 0, len(resultItems))
	for _, item := range resultItems {
		var workflowExecutions *proto.CardinalityField
		var workflows *proto.CardinalityField
		workflowExecutions = getKustoCardinalityAggregateResponse(item.WorkflowExecutions)
		workflows = getKustoCardinalityAggregateResponse(item.Workflows)

		items = append(items, &proto.RunnerTypeUsageItem{
			RunnerType:         proto.RunnerType(proto.RunnerType_value[item.RunnerType]),
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
