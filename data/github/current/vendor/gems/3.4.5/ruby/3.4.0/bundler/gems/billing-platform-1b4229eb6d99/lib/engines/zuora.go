package engines

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"sort"
	"sync"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/zuora"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
)

const (
	ZuoraEmissionMaxRetries = 3
	ZuoraMaxNumberOfRecords = 16 // original value was 1000,  We will need to modify this prior to go live or put in a config
	ZuoraMaxPayloadSize     = 2 * 1024 * 1024
)

var batchIDMutex sync.Mutex

//go:generate pegomock generate -o ../../testing/fakes/mock_zuora_engine.go --self_package=fakes --package=fakes ZuoraEngineInterface
type ZuoraEngineInterface interface {
	GetZuoraEmissions(ctx context.Context, logger log.Logger, customerId string, year int64, month int64, day int64) ([]*models.Emission, error)
	EmitToZuora(ctx context.Context, logger log.Logger, enterpriseCustomer *models.Customer, customer *models.Customer, invoice *models.Invoice, submittedInvoice *models.Invoice) error
	EmitDailyToZuora(ctx context.Context, logger log.Logger, customer *models.Customer, enterpriseCustomer *models.Customer, emission *models.Emission) error
	GetEmission(ctx context.Context, logger log.Logger, ipd *models.EmissionPartitionDetail) (*models.Emission, error)
	UpsertEmission(ctx context.Context, logger log.Logger, emission *models.Emission) (*models.Emission, error)
	HasItemBeenEmitted(ctx context.Context, logger log.Logger, item *models.ActiveUsageItem) (bool, error)
	ProcessDailyZuoraBatch(ctx context.Context, logger log.Logger, emissionDateTime models.UsageTime, customer *models.Customer, enterpriseCustomer *models.Customer, emission *models.Emission) error
	GetZuoraEmissionBatch(ctx context.Context, logger log.Logger, partitionDetail *models.ZuoraEmissionBatchPartitionDetail) ([]*models.ZuoraEmissionBatch, error)
	EmitDailyBatchToZuora(ctx context.Context, logger log.Logger, usageRecords []zuora.UploadUsageRecord) error
	GetZuoraEmissionBatchStatus(ctx context.Context, logger log.Logger, partitionDetail *models.ZuoraEmissionBatchStatusPartitionDetail) ([]*models.ZuoraEmissionBatchStatus, error)
	UpsertZuoraEmissionBatchStatus(ctx context.Context, logger log.Logger, batchStatus *models.ZuoraEmissionBatchStatus) (*models.ZuoraEmissionBatchStatus, error)
	ScheduleZuoraBatchEmission(ctx context.Context, logger log.Logger, zuoraBatchPayload *models.ZuoraBatchEmissionPayload) error
}

type ZuoraEngine struct {
	*EngineParams
	client                *zuora.Client
	costCenterEngine      CostCenterEngineInterface
	invoiceEngine         *InvoiceEngine
	productEngine         ProductEngineInterface
	emissionQuerier       interfaces.Querier[*models.Emission]
	emissionStatusQuerier interfaces.Querier[*models.ZuoraEmissionBatchStatus]
	emissionbatchQuerier  interfaces.Querier[*models.ZuoraEmissionBatch]
}

func NewZuoraEngine(
	params *EngineParams,
	client *zuora.Client,
	costCenterEngine CostCenterEngineInterface,
	invoiceEngine *InvoiceEngine,
	productEngine ProductEngineInterface,
) ZuoraEngineInterface {
	return &ZuoraEngine{
		EngineParams:          params,
		client:                client,
		costCenterEngine:      costCenterEngine,
		invoiceEngine:         invoiceEngine,
		productEngine:         productEngine,
		emissionQuerier:       db.NewQuerier[*models.Emission](params.db),
		emissionStatusQuerier: db.NewQuerier[*models.ZuoraEmissionBatchStatus](params.db),
		emissionbatchQuerier:  db.NewQuerier[*models.ZuoraEmissionBatch](params.db),
	}
}

// Add this constructor for dependency injection (primarily used in tests)
func newZuoraEngineWithQuerier(
	params *EngineParams,
	client *zuora.Client,
	costCenterEngine CostCenterEngineInterface,
	invoiceEngine *InvoiceEngine,
	productEngine ProductEngineInterface,
	emissionquerier interfaces.Querier[*models.Emission],
	emissionstatushquerier interfaces.Querier[*models.ZuoraEmissionBatchStatus],
	emissionbatchquerier interfaces.Querier[*models.ZuoraEmissionBatch],
) *ZuoraEngine {
	return &ZuoraEngine{
		EngineParams:          params,
		client:                client,
		costCenterEngine:      costCenterEngine,
		invoiceEngine:         invoiceEngine,
		productEngine:         productEngine,
		emissionQuerier:       emissionquerier,
		emissionStatusQuerier: emissionstatushquerier,
		emissionbatchQuerier:  emissionbatchquerier,
	}
}

