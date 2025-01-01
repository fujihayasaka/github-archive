package engines

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
)

type AzureEmissionEngine struct {
	*EngineParams
}

func NewAzureEmissionEngine(params *EngineParams) *AzureEmissionEngine {
	return &AzureEmissionEngine{
		EngineParams: params,
	}
}

func (e *AzureEmissionEngine) GetAzureEmission(ctx context.Context, logger log.Logger, ipd *models.AzureEmissionPartitionDetail) (*models.AzureEmission, error) {
	return db.NewQuerier[*models.AzureEmission](e.db).ReadItemWithRetries(ctx, logger, models.NewAzureEmissionKey(ipd))
}

func (e *AzureEmissionEngine) UpsertAzureEmission(ctx context.Context, logger log.Logger, azureEmission *models.AzureEmission) (*models.AzureEmission, error) {
	err := e.db.UpsertWithOptions(ctx, logger, azureEmission, nil)
	if err != nil {
		return nil, err
	}

	return azureEmission, nil
}

func (e *AzureEmissionEngine) GetAzureUsageItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error) {
	// This partition key looks at yesterday's date
	usageTimePK := upd.UsageTime.ToPartitionKey(upd.ActiveType)
	usageItems, err := db.NewQuerier[*models.Item](e.db).QueryItems(ctx, logger, db.QueryStringAllNontotal, fmt.Sprintf("%s:%s", usageTimePK, "byAzureEmission"))
	if err != nil {
		return nil, errors.Wrap(err, "error querying usage items by azure emission")
	}

	return usageItems, nil
}

// Entry point for azure emission that is responsible for creating a fan out of jobs for each usage record in the azure emission rollup
func (e *AzureEmissionEngine) ScheduleAzureEmission(ctx context.Context, logger log.Logger, usageDate *models.AzureUsageDate) error {
	start := time.Now()
	defer func() {
		duration := time.Since(start)
		e.statter.Timing("azure_emission_dispatcher_handler", stats.Tags{}, duration)
	}()

	partitionDetail, err := models.GetPartitionDetailForDailyAzureEmission(usageDate)
	if err != nil {
		logger.WithError(err).Error("error creating usage partition detail")
		return err
	}

	logger.Info("created partition detail for azure emission usages", kvp.Any("partitionDetail", partitionDetail))

	// assume all usage that comes from this partition can be emitted to Azure
	usages, err := e.GetAzureUsageItems(ctx, logger, partitionDetail)
	if err != nil {
		logger.WithError(err).Error("error getting line items for partition", kvp.Any("partitionDetail", partitionDetail))
		return err
	}

	// If we are targeting a specific customer, filter the usages to only include that customer.
	// We chose to filter out the specific customer usages here instead of querying the customer usage directly
	// as we already know that all usage in this azure usage partition is ready for azure emission.
	// If we were to instead query the customer usage directly, we would have to query the customer data, ensure they are able to emit to azure
	// and then query their usage data. This would also expose us to edge cases like customers switching from Azure to Zuora and vice versa and double emitting.
	if usageDate.CustomerId != "" {
		usages = filterUsagesByCustomerID(usages, usageDate.CustomerId)
		logger.Info("queried usages to emit to azure for customer", kvp.Any("num_usages", len(usages)), kvp.String("customerId", usageDate.CustomerId))
	} else {
		logger.Info("queried usages to emit to azure", kvp.Any("num_usages", len(usages)))
	}

	for _, usage := range usages {
		payload, err := json.Marshal(usage)
		if err != nil {
			logger.WithError(err).Error("error serializing usage", kvp.Any("usage", usage))
			continue
		}

		job := aqueduct.Job{
			App:     e.cfg.AqueductApplication(),
			Queue:   messaging.GetQueueName(models.WorkerTypeAzureEmission, e.cfg.OverrideQueuePrefix),
			Payload: payload,
		}
		_, err = e.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)

		// Logging and metrics
		l := logger.WithFields(
			kvp.String("aqueduct.job.app", job.App),
			kvp.String("aqueduct.job.queue", job.Queue),
			kvp.String("aqueduct.job.payload", string(job.Payload)),
		)
		if err != nil {
			l.WithError(err).Error("error submitting azure emission job")
			continue
		}

		l.Info("submitted azure emission job for usage", kvp.String("usage_id", usage.Id))
		e.statter.Counter("published_azure_emission", stats.Tags{}, int64(1))
	}

	logger.Info("azure emission dispatcher fanout finished")

	return nil
}

func filterUsagesByCustomerID(usages []*models.Item, customerID string) []*models.Item {
	filteredUsages := make([]*models.Item, 0, len(usages))
	for _, usage := range usages {
		if usage.GetCustomerId() == customerID {
			filteredUsages = append(filteredUsages, usage)
		}
	}
	return filteredUsages
}
