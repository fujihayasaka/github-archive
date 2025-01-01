package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydro_schemas_billingplatform_v1_entities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"
)

var (
	cachedDisabledCustomerIDs []string
	cacheMutex                sync.RWMutex
	onceDisabled              sync.Once
)

type InvoiceGenerationHandler struct {
	*Handler
	customerEngine   engines.CustomerEngineInterface
	invoiceEngine    *engines.InvoiceEngine
	productEngine    engines.ProductEngineInterface
	usageEngine      engines.UsageEngineInterface
	zuoraEngine      engines.ZuoraEngineInterface
	hydroPublisher   interfaces.HydroPublisher
	costCenterEngine engines.CostCenterEngineInterface
	discountEngine   engines.DiscountEngineInterface
}

func NewInvoiceGenerationHandler(
	params *HandlerParams,
	customerEngine engines.CustomerEngineInterface,
	invoiceEngine *engines.InvoiceEngine,
	productEngine engines.ProductEngineInterface,
	usageEngine engines.UsageEngineInterface,
	zuoraEngine engines.ZuoraEngineInterface,
	hydroPublisher interfaces.HydroPublisher,
	costCenterEngine engines.CostCenterEngineInterface,
	discountEngine engines.DiscountEngineInterface,
) *InvoiceGenerationHandler {
	return &InvoiceGenerationHandler{
		Handler:          NewHandler(params, models.WorkerTypeInvoiceGeneration),
		customerEngine:   customerEngine,
		invoiceEngine:    invoiceEngine,
		productEngine:    productEngine,
		usageEngine:      usageEngine,
		zuoraEngine:      zuoraEngine,
		hydroPublisher:   hydroPublisher,
		costCenterEngine: costCenterEngine,
		discountEngine:   discountEngine,
	}
}

func (h *InvoiceGenerationHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	logger.Debug("Processing message in", kvp.String("queue", h.queueName))
	logger.Debug("unmarshalling enveloped message", kvp.String("payload", string(rr.Payload)))

	start := time.Now()

	// Get the partition key and id from the message
	// partitionKey=active:invoices:year:month, id=customer:id:invoices:year:month
	var key *models.Key
	if err := json.Unmarshal(rr.Payload, &key); err != nil {
		h.trackGenerationErrorAndAddToDLQ(ctx, logger, rr, "unmarshal_error", errors.Wrap(err, "failed to unmarshal enveloped message"))
		return nil
	}
	h.trackGenerationTiming("unmarshal_message", time.Since(start))

	activeInvoiceKey := key
	invoiceKey := models.InvoiceKeyFromActiveInvoiceKey(key)
	invoiceDetail, err := models.InvoicePartitionDetailFromInvoiceKey(invoiceKey)
	if err != nil {
		return err
	}
	err = h.invoiceEngine.MarkInvoicePartitionDetailProcessed(ctx, logger, invoiceDetail, &start)

	if err != nil {
		h.trackGenerationErrorAndAddToDLQ(ctx, logger, rr, "upsert_active_invoice_item_error", errors.Wrap(err, "failed to set processedAt time invoice detail"))
		return nil
	}

	// Get the customer
	getCustomerStart := time.Now()
	customerId := invoiceDetail.CustomerId
	customer, err := h.customerEngine.Get(ctx, logger, customerId, false)
	if err != nil {
		h.trackGenerationErrorAndAddToDLQ(ctx, logger, rr, "get_customer_error", errors.Wrap(err, fmt.Sprintf("failed to fetch customer %s", customerId)), kvp.String("customer", customerId))
		return nil
	} else if customer == nil {
		h.trackGenerationSkipped("customer_not_found")
		logger.Error("customer not found", kvp.String("customer", customerId))
		return nil
	}

	enterpriseCustomer := customer
	if customer.IsCostCenterProxy {
		// grab the enterprise customer as the above customer will be a cost center customer record if it is a proxy
		enterpriseCustomer, err = h.customerEngine.Get(ctx, logger, customer.EnterpriseCustomerId, false)
		if enterpriseCustomer == nil || err != nil {
			h.trackGenerationErrorAndAddToDLQ(ctx, logger, rr, "get_enterprise_customer_error", errors.Wrap(err, "failed to load enterprise customer record"), kvp.String("customer", customerId))
			return nil
		}
	}

	h.trackGenerationTiming("get_customer", time.Since(getCustomerStart))

	logger = logger.WithFields(append(enterpriseCustomer.GetLoggerFields(), kvp.String("invoiceCustomerId", customerId))...)

	if !enterpriseCustomer.ForZuora() {
		h.trackGenerationSkipped("customer_not_for_zuora")
		return nil
	}

	// Feature Flag to disable Zuora Emission
	// All Processing put behind a feature flag
	if h.shouldDisableEmission(ctx, logger, customer) {
		return nil
	}

	// Generate the invoice
	invoice, previouslySubmittedInvoice, err := h.generateInvoice(ctx, logger, invoiceDetail, enterpriseCustomer)
	if err != nil {
		h.trackGenerationErrorAndAddToDLQ(ctx, logger, rr, "invoice_generation_error", errors.Wrap(err, "failed to generate invoice"), kvp.String("customer", customerId))
		return nil
	}
	logger.Debug("Generated invoice", kvp.Any("invoice", invoice), kvp.Any("previouslySubmittedInvoice", previouslySubmittedInvoice))

	// Emit the invoice to Zuora
	err = h.zuoraEngine.EmitToZuora(ctx, logger, enterpriseCustomer, customer, invoice, previouslySubmittedInvoice)
	if err != nil {
		h.trackEmissionErrorAddToDLQ(ctx, logger, rr, "zuora_emission_error", errors.Wrap(err, "failed to emit invoice to Zuora"), kvp.String("customer", customerId))
		return nil
	}

	// delete the active invoice item from the active invoice partition
	// this also allows late usage to come in and be re-considered as active
	err = h.invoiceEngine.DeleteActiveInvoice(ctx, logger, activeInvoiceKey)
	if err != nil {
		logger.WithError(err).Error("unable to delete active invoice item", kvp.String("invoiceId", invoiceKey.Id))
	}

	// Publish the invoice message to Hydro
	h.PublishZuoraInvoiceMessage(ctx, logger, customer, invoice, previouslySubmittedInvoice)

	return nil
}

