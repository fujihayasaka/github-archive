package api

import (
	"context"

	"github.com/github/actions-usage-metrics/internal/projections/runnerruntime"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

func (u *UsageApi) GetRunnerRuntimeUsage(ctx context.Context, req *proto.GetRunnerRuntimeUsageRequest) (*proto.GetRunnerRuntimeUsageResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetRunnerRuntimeUsage")
	defer span.End()

	getItemsResult, err := getMetrics[runnerruntime.RunnerRuntimeUsageItem](u, ctx, runnerruntime.RunnerRuntimeProjection, req.RequestOptions)
	if err != nil {
		return nil, err
	}

	return &proto.GetRunnerRuntimeUsageResponse{
		Items:      convertRunnerRuntimeUsageItemsToProto(ctx, getItemsResult.Items),
		TotalItems: getItemsResult.TotalItems,
		Offset:     *req.RequestOptions.Offset,
		DateRange:  *req.RequestOptions.DateRange,
		StartTime:  &getItemsResult.TimeRange.StartTime,
		EndTime:    &getItemsResult.TimeRange.EndTime,
	}, err
}

func convertRunnerRuntimeUsageItemsToProto(ctx context.Context, resultItems []runnerruntime.RunnerRuntimeUsageItem) []*proto.RunnerRuntimeUsageItem {
	items := make([]*proto.RunnerRuntimeUsageItem, 0, len(resultItems))
	for _, item := range resultItems {
		var workflowExecutions *proto.CardinalityField
		var workflows *proto.CardinalityField
		workflowExecutions = getKustoCardinalityAggregateResponse(item.WorkflowExecutions)
		workflows = getKustoCardinalityAggregateResponse(item.Workflows)

		items = append(items, &proto.RunnerRuntimeUsageItem{
			RunnerRuntime:      proto.RunnerRuntime(proto.RunnerRuntime_value[item.RunnerRuntime]),
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