func (e *ZuoraEngine) GetZuoraEmissions(ctx context.Context, logger log.Logger, customerId string, year int64, month int64, day int64) ([]*models.Emission, error) {
	emissionTarget := &models.EmissionTarget{
		Year:  year,
		Month: month,
		Day:   day,
	}

	emissionPartitionDetail, err := models.GetPartitionDetailForEmission(emissionTarget, customerId)
	if err != nil {
		return nil, err
	}

	partitionKey := emissionPartitionDetail.ToEmissionPartitionKey()
	id := fmt.Sprintf("%s:%d", partitionKey, day)

	queryString := fmt.Sprintf("%s WHERE c.id = \"%s\" and c.Status = %d", db.QueryStringAll, id, models.EmissionCompleted)
	emissions, err := e.emissionQuerier.QueryItems(ctx, logger, queryString, partitionKey)
	if err != nil {
		return nil, err
	}

	return emissions, nil
}

func (e *ZuoraEngine) EmitToZuora(ctx context.Context, logger log.Logger, enterpriseCustomer *models.Customer, customer *models.Customer, invoice *models.Invoice, submittedInvoice *models.Invoice) error {
	start := time.Now()
	logger = logger.WithFields(
		append(enterpriseCustomer.GetLoggerFields(), kvp.String("invoiceCustomerId", customer.GetCustomerId()))...,
	)

	if !enterpriseCustomer.ForZuora() {
		e.trackEmissionSkipped("customer.not_zuora_customer")
		logger.Info("Skipping sending usage to Zuora for customer, not a Zuora customer")
		return nil
	}

	// Skip emission if customer has no ZuoraAccountNumber as Zuora API will return 400 if the field is missing
	if !enterpriseCustomer.HasZuoraAccountNumber() {
		e.trackEmissionSkipped("customer.missing_zuora_account_number")
		logger.Info("Skipping sending usage to Zuora for customer, missing Zuora account number")
		return nil
	}

	// Build the usage records
	buildUsageRecordsStart := time.Now()

	currentUsageRecords, err := e.buildUsageRecords(ctx, logger, *enterpriseCustomer, *customer, invoice)
	if err != nil {
		e.trackEmissionError("build_usage_records_error")
		logger.WithError(err).Error("Failed to build usage records")
		return errors.Wrap(err, "failed to build usage records")
	}
	submittedUsageRecords, err := e.buildUsageRecords(ctx, logger, *enterpriseCustomer, *customer, submittedInvoice)
	if err != nil {
		e.trackEmissionError("build_usage_records_error")
		logger.WithError(err).Error("Failed to build usage records")
		return errors.Wrap(err, "failed to build usage records")
	}
	logger = logger.WithFields(
		kvp.Int("currentUsageRecordsCount", len(currentUsageRecords)),
		kvp.String("currentUsageRecords", fmt.Sprintf("%+v", currentUsageRecords)),
		kvp.Int("submittedUsageRecordsCount", len(submittedUsageRecords)),
		kvp.String("submittedUsageRecords", fmt.Sprintf("%+v", submittedUsageRecords)),
	)
	allUsageRecords := diffUsageRecords(currentUsageRecords, submittedUsageRecords)
	usageRecords := make([]zuora.UploadUsageRecord, 0, len(allUsageRecords))
	for _, usageRecord := range allUsageRecords {
		usageRecords = append(usageRecords, usageRecord)
	}

	if len(usageRecords) == 0 {
		e.trackEmissionSkipped("customer.no_usage_records_to_send")
		logger.Info("Skipping sending usage to Zuora for customer, no usage records to upload")
		return nil
	}
	e.trackEmissionTiming("build_usage_records", time.Since(buildUsageRecordsStart))
	logger = logger.WithFields(
		kvp.Int("usageRecordsCount", len(usageRecords)),
		kvp.String("usageRecords", fmt.Sprintf("%+v", usageRecords)),
	)

	// Call the Zuora API
	var lastError error
	for retryCount := 0; retryCount < ZuoraEmissionMaxRetries; retryCount++ {
		uploadStart := time.Now()
		response, err := e.client.UsageService.UploadUsage(usageRecords)
		if err == nil {
			e.invoiceEngine.markInvoiceSubmitted(ctx, logger, invoice, &uploadStart)
			e.trackEmissionTiming("upload_usage_success", time.Since(uploadStart))
			logger.Info("Usage successfully uploaded to Zuora",
				kvp.String("zuoraResponse", fmt.Sprintf("%+v", *response)),
				kvp.Int("retryCount", retryCount),
			)
			e.statter.Timing("zuora_engine.emit_to_zuora", stats.Tags{"success": "true"}, time.Since(start))
			return nil
		}
		// TODO: Re-evaluate whether we should retry on all errors once Zuora provides better
		// documentation on what kinds of errors we can expect to see from this API
		lastError = errors.Wrap(err, "failed to upload usage on retry attempt")
		e.trackEmissionTiming("upload_usage_failure", time.Since(uploadStart))
		logger.Info("Failed to upload usage to Zuora. Retrying...", kvp.Int("retryCount", retryCount))

		e.waitForThrottling()
	}

	// Mark invoice as rejected
	rejectedAt := time.Now()
	e.invoiceEngine.markInvoiceRejected(ctx, logger, invoice, lastError, &rejectedAt)

	e.trackEmissionError("upload_usage_error")
	e.statter.Timing("zuora_engine.emit_to_zuora", stats.Tags{"success": "false"}, time.Since(start))
	return errors.Wrap(lastError, "failed to upload usage on all retries")
}