func (h *InvoiceGenerationHandler) PublishZuoraInvoiceMessage(ctx context.Context, logger log.Logger, customer *models.Customer, invoice *models.Invoice, previouslySubmittedInvoice *models.Invoice) {
	invoiceHydroSchema := h.generateInvoiceHydroMessage(ctx, logger, customer, invoice)

	// If we have a previously submitted invoice, diff the two and emit the delta
	if previouslySubmittedInvoice != nil {
		previouslySubmittedInvoiceHydroSchema := h.generateInvoiceHydroMessage(ctx, logger, customer, previouslySubmittedInvoice)

		invoiceHydroSchema.GrossBilledAmount -= previouslySubmittedInvoiceHydroSchema.GrossBilledAmount
		invoiceHydroSchema.DiscountAmount -= previouslySubmittedInvoiceHydroSchema.DiscountAmount
		invoiceHydroSchema.NetAmountDue -= previouslySubmittedInvoiceHydroSchema.NetAmountDue

		for _, sku := range invoiceHydroSchema.Skus {
			for _, previousSku := range previouslySubmittedInvoiceHydroSchema.Skus {
				if sku.Name == previousSku.Name {
					sku.GrossQuantity -= previousSku.GrossQuantity
					sku.DiscountQuantity -= previousSku.DiscountQuantity
					sku.NetQuantity -= previousSku.NetQuantity
					sku.GrossBilledAmount -= previousSku.GrossBilledAmount
					sku.DiscountAmount -= previousSku.DiscountAmount
					sku.NetBilledAmount -= previousSku.NetBilledAmount
				}
			}
		}
	}

	err := h.hydroPublisher.Publish(invoiceHydroSchema)
	if err != nil {
		logger.WithError(err).Error("failed to publish invoice message")
	} else {
		logger.Info("published invoice message")
	}
}

