package engines

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats" //nolint:staticcheck
	schemas "github.com/github/hydro-client-go/v5/generated/hydro/schemas/hydro/v1"
	protobuf "github.com/golang/protobuf/proto" //nolint:staticcheck
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type AdminEngine struct {
	*EngineParams
}

func NewAdminEngine(params *EngineParams) *AdminEngine {
	return &AdminEngine{
		EngineParams: params,
	}
}

func (e *AdminEngine) CreateProcessDeadLetterQueueRequest(ctx context.Context, logger log.Logger, requestData *models.ProcessDeadLetterQueueData) error {
	request, err := models.NewProcessDeadLetterQueueRequest(requestData)
	if err != nil {
		logger.WithError(err).Error("error serializing request data")
		return err
	}

	return e.createRequest(ctx, logger, request)
}

func (e *AdminEngine) CreateScheduleAzureEmissionRequest(ctx context.Context, logger log.Logger, target *models.AzureUsageDate) error {
	request, err := models.NewScheduleAzureEmissionRequest(target)
	if err != nil {
		logger.WithError(err).Error("error serializing request data")
		return err
	}

	return e.createRequest(ctx, logger, request)
}

func (e *AdminEngine) CreateScheduleInvoiceGenerationRequest(ctx context.Context, logger log.Logger, ipd *models.InvoicePartitionDetail) error {
	request, err := models.NewScheduleInvoiceGenerationRequest(ipd)
	if err != nil {
		logger.WithError(err).Error("error serializing request data")
		return err
	}

	return e.createRequest(ctx, logger, request)
}

func (e *AdminEngine) CreateScheduleWatermarkJobsRequest(ctx context.Context, logger log.Logger, jobRun *models.WatermarkJobRun) error {
	request, err := models.NewScheduleWatermarkJobsRequest(jobRun)
	if err != nil {
		logger.WithError(err).Error("error serializing request data")
		return err
	}

	return e.createRequest(ctx, logger, request)
}

func (e *AdminEngine) ProcessDeadLetterQueue(ctx context.Context, logger log.Logger, queueName string, num int64) error {
	if !messaging.IsDeadLetterQueue(queueName) {
		return errors.New("cannot process from queue that is not a dead letter queue")
	} else if num <= 0 {
		return errors.New("number of messages to process must be greater than 0")
	}

	// Get the original queue name to send messages back to
	originalQueueName := messaging.GetOriginalQueueName(queueName)

	// Augment the logger with the queue names
	logger = logger.WithFields(
		kvp.String("original_queue_name", originalQueueName),
		kvp.String("dead_letter_queue_name", queueName),
		kvp.Int64("number_of_messages_to_process", num),
	)

	// Errors returned in the message handler do not propagate to the worker with the IgnoreJobErr policy.
	// Track it here to ensure we can log and report metrics on it.
	var messageHandlerErr error

	// Define the message handler
	messageHandler := func(ctx context.Context, rr aqueduct.ReceiveResult) error {
		logger.Info("sending message to original queue")
		_, err := e.aqueductClient.Send(ctx, aqueduct.Job{
			App:     rr.App,
			Queue:   originalQueueName,
			Payload: rr.Payload,
		}, messaging.MessageSenderOptions()...)
		logger.Info("done sending message to original queue")
		if err != nil {
			return errors.Wrap(err, "error sending message to original queue")
		}

		return nil
	}

	// Channel to signal when we are done processing
	done := make(chan struct{}, 1)
	defer close(done)

	// Start a separate goroutine to monitor the queue depth on an interval so we can stop processing once the queue is empty
	go e.monitorQueueDepth(ctx, logger, queueName, done)

	// Create the aqueduct worker
	worker, err := messaging.NewMessagingHandler(ctx, e.aqueductClient, e.cfg, logger, e.statter, queueName, messageHandler)
	if err != nil {
		return errors.Wrap(err, "error creating aqueduct worker")
	}

	// Process messages from the designated dead letter queue but stop when the queue is empty
	for i := int64(0); i < num; i++ {
		select {
		case <-done:
			logger.Info("finished processing dead letter queue, queue is empty")
			return nil
		default:
		}

		err := worker.ProcessJob(ctx)

		if err == nil {
			err = messageHandlerErr
		}

		if err != nil {
			logger.WithError(err).Error("failed to re-process dead letter job")
		}

		e.statter.Counter("process_dead_letter_queue",
			stats.Tags{
				"original_queue_name":    originalQueueName,
				"dead_letter_queue_name": queueName,
				"success":                strconv.FormatBool(err == nil),
			},
			int64(1),
		)
	}

	logger.Info("finished processing dead letter queue")
	return nil
}