func (e *ZuoraEngine) EmitDailyToZuora(ctx context.Context, logger log.Logger, customer *models.Customer, enterpriseCustomer *models.Customer, emission *models.Emission) error {
	start := time.Now()
	logger = logger.WithFields(
		append(enterpriseCustomer.GetLoggerFields(), kvp.String("customerId", customer.GetCustomerId()))...,
	)

	// Skip emission if customer has no ZuoraAccountNumber as Zuora API will return 400 if the field is missing
	if !enterpriseCustomer.HasZuoraAccountNumber() {
		e.trackEmissionSkipped("customer.missing_zuora_account_number")
		logger.Info("Skipping sending usage to Zuora for customer, missing Zuora account number")
		return nil
	}

	// Build the usage records
	buildUsageRecordsStart := time.Now()

	usageRecords, err := e.buildDailyUsageRecords(ctx, logger, customer, enterpriseCustomer, emission)
	if err != nil {
		e.trackEmissionError("build_usage_records_error")
		logger.WithError(err).Error("Failed to build usage records")
		return errors.Wrap(err, "failed to build usage records")
	}

	logger = logger.WithFields(
		kvp.Int("currentUsageRecordsCount", len(usageRecords)),
		kvp.String("currentUsageRecords", fmt.Sprintf("%+v", usageRecords)),
	)

	if len(usageRecords) == 0 {
		e.trackEmissionSkipped("customer.no_usage_records_to_send")
		logger.Info("Skipping sending usage to Zuora for customer, no usage records to upload")
		return nil
	}
	e.trackEmissionTiming("build_usage_records", time.Since(buildUsageRecordsStart))
	logger = logger.WithFields(
		kvp.Int("usageRecordsCount", len(usageRecords)),
		kvp.String("usageRecords", fmt.Sprintf("%+v", usageRecords)),
	)

	// Call the Zuora API
	var lastError error
	for retryCount := 0; retryCount < ZuoraEmissionMaxRetries; retryCount++ {
		uploadStart := time.Now()

		response, err := e.client.UsageService.UploadUsage(usageRecords)
		// Set the EmissionStatus to Completed or Failed
		if err == nil {
			emission.Status = models.EmissionCompleted
			e.trackEmissionTiming("upload_usage_success", time.Since(uploadStart))
			logger.Info("Usage successfully uploaded to Zuora",
				kvp.String("zuoraResponse", fmt.Sprintf("%+v", *response)),
				kvp.Int("retryCount", retryCount),
			)
			if _, upsertErr := e.UpsertEmission(ctx, logger, emission); upsertErr != nil {
				e.trackEmissionError("save_emission_record_error")
				logger.WithError(upsertErr).Error("Failed to save emission record")
				return errors.Wrap(upsertErr, "error saving emission record")
			}
			e.statter.Timing("zuora_engine.emit_to_zuora", stats.Tags{"success": "true"}, time.Since(start))
			return nil
		}
		// TODO: Re-evaluate whether we should retry on all errors once Zuora provides better
		// documentation on what kinds of errors we can expect to see from this API
		lastError = errors.Wrap(err, "failed to upload usage on retry attempt")
		e.trackEmissionTiming("upload_usage_failure", time.Since(uploadStart))
		logger.Info("Failed to upload usage to Zuora. Retrying...", kvp.Int("retryCount", retryCount))

		e.waitForThrottling()
	}
	emission.Status = models.EmissionFailed
	// Save emission record to the database
	_, upsertErr := e.UpsertEmission(ctx, logger, emission)
	if upsertErr != nil {
		e.trackEmissionError("save_emission_record_error")
		logger.WithError(upsertErr).Error("Failed to save emission record")
		return errors.Wrap(upsertErr, "error saving emission record")
	}
	e.trackEmissionError("upload_usage_error")
	e.statter.Timing("zuora_engine.emit_to_zuora", stats.Tags{"success": "false"}, time.Since(start))
	return errors.Wrap(lastError, "failed to upload usage on all retries")
}

func (e *ZuoraEngine) EmitDailyBatchToZuora(ctx context.Context, logger log.Logger, usageRecords []zuora.UploadUsageRecord) error {
	start := time.Now()

	if len(usageRecords) == 0 {
		e.trackEmissionSkipped("batch.no_usage_records_to_send")
		logger.Info("Skipping sending usage to Zuora for batch, no usage records to upload")
		return nil
	}

	// Call the Zuora API
	var lastError error
	for retryCount := 0; retryCount < ZuoraEmissionMaxRetries; retryCount++ {
		uploadStart := time.Now()

		response, err := e.client.UsageService.UploadUsage(usageRecords)
		// Set the ZuoraEmissionBatchStatus to Completed or Failed
		if err == nil {
			e.trackEmissionTiming("upload_usage_success", time.Since(uploadStart))
			logger.Info("Usage successfully uploaded to Zuora",
				kvp.String("zuoraResponse", fmt.Sprintf("%+v", *response)),
				kvp.Int("retryCount", retryCount),
			)
			return nil // Success
		}

		// TODO: Re-evaluate whether we should retry on all errors once Zuora provides better
		// documentation on what kinds of errors we can expect to see from this API
		lastError = errors.Wrap(err, "failed to upload usage on retry attempt")
		e.trackEmissionTiming("upload_usage_failure", time.Since(uploadStart))
		logger.Info("Failed to upload usage to Zuora. Retrying...", kvp.Int("retryCount", retryCount))

		e.waitForThrottling()
	}

	// This means we have exhausted all retries and it failed
	e.trackEmissionError("upload_usage_error")
	e.statter.Timing("zuora_engine.emit_to_zuora", stats.Tags{"success": "false"}, time.Since(start))
	return errors.Wrap(lastError, "failed to upload usage on all retries")
}