func (h *InvoiceGenerationHandler) generateInvoiceHydroMessage(ctx context.Context, logger log.Logger, customer *models.Customer, invoice *models.Invoice) *hydroSchema.Invoice {
	now := timestamppb.New(time.Now().UTC())
	// hardcode to first of the invoice month
	usageTime := models.NewUsageTime().WithYear(invoice.Year).WithMonthInt(invoice.Month).WithDay(1).WithHour(0)

	var skus []*hydro_schemas_billingplatform_v1_entities.SkuInvoice

	for _, productTotal := range invoice.ProductTotals {
		var billingTargetChargeId string
		product, _ := h.productEngine.Get(ctx, logger, productTotal.Product, false)
		if product != nil {
			billingTargetChargeId = product.ZuoraUsageIdentifier
		}

		for _, skuTotal := range productTotal.SkuTotals {
			var discountQuantity float64
			discountTotals, _, err := h.discountEngine.GetDiscountTotal(ctx, logger, &models.UsagePartitionDetail{
				// Use the invoice customer ID here in case it is a cost center
				UsageEntityId: invoice.CustomerId,
				Product:       productTotal.Product,
				Sku:           skuTotal.Sku,
				UsageTime:     usageTime,
				ActiveType:    models.Monthly,
			})
			if err != nil {
				logger.WithError(err).Error("failed to retrieve discount total")
				h.statter.Counter("customer-invoice-discount-error", stats.Tags{}, int64(1))
				discountQuantity = 0

			} else {
				discountQuantity = discountTotals.ToDecimal().Quantity
			}

			skuInvoiceSchema := &hydro_schemas_billingplatform_v1_entities.SkuInvoice{
				Name:                  skuTotal.Sku,
				Product:               productTotal.Product,
				GrossQuantity:         skuTotal.UsageTotal.Quantity,
				DiscountQuantity:      discountQuantity,
				NetQuantity:           skuTotal.UsageTotal.Quantity - discountQuantity,
				GrossBilledAmount:     skuTotal.UsageTotal.Gross,
				DiscountAmount:        skuTotal.UsageTotal.Discount,
				NetBilledAmount:       skuTotal.UsageTotal.Net,
				BillingTargetChargeId: billingTargetChargeId,
			}

			if len(skuTotal.BillingItems) > 0 {
				skuInvoiceSchema.UnitType = skuTotal.BillingItems[0].GetUnitType().String()
			}

			skus = append(skus, skuInvoiceSchema)
		}
	}

	invoiceHydroSchema := hydroSchema.Invoice{
		InvoiceId:            invoice.Key.Id,
		CustomerId:           customer.EnterpriseCustomerId,
		Skus:                 skus,
		GrossBilledAmount:    invoice.UsageTotal.Gross,
		DiscountAmount:       invoice.UsageTotal.Discount,
		NetAmountDue:         invoice.UsageTotal.Net,
		PaymentProcessorId:   customer.ZuoraAccountNumber,
		UsageAt:              timestamppb.New(usageTime.Time),
		GeneratedByBillingAt: now,
		Target:               customer.GetHydroBillingTarget(),
		InvoiceYear:          invoice.Year,
		InvoiceMonth:         invoice.Month,
		BillingTargetId:      customer.ZuoraAccountNumber,
	}

	if customer.IsCostCenterProxy {
		costCenterKey := &models.CostCenterKey{
			Key: &models.Key{
				PartitionKey: fmt.Sprintf("customer:%s:costCenters", customer.EnterpriseCustomerId),
				Id:           customer.CostCenterUUID,
			},
		}

		costCenter, err := h.costCenterEngine.Get(ctx, logger, costCenterKey)
		if err != nil {
			logger.WithError(err).Error("failed to find cost center")
		} else {
			costCenterEntity := hydro_schemas_billingplatform_v1_entities.CostCenter{
				Uuid: costCenter.UUID,
				Name: costCenter.Name,
			}

			invoiceHydroSchema.CostCenter = &costCenterEntity
		}
	}

	return &invoiceHydroSchema
}

func (h *InvoiceGenerationHandler) generateInvoice(ctx context.Context, logger log.Logger, invoiceDetail *models.InvoicePartitionDetail, customer *models.Customer) (*models.Invoice, *models.Invoice, error) {
	generateInvoiceStart := time.Now()
	usageTime := models.NewUsageTime().WithYear(invoiceDetail.Year).WithMonthInt(invoiceDetail.Month)
	usageDetail := &models.UsagePartitionDetail{
		UsageEntityId: invoiceDetail.CustomerId,
		Product:       "",
		Sku:           "",
		UsageTime:     usageTime,
		ActiveType:    models.Monthly,
	}

	items, err := h.usageEngine.GetLineItems(ctx, logger, usageDetail)
	if err != nil {
		return nil, nil, errors.Wrap(err, "failed to retrieve line items for invoice generation")
	}

	discountItems, err := h.usageEngine.GetDiscountLineItems(ctx, logger, usageDetail)
	if err != nil {
		return nil, nil, errors.Wrap(err, "failed to retrieve discount line items for invoice generation")
	}

	// If a customer was offboarded from Copilot, we need to filter out any
	// Copilot usage since we track usage per month but we don't know how much
	// they actually used until they were offboarded.
	// Since we can't tell if they were ever onboarded to
	// Copilot, the best we can do is check if Copilot is disabled now.
	var filteredItems []*models.Item
	var filteredDiscountItems []*models.DiscountItem
	if !customer.HasEnabledProduct("copilot") {
		filteredItems = h.rejectItemsByProduct(items, "copilot")
		filteredDiscountItems = h.rejectDiscountItemsByProduct(discountItems, "copilot")
	} else {
		filteredItems = items
		filteredDiscountItems = discountItems
	}

	// partitionKey=customer:id:invoices, id=customer:id:invoices:year:month
	invoice := models.NewInvoice(invoiceDetail, filteredItems, filteredDiscountItems)

	previouslySubmittedInvoice, err := h.invoiceEngine.GetSubmittedInvoice(ctx, logger, invoiceDetail)
	if err != nil {
		return nil, nil, errors.Wrap(err, "error trying to retrieve a submitted invoice")
	}
	_, err = h.invoiceEngine.UpsertInvoice(ctx, logger, invoice)
	if err != nil {
		return nil, nil, errors.Wrap(err, "failed to generate invoice")
	}

	h.trackGenerationTiming("generate_invoice", time.Since(generateInvoiceStart))

	return invoice, previouslySubmittedInvoice, nil
}

