package engines

import (
	"context"
	"encoding/json"
	"strconv"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"
)

type InvoiceEngine struct {
	*EngineParams
	invoiceQuerier func() db.ModelQuerier[*models.Invoice]
}

func NewInvoiceEngine(params *EngineParams) *InvoiceEngine {
	return &InvoiceEngine{
		EngineParams: params,
		invoiceQuerier: func() db.ModelQuerier[*models.Invoice] {
			return db.NewQuerier[*models.Invoice](params.db)
		},
	}
}

type InvoiceLister interface {
	GetInvoices(ctx context.Context, logger log.Logger, customerId string) ([]*models.Invoice, error)
}

func (e *InvoiceEngine) GetInvoice(ctx context.Context, logger log.Logger, itemKey models.ItemKey) (*models.Invoice, error) {
	return e.invoiceQuerier().ReadItemWithRetries(ctx, logger, itemKey)
}

func (e *InvoiceEngine) GetInvoices(ctx context.Context, logger log.Logger, customerId string) ([]*models.Invoice, error) {
	partitionKey := models.CustomerIdToInvoicePartitionKey(customerId)

	invoices, err := e.invoiceQuerier().QueryItems(ctx, logger, db.QueryStringAll, partitionKey)
	if err != nil {
		return nil, err
	}

	return invoices, nil
}

func (e *InvoiceEngine) GetSubmittedInvoice(ctx context.Context, logger log.Logger, invoiceDetail *models.InvoicePartitionDetail) (*models.Invoice, error) {
	foundInvoice, err := e.invoiceQuerier().ReadItemWithRetries(ctx, logger, models.NewInvoiceKey(invoiceDetail))
	if err != nil {
		return nil, err
	}

	// Temporarily removing the check for submitted invoice state to handle the case where the invoice state is not updated, even though the emission to Zuora is successful.
	// When that happens, this function will not return the submitted invoice and the late items processing will double charge the customer.
	// Returning the existing invoice, regardless of state, will avoid that.
	if foundInvoice == nil {
		return nil, nil
	}

	logger.Info("GetSubmittedInvoice found invoice",
		kvp.String("db.cosmosdb.partition_key", foundInvoice.Key.PartitionKey),
		kvp.String("db.cosmosdb.id", foundInvoice.Id),
		kvp.String("db.cosmosdb.customer_id", foundInvoice.CustomerId),
		kvp.String("db.cosmosdb.state", string(foundInvoice.State)),
	)

	return foundInvoice, nil
}

func (e *InvoiceEngine) UpsertInvoice(ctx context.Context, logger log.Logger, invoice *models.Invoice) (*models.Invoice, error) {
	// Save the invoice under the customer based partition key (e.g. customer:id:invoices:year:month)
	err := e.db.UpsertWithOptions(ctx, logger, invoice, nil)
	if err != nil {
		return nil, err
	}

	return invoice, nil
}

// Save the invoice key under the active invoices partition key (e.g. invoices:active:year:month)
func (e *InvoiceEngine) UpsertActiveInvoiceItem(ctx context.Context, logger log.Logger, ipd *models.InvoicePartitionDetail, processedAt *time.Time) (*models.ActiveInvoicesItem, error) {
	item := models.NewActiveInvoiceItem(ipd, processedAt)
	err := e.db.UpsertWithOptions(ctx, logger, item, nil)
	if err != nil {
		return nil, err
	}

	return item, err
}

func (e *InvoiceEngine) GetActiveInvoiceItem(ctx context.Context, logger log.Logger, ipd *models.InvoicePartitionDetail, processedAt *time.Time) (*models.ActiveInvoicesItem, error) {
	item := models.NewActiveInvoiceItem(ipd, processedAt)

	queriedItem, err := db.NewQuerier[*models.ActiveInvoicesItem](e.db).ReadItemWithRetries(ctx, logger, item)
	return queriedItem, err
}

func (e *InvoiceEngine) DeleteActiveInvoice(ctx context.Context, logger log.Logger, key models.ItemKey) error {
	err := e.db.DeleteWithOptions(ctx, logger, key, nil)
	return err
}

func (e *InvoiceEngine) UpsertSubmittedInvoiceItem(ctx context.Context, logger log.Logger, ipd *models.InvoicePartitionDetail, submittedAt *time.Time) (*models.SubmittedInvoicesItem, error) {
	item := models.NewSubmittedInvoiceItem(ipd, submittedAt)
	err := e.db.UpsertWithOptions(ctx, logger, item, nil)
	if err != nil {
		return nil, err
	}
	return item, err
}