func (e *ZuoraEngine) ProcessDailyZuoraBatch(ctx context.Context, logger log.Logger, emissionDateTime models.UsageTime, customer *models.Customer, enterpriseCustomer *models.Customer, emission *models.Emission) error {
	start := time.Now()
	logger = logger.WithFields(
		append(enterpriseCustomer.GetLoggerFields(), kvp.String("customerId", customer.GetCustomerId()))...,
	)

	if !enterpriseCustomer.HasZuoraAccountNumber() {
		e.trackEmissionSkipped("customer.missing_zuora_account_number")
		logger.Info("Skipping sending usage to Zuora for customer, missing Zuora account number")
		return nil
	}

	buildUsageRecordsStart := time.Now()

	usageRecords, err := e.buildDailyUsageRecords(ctx, logger, customer, enterpriseCustomer, emission)
	if err != nil {
		e.trackEmissionError("build_usage_records_error")
		logger.WithError(err).Error("Failed to build usage records")
		return errors.Wrap(err, "failed to build usage records")
	}

	logger = logger.WithFields(
		kvp.Int("currentUsageRecordsCount", len(usageRecords)),
		kvp.String("currentUsageRecords", fmt.Sprintf("%+v", usageRecords)),
	)

	if len(usageRecords) == 0 {
		e.trackEmissionSkipped("customer.no_usage_records_to_send")
		logger.Info("Skipping batch process to Zuora for customer, no usage records to upload")
		return nil
	}
	e.trackEmissionTiming("build_usage_records", time.Since(buildUsageRecordsStart))
	logger = logger.WithFields(
		kvp.Int("usageRecordsCount", len(usageRecords)),
		kvp.String("usageRecords", fmt.Sprintf("%+v", usageRecords)),
	)

	err = e.createZuoraBatch(ctx, logger, emissionDateTime, customer, usageRecords)
	if err != nil {
		e.trackEmissionError("create_zuora_batch_error")
		logger.WithError(err).Error("Failed to create Zuora batch")
		emission.Status = models.EmissionFailed
		_, upsertErr := e.UpsertEmission(ctx, logger, emission)
		if upsertErr != nil {
			e.trackEmissionError("save_emission_record_error")
			logger.WithError(upsertErr).Error("Failed to save emission record")
			return errors.Wrap(upsertErr, "error saving emission record")
		}
		return errors.Wrap(err, "failed to create Zuora batch")
	}

	emission.Status = models.EmissionCompleted
	_, upsertErr := e.UpsertEmission(ctx, logger, emission)
	if upsertErr != nil {
		e.trackEmissionError("save_emission_record_error")
		logger.WithError(upsertErr).Error("Failed to save emission record")
		return errors.Wrap(upsertErr, "error saving emission record")
	}

	e.statter.Timing("zuora_engine.emit_to_zuora", stats.Tags{"success": "true"}, time.Since(start))
	return nil
}

