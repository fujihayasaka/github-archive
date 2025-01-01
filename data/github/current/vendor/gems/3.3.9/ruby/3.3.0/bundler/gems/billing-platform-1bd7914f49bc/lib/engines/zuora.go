package engines

import (
	"context"
	"fmt"
	"math/rand"
	"time"

	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/zuora"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
)

const ZuoraEmissionMaxRetries = 3

type ZuoraEngine struct {
	*EngineParams
	client           *zuora.Client
	costCenterEngine CostCenterEngineInterface
	invoiceEngine    *InvoiceEngine
	productEngine    ProductEngineInterface
}

func NewZuoraEngine(params *EngineParams, client *zuora.Client, costCenterEngine CostCenterEngineInterface, invoiceEngine *InvoiceEngine, productEngine ProductEngineInterface) *ZuoraEngine {
	return &ZuoraEngine{
		EngineParams:     params,
		client:           client,
		costCenterEngine: costCenterEngine,
		invoiceEngine:    invoiceEngine,
		productEngine:    productEngine,
	}
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
