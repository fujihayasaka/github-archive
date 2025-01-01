package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"
	"strconv"
	"sync"
	"time"

	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/utils"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	billingProto "github.com/github/billing-platform/lib/twirp/proto"
	stats "github.com/github/go-stats"

	schemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"

	"golang.org/x/sync/errgroup"
	"google.golang.org/protobuf/proto"
)

var (
	now = time.Now

	// Mappings between hydroSchema repo visibility to billing platform proto repository visibility
	repoVisibilityMapping = map[hydroSchemaEntities.RepositoryVisibility]billingProto.RepositoryVisibility{
		hydroSchemaEntities.RepositoryVisibility_VISIBILITY_UNKNOWN: billingProto.RepositoryVisibility_VISIBILITY_UNKNOWN,
		hydroSchemaEntities.RepositoryVisibility_PUBLIC:             billingProto.RepositoryVisibility_PUBLIC,
		hydroSchemaEntities.RepositoryVisibility_PRIVATE:            billingProto.RepositoryVisibility_PRIVATE,
		hydroSchemaEntities.RepositoryVisibility_INTERNAL:           billingProto.RepositoryVisibility_INTERNAL,
	}
)

type UsageHandler struct {
	*Handler
	costCenterEngine   engines.CostCenterEngineInterface
	customerEngine     engines.CustomerEngineInterface
	invoiceEngine      *engines.InvoiceEngine
	pricingEngine      engines.PricingEngineInterface
	hydroPublisher     interfaces.HydroPublisher
	subscriptionEngine *engines.SubscriptionsEngine
	productEngine      engines.ProductEngineInterface
	usageEngine        engines.UsageEngineInterface
	discountEngine     engines.DiscountEngineInterface
	budgetEngine       engines.BudgetEngineInterface
}

func NewUsageHandler(
	params *HandlerParams,
	costCenterEngine engines.CostCenterEngineInterface,
	customerEngine engines.CustomerEngineInterface,
	invoiceEngine *engines.InvoiceEngine,
	pricingEngine engines.PricingEngineInterface,
	hydroPublisher interfaces.HydroPublisher,
	subscriptionEngine *engines.SubscriptionsEngine,
	productEngine engines.ProductEngineInterface,
	usageEngine engines.UsageEngineInterface,
	discountEngine engines.DiscountEngineInterface,
	budgetEngine engines.BudgetEngineInterface,
) *UsageHandler {
	return &UsageHandler{
		Handler:            NewHandler(params, models.WorkerTypeUsageIngestion),
		costCenterEngine:   costCenterEngine,
		customerEngine:     customerEngine,
		invoiceEngine:      invoiceEngine,
		pricingEngine:      pricingEngine,
		hydroPublisher:     hydroPublisher,
		subscriptionEngine: subscriptionEngine,
		productEngine:      productEngine,
		usageEngine:        usageEngine,
		discountEngine:     discountEngine,
		budgetEngine:       budgetEngine,
	}
}