func (e *ZuoraEngine) createZuoraBatch(ctx context.Context, logger log.Logger, emissionDateTime models.UsageTime, customer *models.Customer, usageRecords []zuora.UploadUsageRecord) error {
	year := emissionDateTime.Year()
	month := emissionDateTime.Month()
	day := emissionDateTime.Day()

	partitionDetailForBatchStatus := models.GetPartitionDetailForZuoraEmissionBatchStatus(year, int(month), day)

	emissionBatchStatusRecords, err := e.GetZuoraEmissionBatchStatus(ctx, logger, partitionDetailForBatchStatus)
	if err != nil {
		e.trackEmissionError("build_batchstatus_records_error")
		logger.WithError(err).Error("Failed to retreive emission batch status records")
		return errors.Wrap(err, "failed to retreive emission batch status records")
	}

	var activeBatchStatusRecord *models.ZuoraEmissionBatchStatus
	latestBatchID := 0

	batchIDMutex.Lock()
	defer batchIDMutex.Unlock()

	sort.Slice(emissionBatchStatusRecords, func(i, j int) bool {
		return emissionBatchStatusRecords[i].BatchNumber <
			emissionBatchStatusRecords[j].BatchNumber
	})

	for _, record := range emissionBatchStatusRecords {
		if record.Status == models.BatchStatusBuilding {
			activeBatchStatusRecord = record
			break
		}
		if record.BatchNumber > latestBatchID {
			latestBatchID = record.BatchNumber
		}
	}

	if activeBatchStatusRecord == nil {
		latestBatchID++
		activeBatchStatusRecord = models.NewZuoraEmissionBatchStatus(year, int(month), day, latestBatchID)

		err = e.CreateZuoraEmissionBatchStatus(ctx, logger, activeBatchStatusRecord)
		if err != nil {
			e.trackEmissionError("build_batchstatus_records_error")
			logger.WithError(err).Error("Failed to upsert emission batch status records")
			return errors.Wrap(err, "failed to upsert emission batch status records")
		}
	}

	totalCount, totalPayloadSize, err := e.calculateTotalCountAndPayloadSize(activeBatchStatusRecord, usageRecords)
	if err != nil {
		e.trackEmissionError("build_batch_records_error")
		logger.WithError(err).Error("Failed to calculate total count and payload size")
		return errors.Wrap(err, "error calculating total count and payload size")
	}

	if totalCount >= ZuoraMaxNumberOfRecords || totalPayloadSize >= ZuoraMaxPayloadSize {

		activeBatchStatusRecord.Status = models.BatchStatusReadyToSubmit

		err = e.PatchOrCreateZuoraEmissionBatchStatus(ctx, logger, activeBatchStatusRecord)
		if err != nil {
			e.trackEmissionError("update_batch_status_error")
			logger.WithError(err).Error("Failed to update batch status")
			return errors.Wrap(err, "failed to update batch status")
		}

		// Schedule the emission handler for the previous batch and date
		batchParm := models.GetZuoraEmissonBatchPayload(year, int(month), day, activeBatchStatusRecord.BatchNumber)

		err = e.scheduleBatchEmissionHandler(ctx, logger, batchParm)
		if err != nil {
			e.trackEmissionError("schedule_emission_handler_error")
			logger.WithError(err).Error("Failed to schedule batch emission handler")
			return errors.Wrap(err, "failed to schedule batch emission handler")
		}

		nextBatchNumber := activeBatchStatusRecord.BatchNumber + 1
		newBatchStatus := models.NewZuoraEmissionBatchStatus(year, int(month), day, nextBatchNumber)

		totalCount, totalPayloadSize, err := e.calculateTotalCountAndPayloadSize(newBatchStatus, usageRecords)
		if err != nil {
			e.trackEmissionError("build_batch_records_error")
			logger.WithError(err).Error("Failed to calculate total count and payload size")
			return errors.Wrap(err, "error calculating total count and payload size")
		}

		newBatchStatus.TotalRecordCount = totalCount
		newBatchStatus.PayloadSize = totalPayloadSize

		err = e.PatchOrCreateZuoraEmissionBatchStatus(ctx, logger, newBatchStatus)
		if err != nil {
			e.trackEmissionError("create_new_batch_status_error")
			return errors.Wrap(err, "failed to create new batch status")
		}

		newBatch := models.NewZuoraEmissionBatch(year, int(month), day, nextBatchNumber, customer.GetCustomerId())
		newBatch.UploadUsageRecords = usageRecords

		if err := e.CreateZuoraEmissionBatch(ctx, logger, newBatch); err != nil {
			e.trackEmissionError("update_active_batch_error")
			logger.WithError(err).Error("Failed to update old emission batch")
			return errors.Wrap(err, "failed to update old emission batch")
		}

		logger.Info("Successfully closed batch and created new one",
			kvp.Int("old_batch_number", activeBatchStatusRecord.BatchNumber),
			kvp.Int("new_batch_number", nextBatchNumber))

		return nil

	}

	activeBatch := models.NewZuoraEmissionBatch(year, int(month), day, activeBatchStatusRecord.BatchNumber, customer.GetCustomerId())
	activeBatch.UploadUsageRecords = usageRecords

	if err := e.CreateZuoraEmissionBatch(ctx, logger, activeBatch); err != nil {
		e.trackEmissionError("create_batch_error")
		logger.WithError(err).Error("failed to update emission batch")
		return errors.Wrap(err, "failed to update emission batch")
	}

	activeBatchStatusRecord.PayloadSize = totalPayloadSize
	activeBatchStatusRecord.TotalRecordCount = totalCount

	err = e.PatchOrCreateZuoraEmissionBatchStatus(ctx, logger, activeBatchStatusRecord)
	if err != nil {
		e.trackEmissionError("update_batch_status_error")
		logger.WithError(err).Error("Failed to update batch status")
		return errors.Wrap(err, "failed to update batch status")
	}

	logger.Info("Successfully updated batch with new records",
		kvp.Int("batch_number", activeBatchStatusRecord.BatchNumber),
		kvp.Int("total_records", totalCount),
		kvp.Int64("total_size", totalPayloadSize))

	return nil
}

func (e *ZuoraEngine) getZuoraUsageIdentifiers(ctx context.Context, logger log.Logger) (map[string]string, error) {
	// returns a map of product names to Zuora usage identifiers
	// Get the products
	getProductsStart := time.Now()
	products, err := e.productEngine.GetAllProducts(ctx, logger, false)
	if err != nil {
		return nil, errors.Wrap(err, "failed to get products")
	}
	e.trackEmissionTiming("get_products", time.Since(getProductsStart))

	// Map product names to Zuora usage identifiers
	zuoraUsageIdentifiers := make(map[string]string)
	for _, product := range products {
		zuoraUsageIdentifiers[product.Name] = product.ZuoraUsageIdentifier
	}

	return zuoraUsageIdentifiers, nil
}

