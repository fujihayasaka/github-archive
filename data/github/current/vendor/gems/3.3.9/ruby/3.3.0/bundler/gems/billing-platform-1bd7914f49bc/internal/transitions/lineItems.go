package transitions

import (
	"context"
	"fmt"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type LineItemsBackfillTransition struct {
	ctx              context.Context
	cfg              *config.Config
	logger           log.Logger
	customerEngine   *engines.CustomerEngine
	costCenterEngine engines.CostCenterEngineInterface
	usageEngine      *engines.UsageEngine
	hydroPublisher   interfaces.HydroPublisher
}

func NewLineItemsBackfillTransition(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	customerEngine *engines.CustomerEngine,
	costCenterEngine engines.CostCenterEngineInterface,
	usageEngine *engines.UsageEngine,
	hydroPublisher interfaces.HydroPublisher,
) *LineItemsBackfillTransition {
	return &LineItemsBackfillTransition{
		ctx:              ctx,
		cfg:              cfg,
		logger:           logger,
		customerEngine:   customerEngine,
		costCenterEngine: costCenterEngine,
		usageEngine:      usageEngine,
		hydroPublisher:   hydroPublisher,
	}
}

const FirstUsageLineItemUsageAt = 1692642455
const FirstDiscountLineItemUsageAt = 1692740389

func (t *LineItemsBackfillTransition) Run(dryRun bool, customerID string) error {
	t.logger.Info("Running line items transition...")

	customer, err := t.customerEngine.Get(t.ctx, t.logger, customerID)
	if err != nil {
		return err
	}

	if customer == nil {
		return fmt.Errorf("customer not found: %s", customerID)
	}

	err = t.GetAndPublishLineItems(dryRun, customer)
	if err != nil {
		return err
	}

	// The customer might have cost centers that we will have to iterate through and submit line items for
	// TODO: Replace all occurrences of 'bperr' with 'err' to handle errors throughout the code.
	// we will replace the standard error package with the bperrors package and use
	// the err variable to handle errors throughout the code.
	costCenters, bperr := t.costCenterEngine.GetAllCostCenters(t.ctx, t.logger, customer)
	if bperr != nil {
		return errors.New(bperr.Error())
	}

	for _, costCenter := range costCenters {
		t.logger.Info("Publishing cost center line items...")
		costCenterCustomer, err := t.customerEngine.Get(t.ctx, t.logger, costCenter.CostCenterKey.UUID)
		if err != nil {
			t.logger.WithError(err).Error("failed to get cost center customer")
			continue
		}

		if costCenterCustomer == nil {
			t.logger.Info("Cost center customer not found")
			continue
		}

		err = t.GetAndPublishLineItems(dryRun, costCenterCustomer)
		if err != nil {
			return err
		}
	}

	return nil
}

func (t *LineItemsBackfillTransition) GetAndPublishLineItems(dryRun bool, customer *models.Customer) error {
	// use customer.GetCustomerId() instead of customer.EnterpriseCustomerId because we want to query the usage for the customer OR cost center if it exists
	partitionDetail := &models.UsagePartitionDetail{
		UsageEntityId: customer.GetCustomerId(),
		UsageTime:     models.NewUsageTime().WithYear(2023),
		ActiveType:    models.Yearly,
	}

	monthlyUsageLineItems, err := t.usageEngine.GetLineItems(t.ctx, t.logger, partitionDetail)
	if err != nil {
		return err
	}

	numItemsPublished := int64(0)
	numDiscountItemsPublished := int64(0)
	numItemsFound := int64(0)
	numDiscountItemsFound := int64(0)
	totalQuantity := int64(0)
	totalDiscountQuantity := int64(0)

	// get all SKU monthly roll up values for the customer
	for _, monthlyUsageLineItem := range monthlyUsageLineItems {
		dailyUsageLineItems, err := t.usageEngine.GetLineItemsFromPartitionKey(t.ctx, t.logger, monthlyUsageLineItem.Id)
		if err != nil {
			t.logger.WithError(err).Error("failed to get daily usage line items")
			break
		}

		for _, dailyUsageLineItem := range dailyUsageLineItems {
			// we first started to send discount line items mid day on the 22nd so we want to disallow further queries for days after the 22nd
			day := dailyUsageLineItem.UsageAt.Time.Day()
			if day > 22 {
				t.logger.Info("Skipping usage because the day is after the 22nd")
				continue
			}

			hourlyUsageLineItems, err := t.usageEngine.GetLineItemsFromPartitionKey(t.ctx, t.logger, dailyUsageLineItem.Id)
			if err != nil {
				t.logger.WithError(err).Error("failed to get hourly usage line items")
				break
			}

			for _, hourlyUsageLineItem := range hourlyUsageLineItems {
				rawUsageLineItems, err := t.usageEngine.GetLineItemsFromPartitionKey(t.ctx, t.logger, hourlyUsageLineItem.Id)
				if err != nil {
					t.logger.WithError(err).Error("failed to get raw usage line items")
					break
				}

				rawDiscountLineItems, err := t.usageEngine.GetDiscountLineItemsFromPartitionKey(t.ctx, t.logger, hourlyUsageLineItem.Id+":discount")
				if err != nil {
					t.logger.WithError(err).Error("failed to get raw discount line items")
					break
				}

				numItemsFound += int64(len(rawUsageLineItems))
				numDiscountItemsFound += int64(len(rawDiscountLineItems))

				for _, rawUsageLineItem := range rawUsageLineItems {
					// find an item in the discount line items that has the same ID as the minute usage line item
					var matchingDiscountLineItem *models.DiscountItem
					for _, rawDiscountLineItem := range rawDiscountLineItems {
						if rawDiscountLineItem.Id == rawUsageLineItem.Id {
							matchingDiscountLineItem = rawDiscountLineItem
							break
						}
					}

					// if we have a matching discount line item, publish both the usage and discount line items, otherwise we just publish a usage line item message
					if matchingDiscountLineItem != nil {
						t.logger.Info("Publishing usage and discount line items...")

						var publicRepoDiscountAvailable bool
						enterpriseInfo, err := t.customerEngine.GetEnterpriseInfoFromItem(t.ctx, t.logger, rawUsageLineItem)
						if err != nil {
							t.logger.WithError(err).Error("failed to get enterprise info")
						} else {
							repoId := rawUsageLineItem.GetRepoId()
							billForPublicRepoUsage := enterpriseInfo.BillForPublicRepoUsage
							publicRepoDiscountAvailable, err = t.customerEngine.PublicRepoDiscountApplicable(t.ctx, t.logger, customer.Id, rawUsageLineItem.GetSku(), repoId, billForPublicRepoUsage)
							if err == nil {
								t.logger.Info("Queried public repo discount", kvp.Bool("publicRepoDiscountAvailable", publicRepoDiscountAvailable))
							} else {
								t.logger.WithError(err).Error("Failed to determine if public repo discount is applicable, setting to false")
							}
						}

						// this is the first timestamp for a discount line item that is available in the DW, skip sending discounts after this
						var publishErr error
						if matchingDiscountLineItem.UsageAt.Unix() < FirstDiscountLineItemUsageAt {
							if dryRun {
								t.logger.Info("Skipping discount publishing because of dry run")
								numDiscountItemsPublished += 1
								totalDiscountQuantity += matchingDiscountLineItem.Quantity
							} else {
								publishErr = t.PublishDiscountLineItemMessage(customer, rawUsageLineItem, matchingDiscountLineItem, publicRepoDiscountAvailable)
								if publishErr == nil {
									numDiscountItemsPublished += 1
									totalDiscountQuantity += matchingDiscountLineItem.Quantity
								}
							}
						}

						if publishErr == nil {
							// this is the first timestamp for a usage line item that is available in the DW, skip sending usage after this
							if rawUsageLineItem.UsageAt.Unix() < FirstUsageLineItemUsageAt {
								if dryRun {
									t.logger.Info("Skipping usage line item publishing because of dry run")
									numItemsPublished += 1
									totalQuantity += rawUsageLineItem.Quantity
								} else {
									publishErr = t.PublishUsageLineItemMessage(customer, rawUsageLineItem, matchingDiscountLineItem)
									if publishErr != nil {
										t.logger.Info("Failed to publish usage line item")
									} else {
										numItemsPublished += 1
										totalQuantity += rawUsageLineItem.Quantity
									}
								}
							}
						} else {
							t.logger.Info("Failed to publish discount line item, skipping usage line item")
						}
					} else {
						t.logger.Info("Publishing usage line items...")
						if rawUsageLineItem.UsageAt.Unix() < FirstUsageLineItemUsageAt {
							if dryRun {
								t.logger.Info("Skipping usage line item publishing because of dry run")
								numItemsPublished += 1
								totalQuantity += rawUsageLineItem.Quantity
							} else {
								publishErr := t.PublishUsageLineItemMessage(customer, rawUsageLineItem, matchingDiscountLineItem)
								if publishErr != nil {
									t.logger.Info("Failed to publish usage line item")
								} else {
									numItemsPublished += 1
									totalQuantity += rawUsageLineItem.Quantity
								}
							}
						}
					}
				}
			}
		}
	}

	t.logger.Info("Finished publishing line items")
	t.logger.Info("Finished publishing discount line items")

	return nil
}

func (t *LineItemsBackfillTransition) PublishUsageLineItemMessage(customer *models.Customer, item *models.Item, discountItem *models.DiscountItem) error {
	usageLineItemHydroSchema := hydroSchema.UsageLineItem{
		UsageUuid:              item.Id,
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
		ProcessedAt:            timestamppb.New(time.Now().UTC()),
	}

	if customer == nil {
		usageLineItemHydroSchema.CustomerId = item.GetCustomerId()
		usageLineItemHydroSchema.Target = hydroSchemaEntities.BillingTarget_UNKNOWN_TARGET
	} else {
		usageLineItemHydroSchema.CustomerId = customer.EnterpriseCustomerId
		usageLineItemHydroSchema.Target = customer.GetHydroBillingTarget()
	}

	if discountItem == nil {
		usageLineItemHydroSchema.DiscountAmount = 0
		usageLineItemHydroSchema.NetAmount = models.ToDecimalAmount[int64](item.BilledAmount)
	} else {
		usageLineItemHydroSchema.DiscountAmount = models.ToDecimalAmount[int64](discountItem.DiscountAmount)
		usageLineItemHydroSchema.NetAmount = models.ToDecimalAmount[int64](item.BilledAmount - discountItem.DiscountAmount)
	}

	if err := t.hydroPublisher.Publish(&usageLineItemHydroSchema); err != nil {
		return errors.Wrap(err, "failed to publish usage line item")
	}

	return nil
}

func (t *LineItemsBackfillTransition) PublishDiscountLineItemMessage(customer *models.Customer, item *models.Item, discountItem *models.DiscountItem, publicRepoDiscountAvailable bool) error {
	discountType := hydroSchemaEntities.DiscountType_PLAN

	var sourceDiscountId string
	if publicRepoDiscountAvailable {
		discountType = hydroSchemaEntities.DiscountType_PUBLIC_REPO
		sourceDiscountId = models.PublicRepo100PercentDiscountUUID
	} else {
		if item.GetSku() == "actions_storage" {
			switch {
			case customer.DiscountPlanName == "team":
				sourceDiscountId = "c36136bd-94b2-474e-b35e-495b8664463c"
			case customer.DiscountPlanName == "free_organization":
				sourceDiscountId = "a58e09c8-a68b-4d64-8b93-ff5c3f1fb4a8"
			default:
				sourceDiscountId = "1596aea4-44d4-4939-98ba-4ea3bb4749cb"
			}
		} else {
			switch {
			case customer.DiscountPlanName == "enterprise_trial" || customer.DiscountPlanName == "team":
				sourceDiscountId = "e8cdc13b-0de4-45f2-afa9-6619209084e5"
			case customer.DiscountPlanName == "free_organization":
				sourceDiscountId = "e7000b30-6953-45d8-aef5-dffd4ca8a46f"
			default:
				sourceDiscountId = "85679075-fe74-461e-9c22-808ac1393944"
			}
		}
	}

	discountLineItemHydroSchema := hydroSchema.DiscountLineItem{
		DiscountUuid:      sourceDiscountId,
		LineItemId:        discountItem.Id,
		Sku:               discountItem.Pricing.GetSku(),
		Product:           discountItem.Pricing.GetProduct(),
		DiscountAmount:    models.ToDecimalAmount[int64](discountItem.DiscountAmount),
		DiscountType:      discountType,
		PreDiscountAmount: models.ToDecimalAmount[int64](item.BilledAmount),
		SourceDiscountId:  sourceDiscountId,
		DiscountedAt:      timestamppb.New(discountItem.UsageAt.Time),
		ProcessedAt:       timestamppb.New(time.Now().UTC()),
	}

	if customer == nil {
		discountLineItemHydroSchema.CustomerId = item.GetCustomerId()
	} else {
		discountLineItemHydroSchema.CustomerId = customer.EnterpriseCustomerId
	}

	if item.BilledAmount-discountItem.DiscountAmount > 0 {
		nanoDiscountAmount := nano.NewFromInt(discountItem.DiscountAmount)
		nanoAppliedCostPerQuantity := nano.NewFromInt(item.AppliedCostPerQuantity)
		nanoDiscountQuantity := nanoDiscountAmount.Div(nanoAppliedCostPerQuantity)
		discountLineItemHydroSchema.DiscountQuantity = models.ToDecimalAmount[int64](nanoDiscountQuantity.Int64())
	} else {
		discountLineItemHydroSchema.DiscountQuantity = models.ToDecimalAmount[int64](item.Quantity)
	}

	if err := t.hydroPublisher.Publish(&discountLineItemHydroSchema); err != nil {
		return errors.Wrap(err, "failed to publish discount line item")
	}

	return nil
}
