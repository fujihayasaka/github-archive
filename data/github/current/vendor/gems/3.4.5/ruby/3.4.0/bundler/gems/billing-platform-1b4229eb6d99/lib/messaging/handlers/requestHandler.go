package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"
)

type RequestHandler struct {
	*Handler
	adminEngine         *engines.AdminEngine
	azureEmissionEngine engines.AzureEmissionEngineInterface
	invoiceEngine       *engines.InvoiceEngine
	usageEngine         engines.UsageEngineInterface
	usageReportEngine   engines.UsageReportEngineInterface
	pricingEngine       engines.PricingEngineInterface
	zuoraEngine         engines.ZuoraEngineInterface
}

func NewRequestHandler(
	params *HandlerParams,
	adminEngine *engines.AdminEngine,
	azureEmissionEngine engines.AzureEmissionEngineInterface,
	invoiceEngine *engines.InvoiceEngine,
	usageEngine engines.UsageEngineInterface,
	usageReportEngine engines.UsageReportEngineInterface,
	pricingEngine engines.PricingEngineInterface,
	zuoraEngine engines.ZuoraEngineInterface,
) *RequestHandler {
	return &RequestHandler{
		Handler:             NewHandler(params, models.WorkerTypeRequestHandler),
		adminEngine:         adminEngine,
		azureEmissionEngine: azureEmissionEngine,
		invoiceEngine:       invoiceEngine,
		usageEngine:         usageEngine,
		usageReportEngine:   usageReportEngine,
		pricingEngine:       pricingEngine,
		zuoraEngine:         zuoraEngine,
	}
}

func (h *RequestHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	// Get the request type from the message
	var request *models.Request
	if err := json.Unmarshal(rr.Payload, &request); err != nil {
		h.trackError(logger, errors.Wrap(err, "failed to unmarshal request"), "request_unmarshal_error")
		return errors.Wrap(err, "failed to unmarshal request")
	}

	h.DB.SetStatterTags(stats.Tags{"request_type": string(request.Type)})

	// Get the message handler from the request type
	var messageHandler func(context.Context, log.Logger, json.RawMessage) error
	switch request.Type {
	case models.ProcessDeadLetterQueue:
		messageHandler = h.handleProcessDeadLetterQueueRequest
	case models.ScheduleZuoraBatchEmission:
		messageHandler = h.handleScheduleZuoraBatchEmission
	case models.ScheduleEmission:
		messageHandler = h.handleScheduleEmission
	case models.ScheduleAzureEmission:
		messageHandler = h.handleScheduleAzureEmission
	case models.ScheduleInvoiceGeneration:
		messageHandler = h.handleScheduleInvoiceGeneration
	case models.ScheduleWatermarkJobs:
		messageHandler = h.handleScheduleWatermarkJobs
	case models.ScheduleZeroOutQuantitiesJobs:
		messageHandler = h.handleScheduleZeroOutQuantitiesJobs
	case models.ScheduleHighWatermarkRolloverJob:
		messageHandler = h.handleScheduleHighWatermarkRolloverJob
	case models.ScheduleUsageReportJobs:
		messageHandler = h.handleScheduleUsageReportJobs
	default:
		h.trackError(logger, errors.Errorf("unknown request type: %s", request.Type), "unknown_request_type")
		return nil
	}

	// Track the request
	h.statter.Counter("request_handler.start", stats.Tags{"request_type": string(request.Type)}, int64(1))
	logger.Info("processing request", kvp.String("request_type", string(request.Type)), kvp.Any("request_data", string(request.Data)))

	// Process the message
	start := time.Now()
	err := messageHandler(ctx, logger, request.Data)
	h.statter.Timing("request_handler.finish", stats.Tags{"request_type": string(request.Type), "success": strconv.FormatBool(err == nil)}, time.Since(start))
	if err != nil {
		h.trackError(logger, err, fmt.Sprintf("%s_error", request.Type))
	} else {
		logger.Info("finished processing request", kvp.String("request_type", string(request.Type)), kvp.Any("request_data", string(request.Data)))
	}
	return err
}

func (h *RequestHandler) handleProcessDeadLetterQueueRequest(ctx context.Context, logger log.Logger, data json.RawMessage) error {
	// Unmarshal the request data
	var requestData *models.ProcessDeadLetterQueueData
	if err := json.Unmarshal(data, &requestData); err != nil {
		return errors.Wrap(err, "failed to unmarshal process dead letter queue request")
	}

	// Process the dead letter queue
	return h.adminEngine.ProcessDeadLetterQueue(ctx, logger, requestData.DeadLetterQueueName, requestData.Num)
}

