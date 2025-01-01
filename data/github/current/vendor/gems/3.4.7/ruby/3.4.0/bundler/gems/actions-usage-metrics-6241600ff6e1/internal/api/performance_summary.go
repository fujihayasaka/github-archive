package api

import (
	"context"

	"github.com/github/actions-usage-metrics/internal/projections/summary"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"
)

func (u *UsageApi) GetPerformanceSummary(ctx context.Context, req *proto.GetPerformanceSummaryRequest) (*proto.GetPerformanceSummaryResponse, error) {
	ctx, span := telemetry.Trace(ctx, "PerformanceApi.GetPerformanceSummary")
	defer span.End()

	logger := log.WithContext(ctx)
	options := req.RequestOptions
	err := validateSummary(options)
	if err != nil {
		return nil, err
	}

	options.RequestType = proto.RequestType_REQUEST_TYPE_PERFORMANCE.Enum()

	version := getProjectionVersion(options.ProjectionOptions)
	readProjection := summary.PerformanceSummaryProjection(version, options, req.GetMetricsType())

	result, err := getItems[summary.PerformanceSummaryItem](ctx, u.telem, u.apiServerCfg.Kusto, u.kustoClient, readProjection, false, false, options, nil)

	if err != nil {
		logger.WithError(err).Error("failed to get performance summary")
		return nil, err
	}

	if len(result.Items) == 1 {
		// there should only ever be 1 item, so if not 1 return error
		return &proto.GetPerformanceSummaryResponse{
			AverageJobRunTime:   result.Items[0].AverageRunTime,
			AverageJobQueueTime: result.Items[0].AverageQueueTime,
			JobFailureRate:      float32(result.Items[0].FailureRate),
			TotalFailureMinutes: result.Items[0].TotalFailureMinutes,
		}, nil
	} else {
		logger.WithError(err).Error("error getting performance summary")
		return nil, err
	}
}
