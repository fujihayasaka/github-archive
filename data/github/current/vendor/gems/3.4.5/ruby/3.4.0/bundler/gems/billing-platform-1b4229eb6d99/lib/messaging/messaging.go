// Package messaging provides a messaging client and handlers for aqueduct jobs
package messaging

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
)

// DeadLetterPayload contains the payload of a dead letter message
// It is used to send a message to a dead letter queue
// The payload contains the original queue name and the failed payload
type DeadLetterPayload struct {
	SourceQueueName string
	FailedPayload   []byte
}

// NewDeadLetterPayload creates a new DeadLetterPayload
func NewDeadLetterPayload(
	sourceQueueName string,
	failedPayload []byte,
) *DeadLetterPayload {
	return &DeadLetterPayload{
		SourceQueueName: sourceQueueName,
		FailedPayload:   failedPayload,
	}
}

// NewMessagingClient creates a new messaging client
func NewMessagingClient(_ context.Context, cfg *config.Config, statter stats.Client) (aqueduct.Client, error) {
	statsConfig, err := aqueduct.NewStatsConfig(
		aqueduct.WithStatsClient(statter),
	)
	if err != nil {
		return nil, fmt.Errorf("could not create stats config for aqueduct worker: %w", err)
	}

	opts := []aqueduct.ClientOption{
		aqueduct.WithClientStats(statsConfig),
		// aqueduct.WithClientLogger(cfg.Logger()),
	}

	if cfg.AqueductApiKey != "" {
		opts = append(opts, aqueduct.WithAPIKey(cfg.AqueductApiKey))
	}

	client, err := aqueduct.NewClient(cfg.AqueductAddress, opts...)
	if err != nil {
		return nil, fmt.Errorf("could not create client for aqueduct sender: %w", err)
	}

	return client, nil
}

// NewMessagingHandler creates a new messaging handler to process jobs
func NewMessagingHandler(ctx context.Context, client aqueduct.Client, cfg *config.Config, logger log.Logger, statter stats.Client, queueName string, handler aqueduct.JobHandler) (*aqueduct.Worker, error) {
	logger.Info("initializing messaging", kvp.String("appname", cfg.AqueductApplication()), kvp.String("environment", cfg.Environment), kvp.Bool("isProd", cfg.IsProduction()))
	statsConfig, err := aqueduct.NewStatsConfig(
		aqueduct.WithStatsClient(statter),
	)
	if err != nil {
		return nil, fmt.Errorf("could not create stats config for aqueduct worker: %w", err)
	}

	heartbeatConfig, err := aqueduct.NewHeartbeatConfig(
		aqueduct.WithHeartbeatInterval(5 * time.Second),
	)
	if err != nil {
		return nil, fmt.Errorf("could not create heartbeat config for aqueduct worker: %w", err)
	}

	depth, err := client.QueueDepth(context.Background(), cfg.AqueductApplication(), queueName)
	if err != nil {
		panic(fmt.Errorf("error sending %w", err))
	}

	logger.Info("queue depth",
		kvp.String("aqueduct.app", cfg.AqueductApplication()),
		kvp.String("aqueduct.queue.name", queueName),
		kvp.Int64("aqueduct.queue.depth", depth),
	)

	worker, err := aqueduct.NewWorker(
		client,
		cfg.AqueductApplication(), []string{queueName},
		handler,
		aqueduct.WithLogger(logger.WithLevel(log.InfoLevel)), // force log level INFO to avoid spamming the logs in development
		aqueduct.WithWorkerStats(statsConfig),
		aqueduct.WithJobErrorPolicy(aqueduct.IgnoreJobErr), // not sending a Failure ack will trigger a retry
		aqueduct.WithHeartbeatConfig(heartbeatConfig),
	)
	if err != nil {
		return nil, errors.Wrap(err, "could not create aqueduct worker")
	}

	return worker, nil
}

func MessageSenderOptions() []aqueduct.SendOption {
	return []aqueduct.SendOption{
		// aqueduct.WithJobRedeliveryTimeoutSeconds(int(cfg.JobRedeliveryTimeout.Seconds())),
		// aqueduct.WithJobMaxRedeliveryAttempts(cfg.JobMaxRedeliveryAttempts),
		// aqueduct.WithJobRedeliveryTimeoutSeconds(10),
		aqueduct.WithJobMaxRedeliveryAttempts(2),
	}
}

func CreateReadinessProbeFile() error {
	_, err := os.Create("/tmp/consumer_healthy") //nolint:gosec
	if err != nil {
		return errors.Wrap(err, "creating consumer_healthy file for readiness probe")
	}

	return nil
}

