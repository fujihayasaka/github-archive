package api

import (
	"context"

	"github.com/github/actions-usage-metrics/internal/projections/summary"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"
)

func (u *UsageApi) GetUsageSummary(ctx context.Context, req *proto.GetUsageSummaryRequest) (*proto.GetUsageSummaryResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetUsageSummary")
	defer span.End()

	logger := log.WithContext(ctx)
	options := req.RequestOptions
	err := validateSummary(options)
	if err != nil {
		return nil, err
	}

	version := getProjectionVersion(options.ProjectionOptions)
	readProjection := summary.UsageSummaryProjection(version, options, req.GetMetricsType())

	result, err := getItems[summary.UsageSummaryItem](ctx, u.telem, u.apiServerCfg.Kusto, u.kustoClient, readProjection, false, false, options, nil)

	if err != nil {
		logger.WithError(err).Error("failed to get usage summary")
		return nil, err
	}

	if len(result.Items) == 1 {
		// there should only ever be 1 item, so if not 1 return error
		return &proto.GetUsageSummaryResponse{
			TotalMinutes:  result.Items[0].TotalMinutes,
			JobExecutions: result.Items[0].JobExecutions,
		}, nil
	} else {
		logger.WithError(err).Error("error getting usage summary")
		return nil, err
	}
}