func (h *UsageHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) (retErr error) {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.ProcessMessage")
	defer sp.End()

	var discountStateUpdates []models.UpdateDiscountStatePayload
	var budgetStateUpdateJobs []models.BudgetStateUpdateJob

	item, foundPricing, customerId, repositoryVisibility, err := h.loadItem(ctx, logger, rr)
	if err != nil {
		logger.WithError(err).Error("failed to load item")
		return err
	}

	logger = logger.WithFields(item.GetLoggerFields()...)
	logger.Info("usage item loaded successfully", kvp.Any("item", item), kvp.String("usage_process_message.job_id", rr.Job.ID), kvp.Int("usage_process_message.job_delivery_attempt", rr.DeliveryAttempt))

	g, gctx := errgroup.WithContext(ctx)
	// This is an additional safety check to make sure that
	//  we don't return early without waiting for all the scheduled
	// go routines to finish.
	defer func() {
		gErr := g.Wait()
		h.ProcessJobError = gErr
		if gErr != nil {
			logger.WithError(gErr).Error("One or more goroutines failed to complete successfully")
		}
	}()

	// If the customer id is 0 it means we didn't get a customer ID from the sender so we should log it and skip the usage.
	if item.EntityDetail.CustomerId == "0" {
		logger.Info("skipping usage message because it has no customer id")
		h.statter.Counter("metered-usage-handler-no-customer-id", stats.Tags{"product-sku": item.GetSku()}, int64(1))
		return nil
	}

	start := time.Now()
	allowItemReprocessingEnabled := h.flagger.IsEnabledWithDefaultValue(
		ctx, featureflags.IdempotentKeyForUsageHandlerRerun, false, models.CustomerVexiActor(customerId),
	)

	retainUUIDForEventPk := h.flagger.IsEnabledWithDefaultValue(ctx, featureflags.UseHighCardinalEventsPartitionKey, false, models.CustomerVexiActor(customerId))

	itemKey := item.GetKey()
	if item.IsWatermarkEvent() && !retainUUIDForEventPk {
		itemKey = item.AsItemWithEventPartitionKeyWithYearMonth().GetKey()
	}

	var idempotentKey *models.IdempotentKey
	if allowItemReprocessingEnabled {
		idempotentKey, err = db.NewQuerier[*models.IdempotentKey](h.DB).ReadItem(ctx, logger, itemKey, &interfaces.QueryOptions{RetryCount: 7})
		if err != nil {
			logger.WithError(err).Error("failed to read idempotency key", kvp.Any("item_key", itemKey))
			h.statter.Counter("metered-usage-handler-idempotency-check-error", stats.Tags{"status-code": strconv.Itoa(db.GetErrorStatusCode(err))}, int64(1))
			return err
		}

		if idempotentKey == nil {
			idempotentKey = itemKey.NewIdempotentKey()
		} else if idempotentKey.Completed {
			isOnRetry := strconv.FormatBool(rr.DeliveryAttempt > 1)
			logger.Info("skipping usage message - already successfully processed", kvp.Any("item_key", idempotentKey), kvp.Float64("usage_quantity", item.Amounts.ToDecimal().Quantity))
			h.statter.Counter("usage.key.already_processed", stats.Tags{"product_sku": item.GetSku(), "on_retry": isOnRetry}, int64(1))
			return nil
		}

		defer func() {
			err := h.DB.UpsertWithOptions(ctx, logger, idempotentKey, &interfaces.QueryOptions{RetryCount: 10})
			if err != nil {
				logger.WithError(err).Error("failed to update idempotency key", kvp.Any("item_key", idempotentKey), kvp.Bool("completed", idempotentKey.Completed), kvp.Bool("idempotent-key-on-retry", idempotentKey.IsOnRetry()), kvp.Float64("usage_quantity", item.Amounts.ToDecimal().Quantity))

				if idempotentKey.Completed || (item.IsWatermarkEvent() && item.Quantity > 0) {
					// don't retry the message if the idempotent key is completed or if it's a watermark add event
					retErr = nil
					h.ProcessJobError = nil
				}
			}

			h.statter.Counter("idempotent_key.upsert.status", stats.Tags{"sku": item.GetSku(), "status-code": strconv.Itoa(db.GetErrorStatusCode(err)), "completed": strconv.FormatBool(idempotentKey.Completed), "idempotent-key-on-retry": strconv.FormatBool(idempotentKey.IsOnRetry()), "on_retry": strconv.FormatBool(rr.DeliveryAttempt > 1), "save-success": strconv.FormatBool(err == nil)}, 1)
		}()
	} else {
		itemExists, err := h.DB.Exists(gctx, logger, itemKey, &interfaces.QueryOptions{RetryCount: 7})
		if err != nil {
			logger.WithError(err).Error("failed to query for usage item existence", kvp.Any("item_key", itemKey))
			h.statter.Counter("metered-usage-handler-idempotency-check-error", stats.Tags{"status-code": strconv.Itoa(db.GetErrorStatusCode(err))}, int64(1))
			return err
		}

		if itemExists {
			dQuantity := item.Amounts.ToDecimal().Quantity
			isOnRetry := strconv.FormatBool(rr.DeliveryAttempt > 1)
			logger.Info("skipping usage message because it's already processed", kvp.Any("item_key", itemKey), kvp.Float64("usage_quantity", dQuantity))
			h.statter.Counter("usage.key.already_processed", stats.Tags{"product_sku": item.GetSku(), "on_retry": isOnRetry}, int64(1))
			return nil
		}
	}

	// billingCustomer is the customer that will be billed for the usage. Could be a CostCenter or the parentCustomer.
	// parentCustomer is the main customer of the entity (Enterprise, User, Organization customer)
	// billingCustomer and parentCustomer can be nil for customers not onboarded to the billing platform.
	billingCustomer, parentCustomer, err := h.customerEngine.GetBillingAndParentCustomersFromItem(ctx, logger, item)
	if err != nil {
		// We have a non-404 error, so we log and return error to retry the message.
		logger.WithError(err).Error("failed to get billing and enterprise customers")
		return err
	}

	enterpriseInfo := h.customerEngine.GetEnterpriseInfoFromBillingAndParentCustomers(ctx, logger, billingCustomer, parentCustomer)

	var productEnabledForCustomer bool
	var rollupsEnabled bool
	var highWatermarkEvent *models.HighWatermarkEvent
	var discountItem *models.DiscountItem
	var overageAmounts *models.Amounts
	// Watermark events follow a separate processing path and do not need to be written like normal usage. Instead, hourly usage events
	// will be emitted that will then be used to generate line items for storage.
	if item.IsHighWatermarkEvent() {
		if allowItemReprocessingEnabled && idempotentKey.IsOnRetry() && item.Quantity > 0 {
			return nil // don't allow retry run for HWM subscription ADD. This is going away soon anyways
		}

		item.EntityDetail.CustomerId = customerId

		// check if the product is enabled before managing the subscription
		if enterpriseInfo == nil {
			return fmt.Errorf("error processing high watermark event. enterprise info is nil for customer %s", customerId)
		} else if !enterpriseInfo.IsProductEnabled(item.GetProduct()) {
			return fmt.Errorf("error processing high watermark event. product is not enabled for customer %s", customerId)
		}
		g.Go(func() error {
			return h.storeActiveHighWatermarkCustomer(gctx, logger, item)
		})

		isValidForBilling, err := h.subscriptionEngine.ManageSubscription(gctx, item.AsSubscribedItem())
		if err != nil {
			logger.WithError(err).Error("failed to manage subscription")
			return err
		}

		if isValidForBilling {
			highWatermarkEvent = models.NewHighWatermarkEvent(item)
			h.pricingEngine.ApplyPricing(ctx, logger, highWatermarkEvent)

			// set the prorated quantity and billed amount for all the rollups
			item.Quantity = highWatermarkEvent.Quantity
			item.BilledAmount = highWatermarkEvent.BilledAmount
			g.Go(func() error {
				return h.PatchOrCreate(gctx, logger, highWatermarkEvent)
			})
		} else {
			err := g.Wait()
			if err != nil {
				eventPartitionKey := item.AsItemWithEventPartitionKeyWithYearMonth().PartitionKey
				if retainUUIDForEventPk {
					eventPartitionKey = item.PartitionKey
				}
				return fmt.Errorf("failed to process high watermark event message. Partition key: %s. Error: %w", eventPartitionKey, err)
			}
			return nil
		}
	}
	if !item.IsWatermarkEvent() {
		if !allowItemReprocessingEnabled {
			g.Go(func() error {
				// Create just the items key for idempotency checks that happen towards the start of ProcessMessage in the usage handler.
				// Doing this saves us RUs while still ensuring that we don't process the same message multiple times.
				err := h.DB.CreateWithOptions(gctx, logger, item.GetKey(), nil)
				if db.Is409Conflict(err) {
					logger.Info("encountered duplicate usage item")
					h.statter.Counter("metered-usage-handler-duplicate-item", stats.Tags{"product-sku": item.GetSku()}, int64(1))
				}
				return err
			})
		}
		g.Go(func() error {
			customer := billingCustomer
			if customer != nil && customer.IsCostCenterProxy {
				customer = parentCustomer
			}

			switch {
			case customer == nil:
				logger.Error("customer not found", kvp.String("customer", customerId))
			case len(customer.EnabledProducts) != 0: // Only create active invoice, if customer has enabled products
				// Create an Active Usage Item for the customer
				err := h.usageEngine.WriteActiveUsageItems(gctx, logger, item, customer)
				if err != nil {
					logger.WithError(err).Error("failed to write active usage items")
				}
				return h.writeInvoiceItems(gctx, logger, item)
			} // else do nothing
			return nil
		})
	}

	switch {
	case !foundPricing:
		g.Go(func() error {
			created, err := h.DB.CreateIfNotExists(gctx, logger, &models.Key{PartitionKey: item.PartitionKey, Id: "no-pricing"})
			if err != nil {
				logger.WithError(err).Error("Error creating 'no-pricing' item", kvp.Any("item_key", idempotentKey))
			}
			h.statter.Counter("metered-usage-handler-did-not-find-pricing", stats.Tags{"product-sku": item.GetSku(), "saved-to-db": strconv.FormatBool(created)}, int64(1))

			return nil // always return nil from this goroutine. We don't need to retry if this fails
		})
		// Handle watermark event ingestion
	case item.IsWatermarkEvent():
		// Storage events should not be assigned a cost center key. We want to keep the original customer ID
		// so that we can assign the proper cost center when we emit a processed usage event that will
		// create a billable item. The loadItem function overwrites the value of item.EntityDetail.CustomerId to be
		// the cost center key if applicable.
		item.EntityDetail.CustomerId = customerId
		if !allowItemReprocessingEnabled {
			g.Go(func() error {
				eventItem := item.AsItemWithEventPartitionKeyWithYearMonth()
				if retainUUIDForEventPk {
					eventItem = item
				}
				_, err := h.DB.CreateIfNotExists(gctx, logger, eventItem)
				return err
			})
		}
		g.Go(func() error {
			return h.storeActiveWatermarkCustomer(gctx, logger, item)
		})
		g.Go(func() error {
			if allowItemReprocessingEnabled && idempotentKey.IsOnRetry() && item.Quantity > 0 {
				return nil // don't allow retry run for Watermark +ve events to prevent over counting
			}

			err := h.PatchOrCreate(gctx, logger, item.AsItemWithWatermarkTotalRollupPartitionKey())
			if err != nil {
				logger.WithError(err).Error("Failed to update event:rollup total item")
			}

			// also patch to the rollup as usual
			return h.PatchOrCreate(gctx, logger, item.AsItemWithWatermarkRollupPartitionKey())
		})
	default:
		if enterpriseInfo != nil && enterpriseInfo.IsProductEnabled(item.GetProduct()) {
			productEnabledForCustomer = true
			if item.IsEnabledForEmission() {
				rollupsEnabled = true

				// The following block of code is responsible for handling discounts, overages and updating budget states.
				// Here's an example of the expected behavior:
				// Budget:   $5
				// Usage:    $10
				// Discount: $2
				//
				// First, we apply the discount to the usage amount
				// amountAfterDiscount = $10 - $2 = $8
				//
				// Next, we calculate the overages based on the budget limit
				// overageAmount = $8 - $5 = $3
				//
				// The overage amount should not be visible to the customer, so we update the usage amount to exclude it
				// new usage amount = $10 - $3 = $7 (it still includes the discount amount)
				//
				// Finally, we update the budget state with the usage amount excluding discounts and overages amount
				// budget state = $8 - $3 = $5

				discountItem, discountStateUpdatePayloads, err := h.handleDiscount(ctx, logger, item, billingCustomer, enterpriseInfo, repositoryVisibility)
				if err != nil {
					logger.WithError(err).Error("failed to handle discount")
					return err
				} else {
					discountStateUpdates = discountStateUpdatePayloads
				}

				if discountItem != nil && highWatermarkEvent != nil {
					highWatermarkEvent.SetDailyDiscountQuantity(discountItem)
					err = h.subscriptionEngine.IncrementDailyDiscountQuantity(ctx, logger, highWatermarkEvent)
					if err != nil {
						logger.WithError(err).Error("failed to increment daily discount quantity for high watermark event")
						return err
					}
				}

				amountAfterDiscount := item.AmountsWithDiscountApplied(discountItem)
				// If the customer is on trial, we ignore budgets
				// and calculate overages based on discounts
				if parentCustomer.IsOnTrial() {
					if amountAfterDiscount.BilledAmount > 0 {
						overageAmounts = h.getOverageAmounts(logger, item, amountAfterDiscount.BilledAmount)
					}
				} else {
					now := models.UTCNow()
					year := int64(now.Year())
					month := int64(now.Month())
					budgets, err := h.budgetEngine.FindBudgetsFor(ctx, logger, item.GetProduct(), item.GetSku(), item.EntityDetail, year, month)
					if err != nil {
						return errors.Wrap(err, "failed to find budgets for customer")
					}

					overageAmounts, err = h.calculateOverages(ctx, logger, budgets, amountAfterDiscount, item, year, month)
					if err != nil {
						return errors.Wrap(err, "failed to calculate overages")
					}

					g.Go(func() error {
						amountAfterDiscountAndOverage := amountAfterDiscount.Minus(overageAmounts).EnsureNonNegative()

						sendAllBudgetUpdatesToQueue := h.flagger.IsEnabledWithDefaultValue(
							ctx, featureflags.SendAllBudgetUpdatesToQueue, false, models.CustomerVexiActor(customerId),
						)

						if sendAllBudgetUpdatesToQueue {
							for _, budget := range budgets {
								budgetStateUpdateJob := models.NewBudgetStateJob(budget, year, month, item.GetSku(), amountAfterDiscountAndOverage)
								if allowItemReprocessingEnabled {
									budgetStateUpdateJobs = append(budgetStateUpdateJobs, *budgetStateUpdateJob)
								} else {
									h.AddToBudgetStateQueue(ctx, logger, *budgetStateUpdateJob, stats.Tags{})
								}
							}
						} else {
							if allowItemReprocessingEnabled && idempotentKey.IsOnRetry() {
								return nil // don't allow retry run for budget updates to prevent over counting
							}
							bErr := h.updateBudgetStates(ctx, logger, budgets, amountAfterDiscountAndOverage, year, month, item.GetSku())
							if bErr != nil {
								logger.WithError(bErr).Error("failed to update budget state")
							}
						}

						// We're intentionally ignoring the error here for failed budget state updates here so that we don't block sending the rollups at the end of this func if an error is returned.
						// If the budget state fails to be updated, the budget will be incorrect, but it's more important that the rollups run so that the usage billing is correct.
						return nil
					})
				}

				// This mutates the usage amount if there are overages detected
				// so we need to wait for it to complete prior to proceeding with rollups
				item.RemoveOverages(overageAmounts)

				if !allowItemReprocessingEnabled {
					// send a usage line item message to Hydro for downstream consumers with discount item and overage amounts
					h.PublishLineItemMessage(ctx, logger, billingCustomer, item, discountItem, enterpriseInfo, overageAmounts)
				}

				// In https://github.com/github/gitcoin/issues/16861 we decided to remove hourly usage rollups from billing platform.
				// However, the API still supports querying hourly usage from the byOrgRepoProductSku partition so we need to keep
				// writing hourly rollups for that partition.
				g.Go(func() error {
					if allowItemReprocessingEnabled {
						_, err := h.DB.CreateIfNotExists(gctx, logger, models.NewCustomerOrgRepoProductSkuHourlyRollup(item))
						if err != nil {
							logger.WithError(err).Error("Error creating hourly 'byOrgRepoProductSku' item")
							return err
						}
						return nil
					} else {
						return h.DB.CreateWithOptions(gctx, logger, models.NewCustomerOrgRepoProductSkuHourlyRollup(item), nil)
					}
				})
			} else {
				// if the item is disabled for emission we still want to send usage line items to the data warehouse for reporting purposes
				discountItem := item.AsDiscountItemWithAmount(0)
				overageAmounts := models.NewAmountAsWholeNumbers(0, 0)
				h.PublishLineItemMessage(ctx, logger, billingCustomer, item, discountItem, enterpriseInfo, overageAmounts)
			}
		}
	}

	retErr = g.Wait()
	h.ProcessJobError = retErr

	if retErr == nil {
		switch {
		case (rollupsEnabled && allowItemReprocessingEnabled && !idempotentKey.Completed):
			// Trigger fan out of subsequent operations after everything else has completed successfully
			err = h.sendRollupJobs(ctx, logger, item, highWatermarkEvent, enterpriseInfo)
			if err == nil {
				idempotentKey.Completed = true

				if len(discountStateUpdates) > 0 {
					h.AddToDiscountStateUpdateQueue(ctx, logger, discountStateUpdates, item.GetSku())
				}

				for _, budgetStateUpdateJob := range budgetStateUpdateJobs {
					h.AddToBudgetStateQueue(ctx, logger, budgetStateUpdateJob, stats.Tags{})
				}

				// send a usage line item message to Hydro for downstream consumers with discount item and overage amounts
				h.PublishLineItemMessage(ctx, logger, billingCustomer, item, discountItem, enterpriseInfo, overageAmounts)
			} else {
				retErr = err
				h.ProcessJobError = err
			}
		case (rollupsEnabled && !allowItemReprocessingEnabled):
			// Trigger fan out of subsequent operations after everything else has completed successfully
			// dropping the returned error here because we weren't bubbling this up before.
			// I'm handling it in the new codepath when 'allowItemReprocessingEnabled' is true.
			_ = h.sendRollupJobs(ctx, logger, item, highWatermarkEvent, enterpriseInfo)

			if len(discountStateUpdates) > 0 {
				h.AddToDiscountStateUpdateQueue(ctx, logger, discountStateUpdates, item.GetSku())
			}
		case (!rollupsEnabled && allowItemReprocessingEnabled):
			// If rollups is not enabled and there are no errors, we should just mark the idempotent key as completed
			// This applies for watermark events, no-pricing items, items not enabled for emission, and products not enabled for the customer
			idempotentKey.Completed = true
		}
	} else {
		retErr = errors.Wrap(retErr, "failed to process usage message, one or more go routines failed")
	}

	logger.Info("processed usage message",
		kvp.Bool("product_enabled_for_customer", productEnabledForCustomer),
		kvp.Bool("rollups_enabled", rollupsEnabled),
	)
	h.statter.Counter(
		"metered-usage-handler-processed",
		stats.Tags{
			"product-sku":              item.GetSku(),
			"rollups-enabled":          strconv.FormatBool(rollupsEnabled),
			"success:":                 strconv.FormatBool(retErr == nil),
			"last-aqueduct-redelivery": strconv.FormatBool(rr.DeliveryAttempt == rr.MaxDeliveryAttempts),
		},
		int64(1))
	h.statter.Timing("metered-usage-handler-processed", nil, time.Since(start))
	// This measures the time between the timestamp of the message and the time it was processed
	// This will give us a measure of how late we're in processing the message
	h.statter.Timing("metered-usage-handler-usage-at-lag", stats.Tags{"product-sku": item.GetSku()}, time.Since(item.UsageAt.Time))
	return retErr
}