func (h *InvoiceGenerationHandler) rejectItemsByProduct(items []*models.Item, product string) []*models.Item {
	var filtered []*models.Item
	for _, item := range items {
		if item.GetProduct() != product {
			filtered = append(filtered, item)
		}
	}
	return filtered
}

func (h *InvoiceGenerationHandler) rejectDiscountItemsByProduct(items []*models.DiscountItem, product string) []*models.DiscountItem {
	var filtered []*models.DiscountItem
	for _, item := range items {
		if item.GetProduct() != product {
			filtered = append(filtered, item)
		}
	}
	return filtered
}

func (h *InvoiceGenerationHandler) trackGenerationErrorAndAddToDLQ(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult, reason string, err error, fields ...kvp.Field) {
	logger.WithError(err).Error("error on invoice generation", fields...)
	h.statter.Counter("invoice_generation_error", stats.Tags{"origin": reason}, int64(1))
	_ = h.AddToDeadLetterQueue(ctx, logger, rr.Payload, stats.Tags{"origin": reason})
}

func (h *InvoiceGenerationHandler) trackGenerationTiming(origin string, duration time.Duration) {
	h.statter.Timing("invoice_generation_timing", stats.Tags{"origin": origin}, duration)
}

func (h *InvoiceGenerationHandler) trackGenerationSkipped(reason string) {
	h.statter.Counter("invoice_generation_skipped", stats.Tags{"origin": reason}, int64(1))
}

func (h *InvoiceGenerationHandler) trackEmissionErrorAddToDLQ(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult, reason string, err error, fields ...kvp.Field) {
	logger.WithError(err).Error("error on zuora emission", fields...)
	h.statter.Counter("invoice_emission_error", stats.Tags{"origin": reason}, int64(1))
	_ = h.AddToDeadLetterQueue(ctx, logger, rr.Payload, stats.Tags{"origin": reason})
}

func (h *InvoiceGenerationHandler) shouldDisableEmission(ctx context.Context, logger log.Logger, customer *models.Customer) bool {

	disableEmission := false
	runningDate := time.Now()

	// Check if the customer ID is disabled for monthly emission
	disabledCustomerIDs := h.getDisabledCustomerIDs(h.cfg.CustomersWithMonthlyEmissionDisabled)
	if slices.Contains(disabledCustomerIDs, customer.GetCustomerId()) {
		logger.Info("Monthly emission disabled for customer")
		disableEmission = true
		return disableEmission
	}

	activeDate, err := time.Parse("2006-01-02", h.cfg.DailyEmissionsActiveDate)
	if err != nil {
		logger.Error("Invalid format for DailyEmissionsActiveDate")
		return disableEmission
	}

	// Check if the current running date is equal to or greater than DailyEmissionsActiveDate
	if runningDate.Before(activeDate) {
		logger.Info("Current date is before the active date for daily emissions")
		return disableEmission
	}

	// This check will not be accessed until active date is reached, Which will be set to March 1st, 2025
	isFeatureFlagEnabled := h.flagger.IsEnabledWithDefaultValue(ctx, featureflags.ShouldProcessZuoraDailyEmission, false, models.CustomerVexiActor(customer.GetCustomerId()))
	if isFeatureFlagEnabled {
		logger.Info("Monthly emission disabled for customer")
		disableEmission = true
		return disableEmission
	}

	return disableEmission
}

func (h *InvoiceGenerationHandler) getDisabledCustomerIDs(customersWithMonthlyEmissionDisabled string) []string {
	// Acquire read lock
	cacheMutex.RLock()
	if len(cachedDisabledCustomerIDs) > 0 {
		defer cacheMutex.RUnlock()
		return cachedDisabledCustomerIDs
	}
	cacheMutex.RUnlock()

	// Acquire write lock
	cacheMutex.Lock()
	defer cacheMutex.Unlock()

	// Double-check to prevent race condition
	onceDisabled.Do(func() {
		if len(cachedDisabledCustomerIDs) == 0 {
			cachedDisabledCustomerIDs = strings.Split(customersWithMonthlyEmissionDisabled, ",")
		}
	})

	return cachedDisabledCustomerIDs
}
