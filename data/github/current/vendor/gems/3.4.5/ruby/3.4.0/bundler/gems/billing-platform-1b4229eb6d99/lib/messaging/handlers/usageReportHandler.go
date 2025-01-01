package handlers

import (
	"context"
	"encoding/json"
	"time"

	"github.com/github/billing-platform/lib/azure/kusto"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	stats "github.com/github/go-stats"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

type UsageReportHandler struct {
	*Handler
	usageReportEngine engines.UsageReportEngineInterface
	kustoService      kusto.KustoService
	hydroPublisher    interfaces.HydroPublisher
}

func NewUsageReportHandler(
	params *HandlerParams,
	usageReportEngine engines.UsageReportEngineInterface,
	kustoService kusto.KustoService,
	hydroPublisher interfaces.HydroPublisher,
) *UsageReportHandler {
	return &UsageReportHandler{
		Handler:           NewHandler(params, models.WorkerTypeUsageReport),
		usageReportEngine: usageReportEngine,
		kustoService:      kustoService,
		hydroPublisher:    hydroPublisher,
	}
}

func (h *UsageReportHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	start := time.Now()
	defer func() {
		duration := time.Since(start)
		h.statter.Timing("usage.report_handler.time", stats.Tags{}, duration)
	}()

	if h.kustoService == nil {
		logger.Error("kusto service is nil")
		return nil
	}

	logger.Debug("unmarshalling enveloped message", kvp.String("payload", string(rr.Payload)))

	var usageReportExport *models.UsageReportExport
	if err := json.Unmarshal(rr.Payload, &usageReportExport); err != nil {
		h.trackEmissionError(logger, err, nil)
		return nil
	}

	// Check if the usage report request is still active, this guards against the case where the request
	// is deleted after completion at the same time we fan out messages to be processed.
	usageReportRequestActive, err := h.usageReportEngine.UsageReportRequestActive(ctx, logger, &usageReportExport.Key)
	if err != nil {
		h.trackEmissionError(logger, err, usageReportExport)
		return nil
	} else if !usageReportRequestActive {
		logger.Info("usage report request no longer active, skipping", kvp.String("id", usageReportExport.Id))
		h.statter.Counter("usage.report_handler.skip", stats.Tags{"status": string(usageReportExport.Status)}, int64(1))
		return nil
	}

	switch usageReportExport.Status {
	case models.UsageReportExportStatusPending:
		err := h.handlePendingUsageReport(ctx, logger, usageReportExport)
		if err != nil {
			h.trackEmissionError(logger, err, usageReportExport)
			return nil
		}
	case models.UsageReportExportStatusLoading:
		err := h.handleLoadingUsageReport(ctx, logger, usageReportExport)
		if err != nil {
			h.trackEmissionError(logger, err, usageReportExport)
			return nil
		}
	default:
		logger.Info("skipping usage report due to type", kvp.String("id", usageReportExport.Id))
		h.statter.Counter("usage.report_handler.skip", stats.Tags{"status": string(usageReportExport.Status)}, int64(1))

		return nil
	}

	h.statter.Counter("usage.report_handler.success", stats.Tags{"status": string(usageReportExport.Status)}, int64(1))

	return nil
}

func (h *UsageReportHandler) handlePendingUsageReport(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport) error {
	logger.Info("processing pending usage report", kvp.String("id", usageReportExport.Id))

	uuid, err := h.kustoService.SubmitExportRequest(ctx, h.cfg.KustoBlobExportContainerName, usageReportExport, h.cfg.IsProxima)
	if err != nil {
		return err
	}

	logger.Info("submitted export request", kvp.String("id", usageReportExport.Id), kvp.String("uuid", uuid))

	_, err = h.usageReportEngine.MigratePendingUsageReportToLoading(ctx, logger, usageReportExport, uuid)
	if err != nil {
		return err
	}

	return nil
}

func (h *UsageReportHandler) handleLoadingUsageReport(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport) error {
	logger.Info("processing loading usage report", kvp.String("id", usageReportExport.Id))

	kustoExportOperationStatus, err := h.kustoService.GetExportStatus(ctx, usageReportExport)
	if err != nil {
		return err
	}

	switch kustoExportOperationStatus {
	case models.KustoOperationStatusEmpty:
		logger.Debug("export operation not yet started", kvp.String("id", usageReportExport.Id))
		return nil
	case models.KustoOperationStatusInProgress:
		logger.Debug("export operation still in progress", kvp.String("id", usageReportExport.Id))
		return nil
	case models.KustoOperationStatusScheduled:
		logger.Debug("export operation scheduled", kvp.String("id", usageReportExport.Id))
		return nil
	case models.KustoOperationStatusCompleted:
		logger.Info("export operation completed", kvp.String("id", usageReportExport.Id))

		blobURLs, err := h.kustoService.GetExportBlobs(ctx, usageReportExport)
		if err != nil {
			return err
		}

		completedUsageReportExport, err := h.usageReportEngine.MigrateLoadingUsageReportToCompleted(ctx, logger, usageReportExport, blobURLs)
		if err != nil {
			// If the usage report has been deleted by a different job, we can ignore the error
			// and return nil to prevent emitting error messages as this is a valid case.
			if db.Is404NotFound(err) && h.usageReportEngine.IsExportOperationAlreadyCompleted(ctx, logger, usageReportExport) {
				h.statter.Counter("usage.report_handler.skip", stats.Tags{"status": string(usageReportExport.Status)}, int64(1))
				return nil
			}

			// If the usage report has been migrated to completed by a different job, we can ignore the error
			// of the conflict and return nil to prevent emitting error messages as this is a valid case.
			if db.Is409Conflict(err) && h.usageReportEngine.IsExportOperationAlreadyCompleted(ctx, logger, usageReportExport) {
				h.statter.Counter("usage.report_handler.skip", stats.Tags{"status": string(usageReportExport.Status)}, int64(1))
				return nil
			}

			return err
		}

		err = h.usageReportEngine.PublishUsageReportRequestNotification(logger, h.hydroPublisher, completedUsageReportExport, true)
		if err != nil {
			return err
		}

		h.statter.Timing("usage.report_handler.time_to_complete", nil, time.Since(usageReportExport.ReceivedAt))

		return nil
	case models.KustoOperationStatusThrottled:
		logger.Debug("export operation throttled, adding back to pending", kvp.String("exportOperartionUUID", usageReportExport.ExportOperationUUID))

		_, err = h.usageReportEngine.MigrateThrottledUsageReportToPending(ctx, logger, usageReportExport)
		if err != nil {
			return err
		}

		return nil
	default:
		logger.Error("usage report export failed", kvp.String("id", usageReportExport.Id), kvp.String("kustoStatus", string(kustoExportOperationStatus)))

		failedUsageReportExport, err := h.usageReportEngine.MigrateLoadingUsageReportToFailed(ctx, logger, usageReportExport)
		if err != nil {
			// If the usage report has been deleted by a different job, we can ignore the error
			// and return nil to prevent emitting error messages as this is a valid case.
			if db.Is404NotFound(err) && h.usageReportEngine.IsExportOperationAlreadyFailed(ctx, logger, usageReportExport) {
				h.statter.Counter("usage.report_handler.skip", stats.Tags{"status": string(usageReportExport.Status)}, int64(1))
				return nil
			}

			// If the usage report has been migrated to failed by a different job, we can ignore the error
			// of the conflict and return nil to prevent emitting error messages as this is a valid case.
			if db.Is409Conflict(err) && h.usageReportEngine.IsExportOperationAlreadyFailed(ctx, logger, usageReportExport) {
				h.statter.Counter("usage.report_handler.skip", stats.Tags{"status": string(usageReportExport.Status)}, int64(1))
				return nil
			}

			return err
		}

		err = h.usageReportEngine.PublishUsageReportRequestNotification(logger, h.hydroPublisher, failedUsageReportExport, false)
		if err != nil {
			return err
		}
	}

	return nil
}

func (h *UsageReportHandler) trackEmissionError(logger log.Logger, err error, usageReportExport *models.UsageReportExport) {
	if usageReportExport != nil {
		logger.WithError(err).Error("error processing usage report export", kvp.String("id", usageReportExport.Id), kvp.String("exportOperartionUUID", usageReportExport.ExportOperationUUID))
	} else {
		logger.WithError(err).Error("error processing usage report export")
	}

	h.statter.Counter("usage.report_handler.error", stats.Tags{}, int64(1))
}