func (h *UsageHandler) handleDiscount(ctx context.Context, logger log.Logger, item *models.Item, customer *models.Customer, enterpriseInfo *models.EnterpriseInfo, repositoryVisibility hydroSchemaEntities.RepositoryVisibility) (*models.DiscountItem, []models.UpdateDiscountStatePayload, error) {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.handleDiscount")
	defer sp.End()

	now := models.UTCNow()

	amountAfterDiscounts, discountStateUpdates, err := h.calculateAmountAfterDiscounts(ctx, logger, item, customer, enterpriseInfo, now, repositoryVisibility)
	if err != nil {
		logger.WithError(err).Error("failed to update the discount state")
	}

	if amountAfterDiscounts != item.BilledAmount {
		discountItem := item.AsDiscountItemWithAmount(amountAfterDiscounts)
		err := h.DB.UpsertWithOptions(ctx, logger, discountItem.AsHourlyDiscountItemByCustomerOrgRepoProductSkuFrom(item), &interfaces.QueryOptions{RetryCount: 10})
		if err != nil {
			h.statter.Counter("discount.line_item.failure", stats.Tags{"sku": item.GetSku()}, 1)
			logger.WithError(err).Error("failed to write a org repo product sku discount item")
			return nil, discountStateUpdates, err
		}

		emissionDate := models.UTCNow().Truncate(24 * time.Hour)
		if item.UsageAt.Before(emissionDate) {
			lateDiscountItem := models.NewLateDiscountItem(discountItem, customer.GetCustomerId())

			err = h.PatchOrCreateLateDiscount(ctx, logger, lateDiscountItem)
			if err != nil {
				logger.WithError(err).Error("failed to create or patch a late discount item")
			}
		}

		return discountItem, discountStateUpdates, nil
	}

	return nil, discountStateUpdates, nil
}