func (e *ZuoraEngine) buildUsageRecords(ctx context.Context, logger log.Logger, enterpriseCustomer models.Customer, customer models.Customer, invoice *models.Invoice) (map[string]zuora.UploadUsageRecord, error) {
	if invoice == nil {
		return nil, nil
	}

	zuoraUsageIdentifiers, err := e.getZuoraUsageIdentifiers(ctx, logger)
	if err != nil {
		return nil, errors.Wrap(err, "failed to get products")
	}

	// Set usage time to the last day of the invoice month
	zuoraUsageTime := time.Date(int(invoice.Year), time.Month(invoice.Month), 1, 0, 0, 0, 0, time.UTC)
	zuoraUsageTime = zuoraUsageTime.AddDate(0, 1, -1)

	// Look up the cost center if the customer is a cost center proxy
	var costCenter *models.CostCenter
	if customer.IsCostCenterProxy {
		costCenterKey := &models.CostCenterKey{
			Key: &models.Key{
				PartitionKey: enterpriseCustomer.ToCostCentersPartitionKey(),
				Id:           customer.CostCenterUUID,
			},
		}

		costCenter, err = e.costCenterEngine.Get(ctx, logger, costCenterKey)

		if err != nil {
			return nil, errors.Wrap(err, "failed to get cost center")
		} else if costCenter == nil {
			return nil, fmt.Errorf("no cost center found")
		}
	}

	// Build the usage records
	usageRecords := make(map[string]zuora.UploadUsageRecord)
	for _, productTotal := range invoice.ProductTotals {
		usageIdentifier, ok := zuoraUsageIdentifiers[productTotal.Product]
		if ok && usageIdentifier != "" {
			usageRecord := zuora.UploadUsageRecord{
				CustomerId:      enterpriseCustomer.ZuoraAccountNumber,
				UsageIdentifier: usageIdentifier,
				UsageDate:       zuora.ZuoraUsageDateTime{Time: zuoraUsageTime},
				Amount:          productTotal.UsageTotal.Net,
			}

			if costCenter != nil {
				usageRecord.CostCenter = costCenter.Name
			}

			usageRecords[usageIdentifier] = usageRecord
		}
	}

	return usageRecords, nil
}

func (e *ZuoraEngine) buildDailyUsageRecords(ctx context.Context, logger log.Logger, customer *models.Customer, enterpriseCustomer *models.Customer, emission *models.Emission) ([]zuora.UploadUsageRecord, error) {
	if emission == nil {
		return nil, nil
	}

	zuoraUsageIdentifiers, err := e.getZuoraUsageIdentifiers(ctx, logger)
	if err != nil {
		return nil, errors.Wrap(err, "failed to get products")
	}

	zuoraUsageTime := models.GetDateFromEmissionPartitionDetail(emission.Key)

	// Look up the cost center if the customer is a cost center proxy
	var costCenter *models.CostCenter
	if customer.IsCostCenterProxy {
		costCenterKey := &models.CostCenterKey{
			Key: &models.Key{
				PartitionKey: enterpriseCustomer.ToCostCentersPartitionKey(),
				Id:           customer.CostCenterUUID,
			},
		}

		costCenter, err = e.costCenterEngine.Get(ctx, logger, costCenterKey)

		if err != nil {
			return nil, errors.Wrap(err, "failed to get cost center")
		} else if costCenter == nil {
			return nil, fmt.Errorf("no cost center found")
		}
	}

	// Build the usage records
	usageRecords := []zuora.UploadUsageRecord{}
	for _, productTotal := range emission.ProductTotals {
		usageIdentifier, ok := zuoraUsageIdentifiers[productTotal.Product]
		if ok && usageIdentifier != "" {
			if productTotal.UsageTotal.Net == 0 {
				continue
			}
			usageRecord := zuora.UploadUsageRecord{
				CustomerId:      enterpriseCustomer.ZuoraAccountNumber,
				UsageIdentifier: usageIdentifier,
				UsageDate:       zuora.ZuoraUsageDateTime{Time: zuoraUsageTime.Time},
				Amount:          productTotal.UsageTotal.Net,
			}

			if costCenter != nil {
				usageRecord.CostCenter = costCenter.Name
			}

			usageRecords = append(usageRecords, usageRecord)
		}
	}

	return usageRecords, nil
}

