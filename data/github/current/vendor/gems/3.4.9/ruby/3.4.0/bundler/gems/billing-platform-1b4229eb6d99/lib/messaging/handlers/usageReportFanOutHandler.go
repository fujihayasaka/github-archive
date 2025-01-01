package handlers

import (
	"context"
	"strconv"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
)

type UsageReportFanOutHandler struct {
	*Handler
	usageReportEngine engines.UsageReportEngineInterface
}

func NewUsageReportFanOutHandler(params *HandlerParams, usageReportEngine engines.UsageReportEngineInterface) *UsageReportFanOutHandler {
	return &UsageReportFanOutHandler{
		Handler:           NewHandler(params, models.WorkerTypeUsageReportFanOut),
		usageReportEngine: usageReportEngine,
	}
}

func (h *UsageReportFanOutHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	h.statter.Counter("usage_report_fan_out.start", stats.Tags{}, int64(1))
	start := time.Now()

	err := h.handleScheduleUsageReportJobs(ctx, logger)
	if err != nil {
		h.trackError(logger, err)
	} else {
		logger.Info("finished processing usage report fan-out request")
	}

	h.statter.Timing("usage_report_fan_out.finish", stats.Tags{"success": strconv.FormatBool(err == nil)}, time.Since(start))

	return err
}

func (h *UsageReportFanOutHandler) handleScheduleUsageReportJobs(ctx context.Context, logger log.Logger) error {
	usageReportExports, err := h.usageReportEngine.GetActiveUsageReportExports(ctx, logger)
	if err != nil {
		return errors.Wrap(err, "failed to get active usage report exports")
	}

	return h.usageReportEngine.PublishUsageReportMessages(ctx, logger, usageReportExports)
}

func (h *UsageReportFanOutHandler) trackError(logger log.Logger, err error, fields ...kvp.Field) {
	logger.WithError(err).Error("error while processing request", fields...)
	h.statter.Counter("usage_report_fan_out.error", stats.Tags{}, int64(1))
}