func (h *UsageHandler) calculateAmountAfterDiscounts(ctx context.Context, logger log.Logger, item *models.Item, customer *models.Customer, enterpriseInfo *models.EnterpriseInfo, now *models.UsageTime, repositoryVisibility hydroSchemaEntities.RepositoryVisibility) (int64, []models.UpdateDiscountStatePayload, error) {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.calculateAmountAfterDiscounts")
	defer sp.End()

	var discountStateUpdates []models.UpdateDiscountStatePayload

	applied, amountAfterDiscount, discountStateUpdatePayload, err := h.applyFreePublicRepoDiscount(ctx, logger, item, customer, enterpriseInfo, now, repositoryVisibility)
	if err != nil {
		logger.WithError(err).Error("applyFreePublicRepoDiscount failed")
	}
	if applied {
		// free for public repo discount acts as a killswitch for all other discounts
		// it is the largest possible amount, and should not have any other discounts applied
		if discountStateUpdatePayload.Amount > 0 {
			discountStateUpdates = append(discountStateUpdates, discountStateUpdatePayload)
		}

		return amountAfterDiscount, discountStateUpdates, nil
	}

	applied, amountAfterDiscount, discountStateUpdatePayload, err = h.applyPlanDiscount(ctx, logger, item, customer, enterpriseInfo, now)
	if err != nil {
		logger.WithError(err).Error("applyPlanDiscount failed")
	}
	if applied {
		if discountStateUpdatePayload.Amount > 0 {
			discountStateUpdates = append(discountStateUpdates, discountStateUpdatePayload)
		}

		// if no amount is leftover, we can stop applying discounts
		if amountAfterDiscount == 0 {
			return amountAfterDiscount, discountStateUpdates, nil
		}
	}

	_, amountAfterDiscount, discountStateUpdatePayload, err = h.applyConfiguredDiscount(ctx, logger, item, customer, now, amountAfterDiscount)
	if err != nil {
		logger.WithError(err).Error("applyConfiguredDiscount failed")
	} else if discountStateUpdatePayload.Amount > 0 {
		discountStateUpdates = append(discountStateUpdates, discountStateUpdatePayload)

	}

	return amountAfterDiscount, discountStateUpdates, nil
}

func (h *UsageHandler) applyConfiguredDiscount(ctx context.Context, logger log.Logger, item *models.Item, customer *models.Customer, now *models.UsageTime, amountAfterDiscount int64) (bool, int64, models.UpdateDiscountStatePayload, error) {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.applyConfiguredDiscount")
	defer sp.End()

	year := int64(now.Year())
	month := int64(now.Month())

	var newDiscountStateUpdate models.UpdateDiscountStatePayload

	discount, discountType, err := h.discountEngine.GetLargestConfiguredDiscount(ctx, logger, item.EntityDetail.EnterpriseId(), item, now)
	if err != nil {
		logger.WithError(err).Error("GetLargestDiscount failed")
		return false, amountAfterDiscount, newDiscountStateUpdate, err
	}
	if reflect.DeepEqual(discount, &(models.Discount{})) {
		logger.Debug("No configured discount found")
		return false, amountAfterDiscount, newDiscountStateUpdate, nil
	}

	preDiscountAmount := amountAfterDiscount

	if discountType == models.DollarDiscountType {
		var amountExceedingBudget int64

		amountExceedingBudget, err = h.discountEngine.CalculateAmountExceedingDiscountState(ctx, logger, item.EntityDetail.EnterpriseId(), discount, preDiscountAmount, year, month)
		if err != nil {
			logger.WithError(err).Error("failed to calculate amount exceeding discount state", kvp.String("DiscountUUID", discount.Uuid))
		}

		// using the amount exceeding budget to calculate the discount amount we should apply to the discount state update
		discountAmount := preDiscountAmount - amountExceedingBudget

		newDiscountStateUpdate = models.UpdateDiscountStatePayload{
			Discount:   discount,
			Amount:     discountAmount,
			Year:       year,
			Month:      month,
			CustomerId: item.EntityDetail.EnterpriseId(),
			CreatedAt:  time.Now().UTC(),
		}

		// Send a $ discount line item message to Hydro for downstream consumers
		h.PublishDiscountLineItemMessage(ctx, logger, customer, item, discount, discountAmount, preDiscountAmount, hydroSchemaEntities.DiscountType_DOLLAR)

		return true, amountExceedingBudget, newDiscountStateUpdate, nil
	} else if discountType == models.PercentageDiscountType {
		discountAmount := discount.CalculatePercentageDiscountAmount(preDiscountAmount)
		afterDiscountAmount := preDiscountAmount - discountAmount

		newDiscountStateUpdate = models.UpdateDiscountStatePayload{
			Discount:   discount,
			Amount:     discountAmount,
			Year:       year,
			Month:      month,
			CustomerId: item.EntityDetail.EnterpriseId(),
			CreatedAt:  time.Now().UTC(),
		}

		// Send a % discount line item message to Hydro for downstream consumers
		h.PublishDiscountLineItemMessage(ctx, logger, customer, item, discount, discountAmount, preDiscountAmount, hydroSchemaEntities.DiscountType_PERCENT)

		return true, afterDiscountAmount, newDiscountStateUpdate, nil
	}

	return false, amountAfterDiscount, newDiscountStateUpdate, nil
}

