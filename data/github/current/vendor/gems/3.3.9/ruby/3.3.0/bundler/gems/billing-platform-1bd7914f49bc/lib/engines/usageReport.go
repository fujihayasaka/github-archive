package engines

import (
	"context"
	"encoding/json"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

type UsageReportEngineInterface interface {
	ActorHasActiveUsageReportExportForCustomer(ctx context.Context, logger log.Logger, customerID string, actorID int64) (bool, error)
	CreateUsageReportExport(ctx context.Context, logger log.Logger, input *proto.QueueUsageReportExportRequest) (*models.UsageReportExport, error)
	MigratePendingUsageReportToLoading(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport, operationUUID string) (*models.UsageReportExport, error)
	MigrateLoadingUsageReportToFailed(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport) (*models.UsageReportExport, error)
	MigrateLoadingUsageReportToCompleted(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport, blobURLs []string) (*models.UsageReportExport, error)
	MigrateThrottledUsageReportToPending(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport) (*models.UsageReportExport, error)
	GetActiveUsageReportExports(ctx context.Context, logger log.Logger) ([]*models.UsageReportExport, error)
	PublishUsageReportMessages(ctx context.Context, logger log.Logger, usageReportExports []*models.UsageReportExport) error
	PublishUsageReportRequestNotification(logger log.Logger, hydroPublisher interfaces.HydroPublisher, usageReportExport *models.UsageReportExport, success bool) error
	UsageReportRequestActive(ctx context.Context, logger log.Logger, key *models.Key) (bool, error)
	IsExportOperationAlreadyCompleted(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport) bool
	IsExportOperationAlreadyFailed(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport) bool
}

type UsageReportEngine struct {
	*EngineParams
}

func NewUsageReportEngine(params *EngineParams) UsageReportEngineInterface {
	return &UsageReportEngine{
		EngineParams: params,
	}
}

// Check to see if the actor has an active usage report export request for the customer
func (e *UsageReportEngine) ActorHasActiveUsageReportExportForCustomer(ctx context.Context, logger log.Logger, customerID string, actorID int64) (bool, error) {
	usageReportExport, err := db.NewQuerier[*models.UsageReportExport](e.db).ReadItem(ctx, logger, models.NewActiveUsageReportKey(customerID, actorID), nil)
	if err != nil {
		return false, err
	}

	if usageReportExport == nil {
		return false, nil
	}

	return true, nil
}

// Initially create a usage report in the pending state for the customer
// as the export operation has not been executed yet
func (e *UsageReportEngine) CreateUsageReportExport(ctx context.Context, logger log.Logger, input *proto.QueueUsageReportExportRequest) (*models.UsageReportExport, error) {
	usageReportExport := models.NewPendingUsageReportExport(input)

	err := e.db.CreateWithOptions(ctx, logger, usageReportExport, nil)
	if err != nil {
		return nil, err
	}

	return usageReportExport, nil
}

// Update the status and operation UUID of the usage report to loading
func (e *UsageReportEngine) MigratePendingUsageReportToLoading(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport, operationUUID string) (*models.UsageReportExport, error) {
	usageReportExport.Status = models.UsageReportExportStatusLoading
	usageReportExport.ExportOperationUUID = operationUUID

	err := e.db.UpsertWithOptions(ctx, logger, usageReportExport, nil)
	if err != nil {
		return nil, err
	}

	return usageReportExport, nil
}

// Delete the loading usage report and migrate the data to a failed usage report partition on the customer
func (e *UsageReportEngine) MigrateLoadingUsageReportToFailed(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport) (*models.UsageReportExport, error) {
	// remove the usage report from the active partition
	err := e.db.DeleteWithOptions(ctx, logger, usageReportExport, nil)
	if err != nil {
		return nil, err
	}

	failedUsageReportExport := models.NewFailedUsageReportExport(usageReportExport)
	err = e.db.CreateWithOptions(ctx, logger, failedUsageReportExport, nil)
	if err != nil {
		return nil, err
	}

	return failedUsageReportExport, nil
}

// Delete the loading usage report and migrate the data to a completed usage report partition on the customer
func (e *UsageReportEngine) MigrateLoadingUsageReportToCompleted(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport, blobURLs []string) (*models.UsageReportExport, error) {
	// remove the usage report from the active partition
	err := e.db.DeleteWithOptions(ctx, logger, usageReportExport, nil)
	if err != nil {
		return nil, err
	}

	usageReportExport.ExportBlobs = blobURLs

	completedUsageReportExport := models.NewCompletedUsageReportExport(usageReportExport)
	err = e.db.CreateWithOptions(ctx, logger, completedUsageReportExport, nil)
	if err != nil {
		return nil, err
	}

	return completedUsageReportExport, nil
}

// Check if the export operation has already been completed
func (e *UsageReportEngine) IsExportOperationAlreadyCompleted(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport) bool {
	querier := db.NewQuerier[*models.UsageReportExport](e.db)

	// queries the DB for a document with PK of customer:[customerID]:usageReportExports:completed
	// and an ID of the export operation UUID
	item, err := querier.ReadItem(ctx, logger, models.NewCompletedUsageReportKey(usageReportExport), nil)

	if err != nil {
		return false
	}

	if item == nil {
		return false
	}

	return true
}

// Check if the export operation has already failed
func (e *UsageReportEngine) IsExportOperationAlreadyFailed(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport) bool {
	querier := db.NewQuerier[*models.UsageReportExport](e.db)

	// queries the DB for a document with PK of customer:[customerID]:usageReportExports:failed
	// and an ID of the export operation UUID
	item, err := querier.ReadItem(ctx, logger, models.NewFailedUsageReportKey(usageReportExport), nil)

	if err != nil {
		return false
	}

	if item == nil {
		return false
	}

	return true
}

// Update the status of the throttled usage report to pending to allow it to be re-executed by the worker
func (e *UsageReportEngine) MigrateThrottledUsageReportToPending(ctx context.Context, logger log.Logger, usageReportExport *models.UsageReportExport) (*models.UsageReportExport, error) {
	usageReportExport.Status = models.UsageReportExportStatusPending
	usageReportExport.ExportOperationUUID = ""

	err := e.db.UpsertWithOptions(ctx, logger, usageReportExport, nil)
	if err != nil {
		return nil, err
	}

	return usageReportExport, nil
}

// Get all active usage report export requests (pending and loading)
func (e *UsageReportEngine) GetActiveUsageReportExports(ctx context.Context, logger log.Logger) ([]*models.UsageReportExport, error) {
	querier := db.NewQuerier[*models.UsageReportExport](e.db)
	usageReportExports, err := querier.QueryItems(ctx, logger, db.QueryStringAll, models.UsageReportExportsActivePK)
	return usageReportExports, err
}

func (e *UsageReportEngine) PublishUsageReportMessages(ctx context.Context, logger log.Logger, usageReportExports []*models.UsageReportExport) error {
	for _, usageReportExport := range usageReportExports {
		payload, err := json.Marshal(usageReportExport)
		if err != nil {
			logger.WithError(err).Error("error serializing usage report export", kvp.String("id", usageReportExport.Id))
			continue
		}

		job := aqueduct.Job{
			App:     e.cfg.AqueductApplication(),
			Queue:   messaging.GetQueueName(models.WorkerTypeUsageReport, e.cfg.OverrideQueuePrefix),
			Payload: payload,
		}

		_, err = e.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)
		if err != nil {
			logger.WithError(err).Error("error publishing usage report job", kvp.String("id", usageReportExport.Id))
			e.statter.Counter("publish_usage_report_job.failure", stats.Tags{"type": string(usageReportExport.Status)}, int64(1))
			continue
		}

		e.statter.Counter("publish_usage_report_job.success", stats.Tags{"type": string(usageReportExport.Status)}, int64(1))
	}

	return nil
}