func (e *ZuoraEngine) ScheduleZuoraBatchEmission(ctx context.Context, logger log.Logger, zuoraBatchPayload *models.ZuoraBatchEmissionPayload) error {

	logger.Info("ScheduleZuoraBatchEmission Start")

	start := time.Now()

	batchStatusPartitionDetail := models.GetPartitionDetailForZuoraEmissionBatchStatus(zuoraBatchPayload.Year, zuoraBatchPayload.Month, zuoraBatchPayload.Day)
	batchStatusRecords, err := e.GetZuoraEmissionBatchStatus(ctx, logger, batchStatusPartitionDetail)
	if err != nil {
		logger.WithError(err).Error("Failed to retreive batch status records")
		return errors.Wrap(err, "failed to retreive batch status records")
	}

	var buildingStatusRecord *models.ZuoraEmissionBatchStatus
	for _, record := range batchStatusRecords {
		if record.Status == models.BatchStatusBuilding {
			buildingStatusRecord = record
			break
		}
	}

	if buildingStatusRecord == nil {
		logger.Error("No batch status record found in 'building' state")
		return errors.New("no batch status record found in 'building' state")
	}

	buildingStatusRecord.Status = models.BatchStatusReadyToSubmit
	err = e.PatchOrCreateZuoraEmissionBatchStatus(ctx, logger, buildingStatusRecord)
	if err != nil {
		e.trackEmissionError("update_batch_status_error")
		logger.WithError(err).Error("Failed to update batch status")
		return errors.Wrap(err, "failed to update batch status")
	}

	// Schedule the emission handler for the previous batch and date
	batchParm := models.GetZuoraEmissonBatchPayload(zuoraBatchPayload.Year,
		zuoraBatchPayload.Month,
		zuoraBatchPayload.Day,
		buildingStatusRecord.BatchNumber)

	err = e.scheduleBatchEmissionHandler(ctx, logger, batchParm)
	if err != nil {
		e.trackEmissionError("schedule_emission_handler_error")
		logger.WithError(err).Error("Failed to schedule batch emission handler")
		return errors.Wrap(err, "failed to schedule batch emission handler")
	}
	// Logging and metrics
	duration := time.Since(start)
	logger.Info("ScheduleZuoraBatchEmission Finished", kvp.Duration("duration", duration))
	e.statter.Timing("zuora_engine.schedule_zuora_batch_emission", stats.Tags{}, duration)

	return nil

}

func diffUsageRecords(currentRecords, submittedRecords map[string]zuora.UploadUsageRecord) map[string]zuora.UploadUsageRecord {
	// calculates currentRecords - submittedRecords
	if submittedRecords == nil {
		return currentRecords
	}
	newRecords := make(map[string]zuora.UploadUsageRecord)
	for identifier, usage := range currentRecords {
		submittedUsage, ok := submittedRecords[identifier]
		if !ok {
			newRecords[identifier] = usage
		} else {
			if usage.Amount == submittedUsage.Amount {
				continue
			}
			newRecords[identifier] = usage.Diff(submittedUsage)
		}
	}
	return newRecords
}

func (e *ZuoraEngine) trackEmissionError(reason string) {
	e.statter.Counter("zuora_emission_error", stats.Tags{"origin": reason}, int64(1))
}

func (e *ZuoraEngine) trackEmissionSkipped(reason string) {
	e.statter.Counter("zuora_emission_skipped", stats.Tags{"origin": reason}, int64(1))
}

func (e *ZuoraEngine) trackEmissionTiming(origin string, duration time.Duration) {
	e.statter.Timing("zuora_emission_timing", stats.Tags{"origin": origin}, duration)
}

func (e *ZuoraEngine) waitForThrottling() {
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	n := r.Intn(15)
	time.Sleep(time.Duration(n) * time.Millisecond)
}

func (e *ZuoraEngine) GetEmission(ctx context.Context, logger log.Logger, ipd *models.EmissionPartitionDetail) (*models.Emission, error) {
	return db.NewQuerier[*models.Emission](e.db).ReadItemWithRetries(ctx, logger, models.NewEmissionKey(ipd))
}

func (e *ZuoraEngine) UpsertEmission(ctx context.Context, logger log.Logger, emission *models.Emission) (*models.Emission, error) {
	err := e.db.UpsertWithOptions(ctx, logger, emission, nil)
	if err != nil {
		return nil, err
	}

	return emission, nil
}

func (e *ZuoraEngine) HasItemBeenEmitted(ctx context.Context, logger log.Logger, item *models.ActiveUsageItem) (bool, error) {
	emissionTargetDate, error := models.ExtractEmissionDateFromPartitionKey(item.PartitionKey)
	if error != nil {
		return false, error
	}
	emissionPartitionDetail := &models.EmissionPartitionDetail{
		CustomerId: item.Id,
		Year:       emissionTargetDate.Year,
		Month:      emissionTargetDate.Month,
		Day:        emissionTargetDate.Day,
	}

	emissionRecord, err := e.GetEmission(ctx, logger, emissionPartitionDetail)
	if err != nil {
		return false, err
	} else if emissionRecord != nil && emissionRecord.Status == models.EmissionCompleted {
		return true, nil
	}

	return false, nil
}

func (e *ZuoraEngine) calculateTotalCountAndPayloadSize(activeBatchStatusRecord *models.ZuoraEmissionBatchStatus, usageRecords []zuora.UploadUsageRecord) (int, int64, error) {
	var payloadSize int64
	count := len(usageRecords)

	payload, err := json.Marshal(usageRecords)
	if err != nil {
		return 0, 0, errors.Wrap(err, "error marshalling UploadUsage records")
	}
	payloadSize += int64(len(payload))

	totalCount := activeBatchStatusRecord.TotalRecordCount + count
	totalPayloadSize := activeBatchStatusRecord.PayloadSize + payloadSize

	return totalCount, totalPayloadSize, nil
}