func (h *UsageHandler) applyPlanDiscount(ctx context.Context, logger log.Logger, item *models.Item, customer *models.Customer, enterpriseInfo *models.EnterpriseInfo, now *models.UsageTime) (bool, int64, models.UpdateDiscountStatePayload, error) {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.applyPlanDiscount")
	defer sp.End()

	year := int64(now.Year())
	month := int64(now.Month())

	var newDiscountStateUpdate models.UpdateDiscountStatePayload

	discount, err := h.discountEngine.GetLargestPlanDiscount(ctx, logger, item.EntityDetail.EnterpriseId(), item, enterpriseInfo, now)
	if err != nil {
		logger.WithError(err).Error("GetLargestPlanDiscount failed")
		return false, item.BilledAmount, newDiscountStateUpdate, err
	}
	if reflect.DeepEqual(discount, &(models.Discount{})) {
		return false, item.BilledAmount, newDiscountStateUpdate, nil
	}

	preDiscountAmount := item.BilledAmount

	var amountExceedingBudget int64

	amountExceedingBudget, err = h.discountEngine.CalculateAmountExceedingDiscountState(ctx, logger, item.EntityDetail.EnterpriseId(), discount, preDiscountAmount, year, month)
	if err != nil {
		logger.WithError(err).Error("failed to calculate amount exceeding discount state", kvp.String("DiscountUUID", discount.Uuid))
	}

	// using the amount exceeding budget to calculate the discount amount we should apply to the discount state update
	discountAmount := preDiscountAmount - amountExceedingBudget

	newDiscountStateUpdate = models.UpdateDiscountStatePayload{
		Discount: discount,
		Amount:   discountAmount,
		Year:     year,
		Month:    month,
		// cost centers share plan discounts with the parent enterprise, so track it in the enterprise's discountState
		CustomerId: item.EntityDetail.EnterpriseId(),
		CreatedAt:  time.Now().UTC(),
	}

	// Send a plan discount line item message to Hydro for downstream consumers
	h.PublishDiscountLineItemMessage(ctx, logger, customer, item, discount, discountAmount, preDiscountAmount, hydroSchemaEntities.DiscountType_PLAN)

	return true, amountExceedingBudget, newDiscountStateUpdate, nil
}

func (h *UsageHandler) applyFreePublicRepoDiscount(ctx context.Context, logger log.Logger, item *models.Item, customer *models.Customer, enterpriseInfo *models.EnterpriseInfo, now *models.UsageTime, repositoryVisibility hydroSchemaEntities.RepositoryVisibility) (bool, int64, models.UpdateDiscountStatePayload, error) {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.applyFreePublicRepoDiscount")
	defer sp.End()

	year := int64(now.Year())
	month := int64(now.Month())
	customerId := item.GetCustomerId()

	var newDiscountStateUpdate models.UpdateDiscountStatePayload

	discount, err := h.getFreePublicRepoDiscount(ctx, logger, item, customerId, enterpriseInfo, repositoryVisibility, now)
	if err != nil {
		logger.WithError(err).Error("getFreePublicRepoDiscount failed")
		return false, item.BilledAmount, newDiscountStateUpdate, err
	}
	if reflect.DeepEqual(discount, &(models.Discount{})) {
		return false, item.BilledAmount, newDiscountStateUpdate, nil
	}

	// public repo discounts are 100% off for SKUs that are free for public repos (e.g. actions_linux)
	preDiscountAmount := item.BilledAmount
	discountAmount := discount.CalculatePercentageDiscountAmount(preDiscountAmount)
	afterDiscountAmount := preDiscountAmount - discountAmount

	newDiscountStateUpdate = models.UpdateDiscountStatePayload{
		Discount: discount,
		Amount:   discountAmount,
		Year:     year,
		Month:    month,
		// cost centers share FreePublicRepo discounts with the parent enterprise, so track it in the enterprise's discountState
		CustomerId: item.EntityDetail.EnterpriseId(),
		CreatedAt:  time.Now().UTC(),
	}

	// Send a public repo discount line item message to Hydro for downstream consumers
	h.PublishDiscountLineItemMessage(ctx, logger, customer, item, discount, discountAmount, preDiscountAmount, hydroSchemaEntities.DiscountType_PUBLIC_REPO)

	return true, afterDiscountAmount, newDiscountStateUpdate, nil
}

func (h *UsageHandler) getFreePublicRepoDiscount(ctx context.Context, logger log.Logger, item *models.Item, customerId string, enterpriseInfo *models.EnterpriseInfo, repositoryVisibility hydroSchemaEntities.RepositoryVisibility, now *models.UsageTime) (*models.Discount, error) {
	sku := item.GetSku()
	repoId := item.EntityDetail.RepositoryId
	billForPublicRepoUsage := enterpriseInfo.BillForPublicRepoUsage

	// convert the incoming hydro repo visibility to a proto visibility
	protoVisibility := billingProto.RepositoryVisibility_VISIBILITY_UNKNOWN
	visibility, ok := repoVisibilityMapping[repositoryVisibility]
	if ok {
		protoVisibility = visibility
	}

	hasPublicRepoDiscount, err := h.discountEngine.PublicRepoDiscountApplicable(ctx, logger, customerId, sku, repoId, protoVisibility, billForPublicRepoUsage)
	if err != nil {
		return &models.Discount{}, err
	}

	if !hasPublicRepoDiscount {
		return &models.Discount{}, nil
	}

	return models.New100PercentDiscountForSku(customerId, sku, now), nil
}

func (h *UsageHandler) updateBudgetStates(ctx context.Context, logger log.Logger, budgets []*models.Budget, amounts *models.Amounts, year, month int64, sku string) error {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.updateBudgetStates")
	defer sp.End()

	wgBudgets, gctx := errgroup.WithContext(ctx)
	for _, b := range budgets {
		budget := b
		wgBudgets.Go(func() error {
			budgetState, err := h.budgetEngine.PatchBudgetState(gctx, logger, budget, amounts, year, month, sku)
			if err != nil {
				return errors.Wrap(err, "failed to patch budget state")
			} else if budgetState == nil {
				return errors.New("budget state is nil")
			}
			if budget.BudgetLimitType.HardLimit() && budgetState.CurrentAmount > budgetState.TargetAmount {
				// We allowed the budget to go over the limit, but it's too late to fix it now.
				// We should log to investigate.
				logger.Error("Budget went over the limit", kvp.Any("budget", budget), kvp.Any("budgetState", budgetState), kvp.String("CustomerID", budget.CustomerId))
				h.statter.Counter("wrongful_overage", stats.Tags{"sku": sku}, int64(1))
			}

			err = h.budgetEngine.PublishBudgetStateThresholdMessage(logger, h.hydroPublisher, budget, budgetState)
			if err != nil {
				return err
			}

			return nil
		})
	}

	if err := wgBudgets.Wait(); err != nil {
		return errors.Wrap(err, "failed to update budget state")
	}

	return nil
}