func (e *InvoiceEngine) UpsertRejectedInvoiceItem(ctx context.Context, logger log.Logger, ipd *models.InvoicePartitionDetail, errorCode string, errorMessage string, rejectedAt *time.Time) (*models.RejectedInvoicesItem, error) {
	item := models.NewRejectedInvoiceItem(ipd, errorCode, errorMessage, rejectedAt)
	err := e.db.UpsertWithOptions(ctx, logger, item, nil)
	if err != nil {
		return nil, err
	}
	return item, err
}

func (e *InvoiceEngine) ScheduleInvoiceGeneration(ctx context.Context, logger log.Logger, ipd *models.InvoicePartitionDetail) error {
	// The invoice partition detail is not guaranteed to be valid, make sure it is before proceeding
	if !ipd.IsValid() {
		return errors.New("invalid invoice partition detail")
	}

	// Custom logger to namespace all subsequent log messages and to include the invoice partition detail
	logger = logger.Named("ScheduleInvoiceGeneration").WithFields(kvp.Any("invoice_partition_detail", ipd))

	// Handle the special case where we're only emitting a single invoice
	if ipd.CustomerId != "" {
		return e.createInvoiceGenerationJob(ctx, logger, models.GetInvoiceItemKey(ipd, models.Active))
	}

	logger.Info("ScheduleInvoiceGeneration Start")
	start := time.Now()

	// Perform an async query to retrieve all active invoice keys for the provided year and month
	partitionKey := models.InvoiceItemPartitionKey(ipd, models.Active)
	queryString := "SELECT * FROM c WHERE IS_NULL(c.ProcessedAt)"
	keysCh, errCh := db.NewQuerier[*models.Key](e.db).QueryItemsAsyncBatch(ctx, logger, queryString, partitionKey)
	success := true
	g, gctx := errgroup.WithContext(ctx)

	// Process batches of keys until all keys have been processed or an error is encountered
	for keys := range keysCh {
		batch := keys
		g.Go(func() error {
			return e.createInvoiceGenerationBatchJob(gctx, logger, batch)
		})
	}

	// Check for query errors; errCh is closed at this point so receiving from it will not block
	if err := <-errCh; err != nil {
		logger.WithError(err).Error("QueryItemsAsyncBatch failed")
		success = false
	}

	// Wait for all processing goroutines to finish
	err := g.Wait()
	if err != nil {
		logger.WithError(err).Error("createInvoiceGenerationBatchJob failed")
		success = false
		err = errors.Wrap(err, "createInvoiceGenerationBatchJob failed")
	}

	// Logging and metrics
	duration := time.Since(start)
	logger.WithFields(kvp.Bool("success", success), kvp.Duration("duration", duration)).Info("ScheduleInvoiceGeneration Finished")
	e.statter.Timing("invoice_engine.schedule_invoice_generation", stats.Tags{"success": strconv.FormatBool(success)}, duration)

	return err
}

func (e *InvoiceEngine) createInvoiceGenerationBatchJob(ctx context.Context, logger log.Logger, keys []*models.Key) error {
	app := e.cfg.AqueductApplication()
	queue := messaging.GetQueueName(models.WorkerTypeInvoiceGeneration, e.cfg.OverrideQueuePrefix)
	keyCount := len(keys)
	logger = logger.WithFields(
		kvp.String("aqueduct.job.app", app),
		kvp.String("aqueduct.job.queue", queue),
		kvp.Int("messaging.batch.message_count", keyCount),
	)

	logger.Info("createInvoiceGenerationBatchJob start")
	start := time.Now()

	// Convert the keys into batch items for Aqueduct
	batch := make([]aqueduct.BatchItem, keyCount)
	var payloadSize int64
	for i, key := range keys {
		payload, err := json.Marshal(key)
		if err != nil {
			return errors.Wrap(err, "createInvoiceGenerationBatchJob failed to marshal key")
		}
		payloadSize += int64(len(payload))
		batch[i] = aqueduct.BatchItem{
			Job: aqueduct.Job{
				App:     app,
				Queue:   queue,
				Payload: payload,
			},
			Opts: messaging.MessageSenderOptions(),
		}
	}

	// Send the batch
	sendStart := time.Now()
	_, err := e.aqueductClient.SendBatch(ctx, batch)
	sendDuration := time.Since(sendStart)
	if err != nil {
		return errors.Wrap(err, "createInvoiceGenerationBatchJob failed to sendBatch")
	}

	// Logging and metrics
	duration := time.Since(start)
	logger.Info("createInvoiceGenerationBatchJob finished",
		kvp.Duration("duration", duration),
		kvp.Int64("messaging.message.payload_size_bytes", payloadSize),
	)
	e.statter.Timing("invoice_engine.create_invoice_generation_batch_job", stats.Tags{}, duration)
	e.statter.Timing("invoice_engine.create_invoice_generation_batch_job.send", stats.Tags{}, sendDuration)
	e.statter.Counter("invoice_engine.create_invoice_generation_batch_job.processed", stats.Tags{}, int64(keyCount))

	return nil
}

