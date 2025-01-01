package api

import (
	"context"
	"strconv"

	"github.com/github/actions-usage-metrics/internal/projections/performance_workflow"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

func (u *UsageApi) GetWorkflowPerformance(ctx context.Context, req *proto.GetWorkflowPerformanceRequest) (*proto.GetWorkflowPerformanceResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetWorkflowPerformance")
	defer span.End()

	setRequestType(req.RequestOptions, proto.RequestType_REQUEST_TYPE_PERFORMANCE)
	getItemsResult, err := getMetrics[performance_workflow.WorkflowPerformanceItem](u, ctx, performance_workflow.WorkflowPerformanceProjection, req.RequestOptions)
	if err != nil {
		return nil, err
	}

	convertedItems, err := convertWorkflowPerformanceItemsToProto(getItemsResult.Items)
	if err != nil {
		return nil, err
	}

	return &proto.GetWorkflowPerformanceResponse{
		Items:      convertedItems,
		TotalItems: getItemsResult.TotalItems,
		Offset:     *req.RequestOptions.Offset,
		DateRange:  *req.RequestOptions.DateRange,
		StartTime:  &getItemsResult.TimeRange.StartTime,
		EndTime:    &getItemsResult.TimeRange.EndTime,
	}, err
}

func convertWorkflowPerformanceItemsToProto(resultItems []performance_workflow.WorkflowPerformanceItem) ([]*proto.WorkflowPerformanceItem, error) {
	items := make([]*proto.WorkflowPerformanceItem, 0, len(resultItems))
	for _, item := range resultItems {
		var jobs *proto.CardinalityField
		jobs = getKustoCardinalityAggregateResponse(item.Jobs)
		ownerId, err := strconv.ParseInt(item.RepositoryOwnerId, 10, 0)
		if err != nil {
			return nil, err
		}
		items = append(items, &proto.WorkflowPerformanceItem{
			RepositoryId:       item.RepositoryId,
			WorkflowFilePath:   item.WorkflowFilePath,
			WorkflowExecutions: uint64(item.WorkflowExecutions),
			Jobs:               jobs,
			AverageRunTime:     uint64(item.AverageRunTime),
			FailureRate:        float32(item.FailureRate),
			OwnerId:            ownerId,
		})
	}
	return items, nil
}
