package handlers

import (
	"context"
	"time"

	stats "github.com/github/go-stats"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
)

type BulkUsageEmissionsHandler struct {
	*Handler
}

func NewBulkUsageEmissionsHandler(
	params *HandlerParams,
) *BulkUsageEmissionsHandler {
	return &BulkUsageEmissionsHandler{
		Handler: NewHandler(params, models.WorkerTypeBulkUsageEmission),
	}
}

func (h *BulkUsageEmissionsHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	start := time.Now()
	defer func() {
		duration := time.Since(start)
		h.statter.Timing("bulk-usage-emission-handler", stats.Tags{}, duration)
	}()

	logger.Info("Processing message")

	return nil
}