// Logs overages and increments the overage counters
func (h *UsageHandler) logOverages(logger log.Logger, item *models.Item, maxOverageAmount, overageQuantity int64) {
	logger.Info("Overage detected",
		kvp.Float64("overage_amount", nano.ToDecimalAmount[int64](maxOverageAmount)),
		kvp.Float64("overage_quantity", nano.ToDecimalAmount[int64](overageQuantity)),
		kvp.Float64("total_amount", nano.ToDecimalAmount[int64](item.BilledAmount)),
		kvp.Float64("total_quantity", nano.ToDecimalAmount[int64](item.Quantity)),
	)
	h.statter.Counter("overage_amount", stats.Tags{"sku": item.GetSku(), "product": item.Pricing.Product}, maxOverageAmount)
	h.statter.Counter("overage_quantity", stats.Tags{"sku": item.GetSku(), "product": item.Pricing.Product}, overageQuantity)
}

// Get overage amounts and log them if present
func (h *UsageHandler) getOverageAmounts(logger log.Logger, item *models.Item, maxOverageAmount int64) *models.Amounts {
	if maxOverageAmount > 0 {
		overageQuantity := int64(0)
		if item.Pricing == nil {
			logger.Error("Pricing is nil while calculating overages", kvp.Any("item", item))
		} else {
			overageQuantity = item.Pricing.CalculateQuantity(maxOverageAmount)
		}

		h.logOverages(logger, item, maxOverageAmount, overageQuantity)

		return &models.Amounts{BilledAmount: maxOverageAmount, Quantity: overageQuantity}
	}
	return &models.Amounts{BilledAmount: 0, Quantity: 0}
}

// Calculate overage amount based on budget limits
func (h *UsageHandler) calculateOverages(ctx context.Context, logger log.Logger, budgets []*models.Budget, amount *models.Amounts, item *models.Item, year, month int64) (*models.Amounts, error) {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.CalculateOverages")
	defer sp.End()

	wgOverages, gctx := errgroup.WithContext(ctx)
	overageAmounts := make([]int64, 0, len(budgets)) // Track overage amounts in a slice instead of variable to avoid concurrency issues
	var mu sync.Mutex                                // Create a mutex for synchronizing access to overageAmounts

	for _, b := range budgets {
		budget := b
		wgOverages.Go(func() error {
			budgetState, err := h.budgetEngine.GetBudgetState(gctx, logger, budget, year, month)
			if err != nil {
				return errors.Wrap(err, "failed to get budget state")
			}

			overageAmount := budgetState.CalculateOverage(*budget, amount.BilledAmount)
			if overageAmount > 0 {
				mu.Lock()
				overageAmounts = append(overageAmounts, overageAmount)
				mu.Unlock()
			}

			return nil
		})
	}

	if err := wgOverages.Wait(); err != nil {
		return nil, errors.Wrap(err, "failed to calculate overages")
	}

	maxoverageAmount := models.MaxOverageAmount(overageAmounts)
	overageAmount := h.getOverageAmounts(logger, item, maxoverageAmount)

	return overageAmount, nil
}

func (h *UsageHandler) writeInvoiceItems(ctx context.Context, logger log.Logger, item *models.Item) error {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.writeInvoiceItems")
	defer sp.End()

	customerId := item.GetCustomerId()
	year := int64(item.UsageAt.Year())
	month := int64(item.UsageAt.Month())
	ipdMonthly := &models.InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     models.InvoiceMonthly,
		Year:       year,
		Month:      month,
	}

	// check if the active invoice item already exists to minimize RUs on this "hot partition"
	// as upserts have a high number of RUs where read/get is a max of 1
	activeInvoiceItem, err := h.invoiceEngine.GetActiveInvoiceItem(ctx, logger, ipdMonthly, nil)
	if activeInvoiceItem != nil && err == nil {
		return nil
	}

	// Save a monthly invoice item to track monthly usage
	_, err = h.invoiceEngine.UpsertActiveInvoiceItem(ctx, logger, ipdMonthly, nil)
	return err
}

func (h *UsageHandler) sendRollupJobs(ctx context.Context, logger log.Logger, item *models.Item, highWatermarkEvent *models.HighWatermarkEvent, enterpriseInfo *models.EnterpriseInfo) error {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.sendRollupJobs")
	defer sp.End()

	jobs := h.createRollupJobs(ctx, logger, item, highWatermarkEvent, enterpriseInfo)

	var err error
	retryCount := 5
	for i := 0; i < retryCount; i++ {
		_, err = h.aqueductClient.SendBatch(ctx, jobs)
		if err != nil {
			logger.WithError(err).Error("createRollupJobs failed to send batch to aqueduct", kvp.Int("retryCount", i+1))
			h.statter.Counter("published-rollup", stats.Tags{"success": "false"}, int64(1))
			utils.WaitForThrottling(retryCount, true)
		} else {
			h.statter.Counter("published-rollup", stats.Tags{"success": strconv.FormatBool(err == nil)}, int64(1))
			return nil
		}
	}
	logger.WithError(err).Error("createRollupJobs failed to send batch to aqueduct - retries exhausted", kvp.Int("retryCount", retryCount))
	h.statter.Counter("published-rollup.retries_exhausted", stats.Tags{}, int64(1))
	return errors.Wrap(err, "failed to send jobs to aqueduct")
}