func (e *AdminEngine) CreateScheduleHighWatermarkRolloverJobRequest(ctx context.Context, logger log.Logger, jobRun *models.HighWatermarkRolloverJobRun) error {
	request, err := models.NewScheduleHighWatermarkRolloverJobRequest(jobRun)
	if err != nil {
		logger.WithError(err).Error("error serializing request data")
		return err
	}

	return e.createRequest(ctx, logger, request)
}

func (e *AdminEngine) createRequest(ctx context.Context, logger log.Logger, request *models.Request) error {
	// Convert the request to JSON
	payload, err := json.Marshal(request)
	if err != nil {
		logger.WithError(err).Error("error serializing request")
		return errors.Wrap(err, "error serializing request")
	}

	// Create job
	job := aqueduct.Job{
		App:     e.cfg.AqueductApplication(),
		Queue:   messaging.GetQueueName(models.WorkerTypeRequestHandler, e.cfg.OverrideQueuePrefix),
		Payload: payload,
	}

	// Send job to Aqueduct
	_, err = e.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)
	if err != nil {
		logger.WithError(err).Error("error sending message to request handler queue")
		return errors.Wrap(err, "error sending message to request handler queue")
	}

	return nil
}

// monitorQueueDepth checks the queue depth on an interval and sends a signal on the done channel when the queue is empty
func (e *AdminEngine) monitorQueueDepth(ctx context.Context, logger log.Logger, queueName string, done chan struct{}) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			depth, err := e.aqueductClient.QueueDepth(ctx, e.cfg.AqueductApplication(), queueName)
			if err != nil {
				logger.WithError(err).Error("monitorQueueDepth: error getting queue depth")
			} else if depth == 0 {
				logger.Info(fmt.Sprintf("monitorQueueDepth: queue %s is empty", queueName))
				done <- struct{}{}
				return
			}
		case <-done:
			logger.Info(fmt.Sprintf("monitorQueueDepth: stop monitoring queue %s", queueName))
			return
		}
	}
}

func (e *AdminEngine) GenerateUsage(
	ctx context.Context,
	logger log.Logger,
	customer *models.Customer,
	orgID int64,
	repoID int64,
	pricing *models.Pricing,
	quantity nano.Nano,
) error {
	chargeLineItem := &models.Item{
		Key:     *customer.Key,
		Pricing: pricing,
		UsageAt: *models.UTCNow(),
		Amounts: &models.Amounts{
			Quantity:               quantity.Int64(),
			AppliedCostPerQuantity: pricing.GetPrice(),
		},
		EntityDetail: &models.EntityDetail{
			CustomerId:     customer.EnterpriseCustomerId,
			OrganizationId: orgID,
			RepositoryId:   repoID,
		},
	}
	customerIDAsInt, _ := strconv.ParseInt(string(chargeLineItem.EntityDetail.CustomerId), 10, 64)
	now := models.NewUsageTimeFromTime(time.Now()).Time

	asHydroMessage := &hydroSchema.Usage{
		Sku:       chargeLineItem.GetSku(),
		Quantity:  models.ToDecimalAmount[int64](chargeLineItem.Quantity),
		SourceUri: models.Charge,
		UsageAt:   timestamppb.New(now),
		Entity: &hydroSchemaEntities.EntityDetail{
			CustomerId:     customerIDAsInt,
			OrganizationId: chargeLineItem.EntityDetail.OrganizationId,
			RepoId:         chargeLineItem.EntityDetail.RepositoryId,
			ActorId:        chargeLineItem.EntityDetail.ActorId,
		},
		// usage requires a UUID. Can make this unique as it's a one-off charge
		// being triggered manually.
		UsageUuid: uuid.NewString(),
	}

	usageAsBytes, err := protobuf.Marshal(asHydroMessage)
	if err != nil {
		logger.WithError(err).Error("Failed to marshal usage")
		return errors.Wrap(err, "Failed to marshal usage")
	}

	envelope := schemas.Envelope{
		Message: usageAsBytes,
	}
	envelopeBytes, err := protobuf.Marshal(&envelope)
	if err != nil {
		logger.WithError(err).Error("Failed to marshal envelope")
		return errors.Wrap(err, "Failed to marshal envelope")
	}

	// Send line items back to the usage ingestion handler
	job := aqueduct.Job{
		App:     e.cfg.AqueductApplication(),
		Queue:   messaging.GetQueueName(models.WorkerTypeUsageIngestion, e.cfg.OverrideQueuePrefix),
		Payload: envelopeBytes,
	}
	_, err = e.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)

	if err != nil {
		l := logger.WithFields(
			kvp.String("aqueduct.job.app", job.App),
			kvp.String("aqueduct.job.queue", job.Queue),
			kvp.String("aqueduct.job.payload", string(usageAsBytes)),
		)
		l.WithError(err).Error("error submitting usage for ingestion")
		return errors.Wrap(err, "error submitting usage for ingestion")
	}

	e.statter.Counter("admin_create_charge.send_usage", stats.Tags{}, int64(1))

	return nil
}
