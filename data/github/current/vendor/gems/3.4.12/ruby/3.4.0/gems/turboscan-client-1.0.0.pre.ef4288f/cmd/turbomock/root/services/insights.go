package services

import (
	"context"

	"github.com/github/turboscan/cmd/turbomock/data"
	"github.com/github/turboscan/ts/proto"
)

type InsightsResponses struct {
}

func (r *InsightsResponses) GetAlertsForInsightsBackfill(ctx context.Context, _ *proto.GetAlertsForInsightsBackfillRequest) (resp *proto.GetAlertsForInsightsBackfillRequestResponse, err error) {
	return data.LoadCassette(ctx, "get-alerts-for-insights-backfill.yml", resp)
}