func (e *UsageReportEngine) PublishUsageReportRequestNotification(logger log.Logger, hydroPublisher interfaces.HydroPublisher, usageReportExport *models.UsageReportExport, success bool) error {
	usageReportRequestNotification := hydroSchema.UsageReportRequestNotification{
		ActorId:      usageReportExport.ActorId,
		BlobUrls:     usageReportExport.ExportBlobs,
		CustomerId:   usageReportExport.CustomerID,
		Success:      success,
		StartDate:    usageReportExport.StartDate.Unix(),
		EndDate:      usageReportExport.EndDate.Unix(),
		IsStafftools: usageReportExport.IsStafftools,
	}

	err := hydroPublisher.Publish(&usageReportRequestNotification)
	if err != nil {
		logger.WithError(err).Error("failed to publish usage report export notification",
			kvp.String("exportId", usageReportExport.Id),
			kvp.String("customerId", usageReportExport.CustomerID),
			kvp.Bool("success", success),
		)
		return errors.Wrap(err, "failed to publish usage report export notification")
	} else {
		logger.Info("published usage report export notification",
			kvp.String("exportId", usageReportExport.Id),
			kvp.String("customerId", usageReportExport.CustomerID),
			kvp.Bool("success", success),
		)
	}
	return nil
}

func (e *UsageReportEngine) UsageReportRequestActive(ctx context.Context, logger log.Logger, key *models.Key) (bool, error) {
	querier := db.NewQuerier[*models.UsageReportExport](e.db)
	item, err := querier.ReadItem(ctx, logger, key, nil)

	if err != nil {
		return false, err
	}

	if item == nil {
		return false, nil
	}

	return true, nil
}
