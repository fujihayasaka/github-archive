package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// ScheduleEmissionsHandler is a handler to schedule emissions.
type ScheduleEmissionsHandler struct {
	cfg            *config.Config
	customerEngine *engines.CustomerEngine
	jobby          *jobs.Jobby
	statter        stats.Client
	tracer         trace.Tracer
}

// NewScheduleEmissionsHandler creates a new ScheduleEmissionsHandler.
func NewScheduleEmissionsHandler(
	cfg *config.Config,
	customerEngine *engines.CustomerEngine,
	jobby *jobs.Jobby,
	statter stats.Client,
	tracer trace.Tracer,
) *ScheduleEmissionsHandler {
	return &ScheduleEmissionsHandler{
		cfg:            cfg,
		customerEngine: customerEngine,
		jobby:          jobby,
		statter:        statter,
		tracer:         tracer,
	}
}

// ProcessMessage takes an aqueduct message for scheduling emissions.
func (h *ScheduleEmissionsHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	ctx, sp := h.tracer.Start(ctx, "ScheduleEmissionsHandler.ProcessMessage")
	defer sp.End()

	var msg *models.ScheduleEmissionsJob
	if err := json.Unmarshal(rr.Payload, &msg); err != nil {
		logger.WithError(err).Error("Failed to unmarshal message")
		return fmt.Errorf("failed to unmarshal message: %w", err)
	}

	logger = logger.WithFields(msg.GetLoggerFields()...)
	logger.Info("scheduleEmissionsHandler start", kvp.String("gh.aqueduct.job.payload", fmt.Sprintf("%+v", *msg)))
	start := time.Now()

	// Get all customers with metered licensing model.
	licensingModel := models.LicensingModelMetered
	sdlcTrial := false
	customers, err := h.customerEngine.GetAll(ctx, logger, &licensingModel, &sdlcTrial)
	customersCount := len(customers)
	if err != nil {
		err := fmt.Errorf("failed to get customers: %w", err)
		h.trackError(err, "get-customers-error", sp, logger)
		return err
	}

	logger = logger.WithFields(kvp.Int("messaging.batch.message_count", customersCount))

	// Create a batch of publish emission jobs for each customer.
	payloads := make([][]byte, customersCount)
	for i, customer := range customers {
		payload, err := json.Marshal(models.PublishEmissionJob{
			CustomerID: customer.IDToUInt64(),
			UsageTime:  msg.UsageTime,
		})
		if err != nil {
			err := fmt.Errorf("failed to marshal payload: %w", err)
			h.trackError(err, "marshal-payload-error", sp, logger)
			continue
		}
		payloads[i] = payload
	}

	// Send the batch
	sendStart := time.Now()
	_, err = h.jobby.EnqueueBatch(ctx, jobs.JobNamePublishEmission, queues.QueuePublishEmission, payloads)
	sendDuration := time.Since(sendStart)
	if err != nil {
		err = fmt.Errorf("failed to send batch: %w", err)
		h.trackError(err, "send-batch-error", sp, logger)
		return err
	}

	// Logging and metrics
	duration := time.Since(start)
	logger.Info("scheduleEmissionsHandler finished",
		kvp.Duration("duration", duration),
	)
	h.statter.Timing("schedule_emissions_handler.duration", stats.Tags{}, duration)
	h.statter.Timing("schedule_emissions_handler.batch.send", stats.Tags{}, sendDuration)
	h.statter.Counter("schedule_emissions_handler.batch.processed", stats.Tags{}, int64(customersCount))

	return nil
}

func (h *ScheduleEmissionsHandler) trackError(err error, origin string, span trace.Span, logger log.Logger) {
	h.statter.Counter("schedule_emissions_error",
		stats.Tags{"origin": origin},
		int64(1),
	)
	logger.WithError(err).Error("error processing ScheduleEmissions message")
	span.RecordError(err)
	span.SetStatus(codes.Error, origin)
}