func (e *InvoiceEngine) createInvoiceGenerationJob(ctx context.Context, logger log.Logger, key *models.Key) error {
	app := e.cfg.AqueductApplication()
	queue := messaging.GetQueueName(models.WorkerTypeInvoiceGeneration, e.cfg.OverrideQueuePrefix)
	logger = logger.WithFields(
		kvp.String("aqueduct.job.app", app),
		kvp.String("aqueduct.job.queue", queue),
		kvp.Any("key", key),
	)

	logger.Info("createInvoiceGenerationJob start")
	start := time.Now()

	activeInvoice, err := db.NewQuerier[*models.ActiveInvoicesItem](e.db).ReadItem(ctx, logger, key, nil)
	if err != nil {
		return errors.New("failed to read active invoice item")
	}
	if activeInvoice == nil {
		logger.Info("No active invoice item found")
		return nil
	}
	if activeInvoice.ProcessedAt != nil {
		logger.Info("Invoice already processed")
		return nil
	}

	// Convert the key to JSON
	payload, err := json.Marshal(key)
	if err != nil {
		logger.WithError(err).Error("error serializing invoice key")
		return errors.Wrap(err, "createInvoiceGenerationJob failed to marshal key")
	}

	// Create and send job
	job := aqueduct.Job{
		App:     app,
		Queue:   queue,
		Payload: payload,
	}
	sendStart := time.Now()
	_, err = e.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)
	sendDuration := time.Since(sendStart)
	if err != nil {
		logger.WithError(err).Error("createInvoiceGenerationJob failed")
		return errors.Wrap(err, "createInvoiceGenerationJob failed to Send")
	}

	// Logging and metrics
	duration := time.Since(start)
	logger.Info("createInvoiceGenerationJob finished", kvp.Duration("duration", duration))
	e.statter.Timing("invoice_engine.create_invoice_generation_job", stats.Tags{}, duration)
	e.statter.Timing("invoice_engine.create_invoice_generation_job.send", stats.Tags{}, sendDuration)

	return nil
}

func (e *InvoiceEngine) MarkInvoicePartitionDetailProcessed(ctx context.Context, logger log.Logger, ipd *models.InvoicePartitionDetail, processedAt *time.Time) error {
	start := time.Now()

	_, err := e.UpsertActiveInvoiceItem(ctx, logger, ipd, processedAt)

	if err != nil {
		return err
	}

	e.statter.Timing("invoice_engine.mark_invoice_processed",
		stats.Tags{"success": strconv.FormatBool(err == nil)},
		time.Since(start),
	)
	return nil
}

func (e *InvoiceEngine) markInvoiceSubmitted(ctx context.Context, logger log.Logger, invoice *models.Invoice, submittedAt *time.Time) {
	start := time.Now()

	invoice.State = models.Submitted
	_, err := e.UpsertInvoice(ctx, logger, invoice)
	if err != nil {
		logger.WithError(err).Error("failed to save submitted invoice")
	}

	ipd, err := models.InvoicePartitionDetailFromInvoiceKey(invoice.Key)
	if err != nil {
		logger.WithError(err).Error("failed to get partition detail for invoice")
		return
	}

	_, err = e.UpsertSubmittedInvoiceItem(ctx, logger, ipd, submittedAt)
	if err != nil {
		logger.WithError(err).Error("failed to mark invoice submitted")
	}

	e.statter.Timing("invoice_engine.mark_invoice_submitted",
		stats.Tags{"success": strconv.FormatBool(err == nil)},
		time.Since(start),
	)
}

func (e *InvoiceEngine) markInvoiceRejected(ctx context.Context, logger log.Logger, invoice *models.Invoice, sourceError error, rejectedAt *time.Time) {
	start := time.Now()

	invoice.State = models.Rejected
	_, err := e.UpsertInvoice(ctx, logger, invoice)
	if err != nil {
		logger.WithError(err).Error("failed to save rejected invoice")
	}

	ipd, err := models.InvoicePartitionDetailFromInvoiceKey(invoice.Key)
	if err != nil {
		logger.WithError(err).Error("failed to get partition detail for invoice")
		return
	}

	_, err = e.UpsertRejectedInvoiceItem(ctx, logger, ipd, "", sourceError.Error(), rejectedAt)
	if err != nil {
		logger.WithError(err).Error("failed to mark invoice rejected")
	}
	e.statter.Timing("invoice_engine.mark_invoice_rejected",
		stats.Tags{"success": strconv.FormatBool(err == nil)},
		time.Since(start),
	)
}