func (e *ZuoraEngine) GetZuoraEmissionBatchStatus(ctx context.Context, logger log.Logger, zpd *models.ZuoraEmissionBatchStatusPartitionDetail) ([]*models.ZuoraEmissionBatchStatus, error) {
	pk := zpd.ToGetPartitionKey()
	batchStatus, err := e.emissionStatusQuerier.QueryItems(ctx, logger, db.QueryStringAll, pk)
	if err != nil {
		return nil, err
	}
	return batchStatus, nil
}

func (e *ZuoraEngine) GetZuoraEmissionBatch(ctx context.Context, logger log.Logger, zpd *models.ZuoraEmissionBatchPartitionDetail) ([]*models.ZuoraEmissionBatch, error) {
	pk := zpd.GetBatchPartitionKey()
	batch, err := e.emissionbatchQuerier.QueryItems(ctx, logger, db.QueryStringAll, pk)
	if err != nil {
		return nil, err
	}

	return batch, err
}

func (e *ZuoraEngine) UpsertZuoraEmissionBatchStatus(ctx context.Context, logger log.Logger, batchstatus *models.ZuoraEmissionBatchStatus) (*models.ZuoraEmissionBatchStatus, error) {
	err := e.db.UpsertWithOptions(ctx, logger, batchstatus, nil)
	if err != nil {
		return nil, err
	}

	return batchstatus, err
}

func (e *ZuoraEngine) PatchOrCreateZuoraEmissionBatchStatus(ctx context.Context, logger log.Logger, batchStatus *models.ZuoraEmissionBatchStatus) error {
	if e.PatchZuoraEmissionBatchStatus(ctx, logger, batchStatus) == nil {
		return nil
	}

	if e.db.CreateWithOptions(ctx, logger, batchStatus, nil) == nil {
		return nil
	}
	return e.PatchZuoraEmissionBatchStatus(ctx, logger, batchStatus)
}

func (e *ZuoraEngine) PatchZuoraEmissionBatchStatus(ctx context.Context, logger log.Logger, batchStatus *models.ZuoraEmissionBatchStatus) error {
	po := azcosmos.PatchOperations{}
	po.AppendReplace("/payloadSize", batchStatus.PayloadSize)
	po.AppendReplace("/totalRecordCount", batchStatus.TotalRecordCount)
	po.AppendReplace("/status", batchStatus.Status)
	err := e.db.PatchWithOptions(ctx, logger, batchStatus, po, nil)
	if err != nil {
		return err
	}
	return nil
}

func (e *ZuoraEngine) CreateZuoraEmissionBatchStatus(ctx context.Context, logger log.Logger, batchStatus *models.ZuoraEmissionBatchStatus) error {
	err := e.db.CreateWithOptions(ctx, logger, batchStatus, nil)
	if err != nil {
		return errors.Wrap(err, "failed to create ZuoraEmissionBatchStatus")
	}
	return nil
}

func (e *ZuoraEngine) UpsertZuoraEmissionBatch(ctx context.Context, logger log.Logger, batch *models.ZuoraEmissionBatch) (*models.ZuoraEmissionBatch, error) {
	err := e.db.UpsertWithOptions(ctx, logger, batch, nil)
	if err != nil {
		return nil, err
	}

	return batch, nil
}

func (e *ZuoraEngine) CreateZuoraEmissionBatch(ctx context.Context, logger log.Logger, batch *models.ZuoraEmissionBatch) error {

	err := e.db.CreateWithOptions(ctx, logger, batch, nil)
	if err != nil {
		return errors.Wrap(err, "failed to create ZuoraEmissionBatch")
	}
	return nil
}

func (e *ZuoraEngine) scheduleBatchEmissionHandler(ctx context.Context, logger log.Logger, batch *models.ZuoraBatchEmissionPayload) error {
	payload, err := json.Marshal(batch)
	if err != nil {
		logger.WithError(err).Error("error serializing zuora batch emission", kvp.Int("batchNumber", batch.BatchNumber))
		return errors.Wrap(err, "error serializing batch")
	}

	job := aqueduct.Job{
		App:     e.cfg.AqueductApplication(),
		Queue:   messaging.GetQueueName(models.WorkerTypeZuoraBatchEmissionHandler, e.cfg.OverrideQueuePrefix),
		Payload: payload,
	}
	_, err = e.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)

	l := logger.WithFields(
		kvp.String("aqueduct.job.app", job.App),
		kvp.String("aqueduct.job.queue", job.Queue),
		kvp.String("aqueduct.job.payload", string(job.Payload)),
	)
	if err != nil {
		l.WithError(err).Error("error submitting zuora batch emission dispatcher job",
			kvp.Int("batchNumber", batch.BatchNumber))
		return errors.Wrap(err, "failed to submit zuora batch emission dispatcher job")
	}

	// Log successful submission of the batch emission job
	l.Info("submitted zuora batch emission job for batch",
		kvp.Int("batchNumber", batch.BatchNumber))
	e.statter.Counter("published_emission_dispatcher_job", stats.Tags{}, int64(1))

	return nil
}