func (h *UsageHandler) createRollupJobs(ctx context.Context, logger log.Logger, item *models.Item, highWatermarkEvent *models.HighWatermarkEvent, enterpriseInfo *models.EnterpriseInfo) []aqueduct.BatchItem {
	_, sp := h.tracer.Start(ctx, "UsageHandler.createRollupJobs")
	defer sp.End()

	payload, err := json.Marshal(models.NewCustomerSkuHourlyRollup(item))
	if err != nil {
		panic(fmt.Errorf("error serializing %w", err))
	}

	logger.Debug("usage handler sending rollup jobs", kvp.String("data", string(payload)))
	rollupJobs := []aqueduct.BatchItem{
		{
			Job: aqueduct.Job{
				App:     h.appName,
				Queue:   h.GetQueueName(models.WorkerTypeCustomerDailyRollup),
				Payload: payload,
			},
			Opts: messaging.MessageSenderOptions(),
		},
		{
			Job: aqueduct.Job{
				App:     h.appName,
				Queue:   h.GetQueueName(models.WorkerTypeCustomerMonthlyRollup),
				Payload: payload,
			},
			Opts: messaging.MessageSenderOptions(),
		},
		{
			Job: aqueduct.Job{
				App:     h.appName,
				Queue:   h.GetQueueName(models.WorkerTypeCustomerYearlyRollup),
				Payload: payload,
			},
			Opts: messaging.MessageSenderOptions(),
		},
	}

	if enterpriseInfo == nil {
		return rollupJobs
	}

	// For high watermark events, we divide the total quantity by the number of
	// days remaining in the month and create a rollup job for each day
	if highWatermarkEvent != nil {
		remainingDaysInMonth, dailyQuantity := highWatermarkEvent.DailyQuantity()

		if enterpriseInfo.BillingTarget == models.Azure {
			// Create an Azure rollup job for each day
			for i := 0; i < remainingDaysInMonth; i++ {
				itemCopy := *item
				itemCopy.Quantity = dailyQuantity
				itemCopy.UsageAt = *itemCopy.UsageAt.AddDay(i)
				payload, err := json.Marshal(models.NewCustomerSkuHourlyRollup(&itemCopy))
				if err != nil {
					h.statter.Counter(
						"azure_rollup.highwatermark.error",
						stats.Tags{"error": "marshal", "sku": highWatermarkEvent.GetSku()},
						int64(1),
					)
					logger.WithError(err).Error(
						"failed to unmarshal enveloped message",
						kvp.String("error", "marshal"),
						kvp.String("partitionKey", itemCopy.PartitionKey),
					)
					continue
				}

				rollupJobs = append(rollupJobs, aqueduct.BatchItem{
					Job: aqueduct.Job{
						App:     h.appName,
						Queue:   h.GetQueueName(models.WorkerTypeCustomerAzureEmissionDailyRollup),
						Payload: payload,
					},
					Opts: messaging.MessageSenderOptions(),
				})
			}
		} else if enterpriseInfo.BillingTarget == models.Zuora {
			// Create an Zuora rollup job for each day
			for i := 0; i < remainingDaysInMonth; i++ {
				itemCopy := *item
				itemCopy.Quantity = dailyQuantity
				itemCopy.UsageAt = *itemCopy.UsageAt.AddDay(i)
				payload, err := json.Marshal(models.NewCustomerSkuHourlyRollup(&itemCopy))
				if err != nil {
					h.statter.Counter(
						"zuora_rollup.highwatermark.error",
						stats.Tags{"error": "marshal", "sku": highWatermarkEvent.GetSku()},
						int64(1),
					)
					logger.WithError(err).Error(
						"failed to unmarshal enveloped message",
						kvp.String("error", "marshal"),
						kvp.String("partitionKey", itemCopy.PartitionKey),
					)
					continue
				}

				rollupJobs = append(rollupJobs, aqueduct.BatchItem{
					Job: aqueduct.Job{
						App:     h.appName,
						Queue:   h.GetQueueName(models.WorkerTypeCustomerZuoraEmissionDailyRollup),
						Payload: payload,
					},
					Opts: messaging.MessageSenderOptions(),
				})
			}
		}

	} else {
		// We only enqueue the azure emission rollup job if the billing target is azure
		if enterpriseInfo.BillingTarget == models.Azure {
			rollupJobs = append(rollupJobs, aqueduct.BatchItem{
				Job: aqueduct.Job{
					App:     h.appName,
					Queue:   h.GetQueueName(models.WorkerTypeCustomerAzureEmissionDailyRollup),
					Payload: payload,
				}, Opts: messaging.MessageSenderOptions(),
			})
		} else if enterpriseInfo.BillingTarget == models.Zuora {
			// We only enqueue the zuora rollup job if the billing target is zuora
			rollupJobs = append(rollupJobs, aqueduct.BatchItem{
				Job: aqueduct.Job{
					App:     h.appName,
					Queue:   h.GetQueueName(models.WorkerTypeCustomerZuoraEmissionDailyRollup),
					Payload: payload,
				}, Opts: messaging.MessageSenderOptions(),
			})
		}
	}
	return rollupJobs
}

func (h *UsageHandler) loadItem(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) (*models.Item, bool, string, hydroSchemaEntities.RepositoryVisibility, error) {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.loadItem")
	defer sp.End()

	var envelope schemas.Envelope
	if err := proto.Unmarshal(rr.Payload, &envelope); err != nil {
		return nil, false, "", hydroSchemaEntities.RepositoryVisibility_VISIBILITY_UNKNOWN, errors.Wrap(err, "failed to unmarshal envelope")
	}

	var message hydroSchema.Usage
	if err := proto.Unmarshal(envelope.Message, &message); err != nil {
		return nil, false, "", hydroSchemaEntities.RepositoryVisibility_VISIBILITY_UNKNOWN, errors.Wrap(err, "failed to unmarshal enveloped message")
	}

	repositoryVisibility := message.RepositoryVisibility

	// find cost center if exist and pass that everywhere else in the pipeline
	entity := models.NewEntityDetailFromHydro(message.Entity)
	costCenterKey, err := h.costCenterEngine.FindCostCenterFor(ctx, logger, entity, message.Sku)
	if err != nil {
		return nil, false, "", hydroSchemaEntities.RepositoryVisibility_VISIBILITY_UNKNOWN, errors.Wrap(err, "failed to find cost center")
	}
	originalCustomerID := entity.CustomerId
	if costCenterKey != nil {
		entity.SetCostCenterDetail(models.NewCustomerFromCostCenter(costCenterKey).CostCenterDetail)
	}

	item := h.createItemFromMessage(&message, entity)

	foundPricing := h.pricingEngine.ApplyPricing(ctx, logger, item)

	if item.IsWatermarkEvent() && h.flagger.IsEnabledWithDefaultValue(ctx, featureflags.UseHighCardinalEventsPartitionKey, false, models.CustomerVexiActor(originalCustomerID)) {
		item.Id = "events"
	}

	return item, foundPricing, originalCustomerID, repositoryVisibility, nil
}

func (h *UsageHandler) createItemFromMessage(message *hydroSchema.Usage, entityDetail *models.EntityDetail) *models.Item {
	generatedPartitionKey := message.UsageUuid
	// We are introducing the requirement for UsageUUID to be set in the message with https://github.com/github/hydro-schemas/pull/3753
	// Until all clients are using this the UsageUUID might not be set. In that case it will return "". If its "" then create a new uuid like we did before.
	if generatedPartitionKey == "" {
		generatedPartitionKey = uuid.NewString()
	}

	amounts := models.NewAmountAsWholeNumbers(0, message.Quantity)
	usageTime := message.UsageAt.AsTime()
	usageItem := &models.Item{
		Key: models.Key{
			Id:           "billable",
			PartitionKey: generatedPartitionKey,
		},
		Pricing: &models.Pricing{
			Sku: message.Sku,
		},
		UsageAt:      *models.NewUsageTimeFromTime(usageTime),
		SourceUri:    message.SourceUri,
		Amounts:      amounts,
		EntityDetail: entityDetail,
	}

	return usageItem
}

func (h *UsageHandler) storeActiveWatermarkCustomer(ctx context.Context, logger log.Logger, item *models.Item) error {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.storeActiveWatermarkCustomer")
	defer sp.End()

	_, err := h.DB.CreateIfNotExists(ctx, logger, item.AsActiveWatermarkCustomerProductSku())

	return err
}

func (h *UsageHandler) storeActiveHighWatermarkCustomer(ctx context.Context, logger log.Logger, item *models.Item) error {
	ctx, sp := h.tracer.Start(ctx, "UsageHandler.storeActiveHighWatermarkCustomer")
	defer sp.End()

	_, err := h.DB.CreateIfNotExists(ctx, logger, item.AsActiveHighWatermarkCustomerProductSku())
	return err
}

