package api

import (
	"context"
	"strconv"

	"github.com/github/actions-usage-metrics/internal/projections/org"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

func (u *UsageApi) GetOrgUsage(ctx context.Context, req *proto.GetOrgUsageRequest) (*proto.GetOrgUsageResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetOrgUsage")
	defer span.End()

	getItemsResult, err := getMetrics[org.OrgUsageItem](u, ctx, org.OrgProjection, req.RequestOptions)
	if err != nil {
		return nil, err
	}

	convertedItems, err := convertOrgUsageItemsToProto(ctx, getItemsResult.Items)
	if err != nil {
		return nil, err
	}

	return &proto.GetOrgUsageResponse{
		Items:      convertedItems,
		TotalItems: getItemsResult.TotalItems,
		StartTime:  &getItemsResult.TimeRange.StartTime,
		EndTime:    &getItemsResult.TimeRange.EndTime,
	}, err
}

func convertOrgUsageItemsToProto(ctx context.Context, resultItems []org.OrgUsageItem) ([]*proto.OrgUsageItem, error) {
	items := make([]*proto.OrgUsageItem, 0, len(resultItems))
	for _, item := range resultItems {
		var workflowExecutions *proto.CardinalityField
		var workflows *proto.CardinalityField
		workflowExecutions = getKustoCardinalityAggregateResponse(item.WorkflowExecutions)
		workflows = getKustoCardinalityAggregateResponse(item.Workflows)
		ownerId, err := strconv.ParseInt(item.RepositoryOwnerId, 10, 0)
		if err != nil {
			return nil, err
		}
		items = append(items, &proto.OrgUsageItem{
			TotalMinutes:       item.TotalMinutes,
			JobExecutions:      item.JobExecutions,
			WorkflowExecutions: workflowExecutions,
			Workflows:          workflows,
			AverageRunTime:     uint64(item.AverageRunTime),
			AverageQueueTime:   uint64(item.AverageQueueTime),
			FailureRate:        float32(item.FailureRate),
			OwnerId:            ownerId,
		})
	}
	return items, nil
}