const (
	deadLetterQueuePrefix                       = "dead-letter-"
	queueUsageBillingPlatform                   = "hydro_billingplatform_v1_usage" // TODO: this should be in config
	queueCustomerHourlyRollups                  = "customer-hourly-rollups"
	queueCustomerDailyRollups                   = "customer-daily-rollups"
	queueCustomerMonthlyRollups                 = "customer-monthly-rollups"
	queueCustomerYearlyRollups                  = "customer-yearly-rollups"
	queueAzureEmission                          = "azure-emission"
	queueRequestHandler                         = "request-handler"
	queueInvoiceGeneration                      = "invoice-generation"
	queueCustomerAzureEmissionDailyRollup       = "customer-azure-emission-daily-rollup"
	queueCustomerZuoraEmissionDailyRollup       = "customer-zuora-emission-daily-rollup"
	queueWorkerTypeWatermarkHandler             = "watermark-handler"
	queueWorkerTypeZeroOutQuantitiesHandler     = "zero-out-quantities-handler"
	queueWorkerTypeHighWatermarkRolloverHandler = "high-watermark-rollover-handler"
	queueWorkerUsageReport                      = "usage-report"
	queueWorkerUsageReportFanOut                = "usage-report-fan-out"
	queueEmissionHandler                        = "emission-handler"
	queueFailedRollups                          = "failed-rollups"
	queueDiscountStateUpdate                    = "discount-state-update"
	queueZuoraBatchEmissionHandler              = "zuora-batch-emission-handler"
	queueWorkerThrottledWatermark               = "throttled-watermark"
	queueBulkUsageEmission                      = "bulk-usage-emission"
	queueBudgetState                            = "budget-state"
)

func GetQueueNameDefault(workerType models.WorkerType) string {
	return GetQueueName(workerType, "")
}

func GetQueueName(workerType models.WorkerType, queuePrefix string) string {
	var selectedName string
	switch workerType {
	case models.WorkerTypeUsageIngestion:
		selectedName = queueUsageBillingPlatform
	case models.WorkerTypeCustomerDailyRollup:
		selectedName = queueCustomerDailyRollups
	case models.WorkerTypeCustomerMonthlyRollup:
		selectedName = queueCustomerMonthlyRollups
	case models.WorkerTypeCustomerYearlyRollup:
		selectedName = queueCustomerYearlyRollups
	case models.WorkerTypeEmissionHandler:
		selectedName = queueEmissionHandler
	case models.WorkerTypeAzureEmission:
		selectedName = queueAzureEmission
	case models.WorkerTypeRequestHandler:
		selectedName = queueRequestHandler
	case models.WorkerTypeInvoiceGeneration:
		selectedName = queueInvoiceGeneration
	case models.WorkerTypeCustomerAzureEmissionDailyRollup:
		selectedName = queueCustomerAzureEmissionDailyRollup
	case models.WorkerTypeCustomerZuoraEmissionDailyRollup:
		selectedName = queueCustomerZuoraEmissionDailyRollup
	case models.WorkerTypeZuoraBatchEmissionHandler:
		selectedName = queueZuoraBatchEmissionHandler
	case models.WorkerTypeWatermarkHandler:
		selectedName = queueWorkerTypeWatermarkHandler
	case models.WorkerTypeZeroOutQuantities:
		selectedName = queueWorkerTypeZeroOutQuantitiesHandler
	case models.WorkerTypeHighWatermarkRolloverHandler:
		selectedName = queueWorkerTypeHighWatermarkRolloverHandler
	case models.WorkerTypeUsageReport:
		selectedName = queueWorkerUsageReport
	case models.WorkerTypeUsageReportFanOut:
		selectedName = queueWorkerUsageReportFanOut
	case models.WorkerTypeFailedRollups:
		selectedName = queueFailedRollups
	case models.WorkerTypeDiscountStateUpdate:
		selectedName = queueDiscountStateUpdate
	case models.WorkerTypeThrottledWatermark:
		selectedName = queueWorkerThrottledWatermark
	case models.WorkerTypeBulkUsageEmission:
		selectedName = queueBulkUsageEmission
	case models.WorkerTypeBudgetState:
		selectedName = queueBudgetState
	default:
		panic(fmt.Sprintf("unknown worker type: %s", workerType))
	}

	if queuePrefix != "" {
		selectedName = fmt.Sprintf("%s-%s", queuePrefix, selectedName)
	}

	return selectedName
}

func GetOriginalQueueName(deadLetterQueueName string) string {
	return strings.Replace(deadLetterQueueName, deadLetterQueuePrefix, "", 1)
}

func GetDeadLetterQueueName(originalQueueName string) string {
	if IsDeadLetterQueue(originalQueueName) {
		return originalQueueName
	}
	return fmt.Sprintf("%s%s", deadLetterQueuePrefix, originalQueueName)
}

func IsDeadLetterQueue(queueName string) bool {
	return strings.HasPrefix(queueName, deadLetterQueuePrefix)
}

func GetFailedRollupsQueueName() string {
	return queueFailedRollups
}

func GetBudgetStateUpdateRetriesQueueName() string {
	return queueBudgetState
}