func (h *UsageHandler) PublishLineItemMessage(ctx context.Context, logger log.Logger, customer *models.Customer, item *models.Item, discountItem *models.DiscountItem, enterpriseInfo *models.EnterpriseInfo, overageAmount *models.Amounts) {
	_, sp := h.tracer.Start(ctx, "UsageHandler.PublishLineItemMessage")
	defer sp.End()

	usageLineItemHydroSchema := hydroSchema.UsageLineItem{
		UsageUuid:              item.PartitionKey,
		SourceUri:              item.SourceUri,
		Product:                item.GetProduct(),
		Sku:                    item.GetSku(),
		Quantity:               models.ToDecimalAmount[int64](item.Quantity),
		GrossAmount:            models.ToDecimalAmount[int64](item.BilledAmount),
		AppliedCostPerQuantity: models.ToDecimalAmount[int64](item.GetPrice()),
		ActorId:                item.EntityDetail.ActorId,
		RepoId:                 item.EntityDetail.RepositoryId,
		OrgId:                  item.EntityDetail.OrganizationId,
		UsageAt:                timestamppb.New(item.UsageAt.Time),
		ProcessedAt:            timestamppb.New(now().UTC()),
		UnitType:               item.GetUnitType().String(),
	}

	// This is to not lose the message if customer is not found
	if customer == nil {
		usageLineItemHydroSchema.CustomerId = item.GetCustomerId()
		usageLineItemHydroSchema.Target = hydroSchemaEntities.BillingTarget_UNKNOWN_TARGET
	} else {
		usageLineItemHydroSchema.CustomerId = customer.EnterpriseCustomerId
		usageLineItemHydroSchema.Target = customer.GetHydroBillingTarget()

		var billingTargetId string
		var billingTargetChargeId string

		if customer.BillingTarget == models.Zuora {
			billingTargetId = enterpriseInfo.ZuoraAccountNumber

			product, _ := h.productEngine.Get(ctx, logger, item.GetProduct(), false)
			if product != nil {
				billingTargetChargeId = product.ZuoraUsageIdentifier
			}
		} else if customer.BillingTarget == models.Azure {
			billingTargetId = enterpriseInfo.AzureAccountId
			billingTargetChargeId = item.Pricing.AzureMeterId
		}

		usageLineItemHydroSchema.BillingTargetId = billingTargetId
		usageLineItemHydroSchema.BillingTargetChargeId = billingTargetChargeId

		if customer.IsCostCenterProxy {
			costCenterKey := &models.CostCenterKey{
				Key: &models.Key{
					PartitionKey: fmt.Sprintf("customer:%s:costCenters", customer.EnterpriseCustomerId),
					Id:           customer.CostCenterUUID,
				},
			}

			// query cost center name from cost center engine.get
			costCenter, err := h.costCenterEngine.Get(ctx, logger, costCenterKey)
			if err != nil {
				logger.WithError(err).Error("failed to find cost center")
			} else {
				costCenterEntity := hydroSchemaEntities.CostCenter{
					Uuid: costCenter.UUID,
					Name: costCenter.Name,
				}

				usageLineItemHydroSchema.CostCenter = &costCenterEntity
			}
		}
	}

	if discountItem == nil {
		usageLineItemHydroSchema.DiscountAmount = 0
		usageLineItemHydroSchema.NetAmount = models.ToDecimalAmount[int64](item.BilledAmount)
	} else {
		usageLineItemHydroSchema.DiscountAmount = models.ToDecimalAmount[int64](discountItem.DiscountAmount)
		usageLineItemHydroSchema.NetAmount = models.ToDecimalAmount[int64](item.BilledAmount - discountItem.DiscountAmount)
	}

	if overageAmount != nil {
		usageLineItemHydroSchema.OverageAmount = models.ToDecimalAmount[int64](overageAmount.BilledAmount)
		usageLineItemHydroSchema.OverageQuantity = models.ToDecimalAmount[int64](overageAmount.Quantity)
	} else {
		usageLineItemHydroSchema.OverageAmount = 0
		usageLineItemHydroSchema.OverageQuantity = 0
	}

	err := h.hydroPublisher.Publish(&usageLineItemHydroSchema)
	if err != nil {
		logger.WithError(err).Error("failed to publish usage line item message")
	} else {
		logger.Info("published usage line item message")
	}
}

func (h *UsageHandler) PublishDiscountLineItemMessage(ctx context.Context, logger log.Logger, customer *models.Customer, item *models.Item, discount *models.Discount, discountAmount int64, preDiscountAmount int64, discountType hydroSchemaEntities.DiscountType) {
	_, sp := h.tracer.Start(ctx, "UsageHandler.PublishDiscountLineItemMessage")
	defer sp.End()

	discountLineItemHydroSchema := hydroSchema.DiscountLineItem{
		DiscountUuid:      discount.Uuid,
		LineItemId:        item.PartitionKey,
		Sku:               item.GetSku(),
		Product:           item.GetProduct(),
		DiscountAmount:    models.ToDecimalAmount[int64](discountAmount),
		DiscountType:      discountType,
		PreDiscountAmount: models.ToDecimalAmount[int64](preDiscountAmount),
		SourceDiscountId:  discount.Id,
		DiscountedAt:      timestamppb.New(item.UsageAt.Time),
		ProcessedAt:       timestamppb.New(time.Now().UTC()),
		UnitType:          item.GetUnitType().String(),
	}

	// This is to not lose the message if customer is not found
	if customer == nil {
		discountLineItemHydroSchema.CustomerId = item.GetCustomerId()
	} else {
		discountLineItemHydroSchema.CustomerId = customer.EnterpriseCustomerId

		if customer.IsCostCenterProxy {
			costCenterKey := &models.CostCenterKey{
				Key: &models.Key{
					PartitionKey: fmt.Sprintf("customer:%s:costCenters", customer.EnterpriseCustomerId),
					Id:           customer.CostCenterUUID,
				},
			}

			// query cost center name from cost center engine
			costCenter, err := h.costCenterEngine.Get(ctx, logger, costCenterKey)
			if err != nil {
				logger.WithError(err).Error("failed to find cost center")
			} else {
				costCenterEntity := hydroSchemaEntities.CostCenter{
					Uuid: costCenter.UUID,
					Name: costCenter.Name,
				}

				discountLineItemHydroSchema.CostCenter = &costCenterEntity
			}
		}
	}

	if preDiscountAmount-discountAmount > 0 {
		nanoDiscountAmount := nano.NewFromInt(discountAmount)
		nanoAppliedCostPerQuantity := nano.NewFromInt(item.AppliedCostPerQuantity)
		nanoDiscountQuantity := nanoDiscountAmount.Div(nanoAppliedCostPerQuantity)
		discountLineItemHydroSchema.DiscountQuantity = models.ToDecimalAmount[int64](nanoDiscountQuantity.Int64())
	} else {
		discountLineItemHydroSchema.DiscountQuantity = models.ToDecimalAmount[int64](item.Quantity)
	}

	err := h.hydroPublisher.Publish(&discountLineItemHydroSchema)
	if err != nil {
		logger.WithError(err).Error("failed to publish discount line item message")
	} else {
		logger.Info("published discount line item message")
	}
}
