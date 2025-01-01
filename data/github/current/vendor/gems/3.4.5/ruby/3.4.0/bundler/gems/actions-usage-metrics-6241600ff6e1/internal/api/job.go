package api

import (
	"context"
	"strconv"

	"github.com/github/actions-usage-metrics/internal/projections/job"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

func (u *UsageApi) GetJobUsage(ctx context.Context, req *proto.GetJobUsageRequest) (*proto.GetJobUsageResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetJobUsage")
	defer span.End()

	getItemsResult, err := getMetrics[job.JobUsageItem](u, ctx, job.JobProjection, req.RequestOptions)
	if err != nil {
		return nil, err
	}

	convertedItems, err := convertJobUsageItemsToProto(getItemsResult.Items)
	if err != nil {
		return nil, err
	}

	return &proto.GetJobUsageResponse{
		Items:      convertedItems,
		TotalItems: getItemsResult.TotalItems,
		Offset:     *req.RequestOptions.Offset,
		DateRange:  *req.RequestOptions.DateRange,
		StartTime:  &getItemsResult.TimeRange.StartTime,
		EndTime:    &getItemsResult.TimeRange.EndTime,
	}, err
}

func convertJobUsageItemsToProto(resultItems []job.JobUsageItem) ([]*proto.JobUsageItem, error) {
	items := make([]*proto.JobUsageItem, 0, len(resultItems))

	for _, item := range resultItems {
		ownerId, err := strconv.ParseInt(item.RepositoryOwnerId, 10, 0)
		if err != nil {
			return nil, err
		}

		items = append(items, &proto.JobUsageItem{
			RepositoryId:      item.RepositoryId,
			WorkflowFilePath:  item.WorkflowFilePath,
			JobUserIdentifier: item.JobUserIdentifier,
			JobName:           item.JobName,
			RunnerType:        proto.RunnerType(proto.RunnerType_value[item.RunnerType]),
			RunnerRuntime:     proto.RunnerRuntime(proto.RunnerRuntime_value[item.RunnerRuntime]),
			TotalMinutes:      item.TotalMinutes,
			JobExecutions:     item.JobExecutions,
			AverageRunTime:    uint64(item.AverageRunTime),
			AverageQueueTime:  uint64(item.AverageQueueTime),
			FailureRate:       float32(item.FailureRate),
			RunnerLabels:      item.RunnerLabels,
			OwnerId:           ownerId,
		})
	}
	return items, nil
}