func (h *RequestHandler) handleScheduleZuoraBatchEmission(ctx context.Context, logger log.Logger, data json.RawMessage) error {
	// Get the emission target from the message
	var zuoraPayload *models.ZuoraBatchEmissionPayload
	if err := json.Unmarshal(data, &zuoraPayload); err != nil {
		return errors.Wrap(err, "failed to unmarshal zuora batch payload")
	}

	// Schedule Zuora Batch Emission Job
	return h.zuoraEngine.ScheduleZuoraBatchEmission(ctx, logger, zuoraPayload)
}

func (h *RequestHandler) handleScheduleEmission(ctx context.Context, logger log.Logger, data json.RawMessage) error {
	// Get the emission target from the message
	var target *models.EmissionTarget
	if err := json.Unmarshal(data, &target); err != nil {
		return errors.Wrap(err, "failed to unmarshal emission target")
	}

	// Schedule Zuora Emission
	skipCache := false
	return h.usageEngine.ScheduleZuoraEmission(ctx, logger, target, skipCache)
}

func (h *RequestHandler) handleScheduleAzureEmission(ctx context.Context, logger log.Logger, data json.RawMessage) error {
	// Get the emission target from the message
	var target *models.AzureUsageDate
	if err := json.Unmarshal(data, &target); err != nil {
		return errors.Wrap(err, "failed to unmarshal azure emission target")
	}

	// Schedule azure emission
	return h.azureEmissionEngine.ScheduleAzureEmission(ctx, logger, target)
}

func (h *RequestHandler) handleScheduleUsageReportJobs(ctx context.Context, logger log.Logger, data json.RawMessage) error {
	usageReportExports, err := h.usageReportEngine.GetActiveUsageReportExports(ctx, logger)
	if err != nil {
		return errors.Wrap(err, "failed to get active usage report exports")
	}

	return h.usageReportEngine.PublishUsageReportMessages(ctx, logger, usageReportExports)
}

func (h *RequestHandler) handleScheduleInvoiceGeneration(ctx context.Context, logger log.Logger, data json.RawMessage) error {
	// Get the invoice partition detail from the message
	var ipd *models.InvoicePartitionDetail
	if err := json.Unmarshal(data, &ipd); err != nil {
		return errors.Wrap(err, "failed to unmarshal invoice partition detail")
	}

	// Schedule invoice generation
	return h.invoiceEngine.ScheduleInvoiceGeneration(ctx, logger, ipd)
}

func (h *RequestHandler) handleScheduleWatermarkJobs(ctx context.Context, logger log.Logger, data json.RawMessage) error {
	// Get the watermark job run from the message
	var jobRun *models.WatermarkJobRun
	if err := json.Unmarshal(data, &jobRun); err != nil {
		return errors.Wrap(err, "failed to unmarshal watermark job run")
	}

	var watermarkSkus []string
	if len(jobRun.Sku) == 0 {
		now := time.Now().UTC()
		skipCache := false
		allSkus, err := h.pricingEngine.GetAllPricing(ctx, logger, skipCache)
		if err != nil {
			return errors.Wrap(err, "Unable to query pricings for watermark job")
		}

		for _, pricing := range allSkus {
			if (pricing.IsEnabled(now)) && (pricing.MeterType == models.PricingMeterPerHourUnitCharge) {
				watermarkSkus = append(watermarkSkus, pricing.Sku)
			}
		}
	} else {
		watermarkSkus = append(watermarkSkus, jobRun.Sku)
	}

	g, gctx := errgroup.WithContext(ctx)

	// Schedule watermark jobs
	for _, sku := range []string(watermarkSkus) {
		skuToRunWith := sku
		g.Go(func() error {
			return h.usageEngine.ScheduleWatermarkJobs(gctx, logger, jobRun.WithSku(skuToRunWith))
		})
	}

	if err := g.Wait(); err != nil {
		return errors.Wrap(err, "failed to schedule watermark jobs")
	}

	return nil
}

func (h *RequestHandler) handleScheduleZeroOutQuantitiesJobs(ctx context.Context, logger log.Logger, data json.RawMessage) error {
	return h.usageEngine.SendScheduleZeroOutQuantitiesJob(ctx, logger, data)
}

func (h *RequestHandler) handleScheduleHighWatermarkRolloverJob(ctx context.Context, logger log.Logger, data json.RawMessage) error {
	schedulehwRolloverJobHandler := &ScheduleHighWatermarkJobHandler{
		usageEngine:   h.usageEngine,
		pricingEngine: h.pricingEngine,
	}
	return schedulehwRolloverJobHandler.Handle(ctx, logger, data)
}

func (h *RequestHandler) trackError(logger log.Logger, err error, reason string, fields ...kvp.Field) {
	fields = append(fields, kvp.String("reason", reason))
	logger.WithError(err).Error("error while processing request", fields...)
	h.statter.Counter("request_handler.error", stats.Tags{"origin": reason}, int64(1))
}
