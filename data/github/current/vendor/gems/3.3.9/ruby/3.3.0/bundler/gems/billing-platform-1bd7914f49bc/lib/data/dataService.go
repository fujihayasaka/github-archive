package data

import (
	"context"
	"fmt"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydro_schemas_billingplatform_v1_entities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type DataService struct {
	hydroPublisher   interfaces.HydroPublisher
	usageEngine      *engines.UsageEngine
	costCenterEngine engines.CostCenterEngineInterface
	logger           log.Logger
	statter          stats.Client
}

func NewDataService(hydroPublisher interfaces.HydroPublisher, usageEngine *engines.UsageEngine, costCenterEngine engines.CostCenterEngineInterface, logger log.Logger, statter stats.Client) *DataService {
	return &DataService{
		hydroPublisher:   hydroPublisher,
		usageEngine:      usageEngine,
		costCenterEngine: costCenterEngine,
		logger:           logger,
		statter:          statter,
	}
}

// PublishAzureInvoiceMessage publishes an invoice message to Azure
func (d *DataService) PublishAzureInvoiceMessage(ctx context.Context, logger log.Logger, enterpriseInfo *models.EnterpriseInfo, item *models.Item, emission *models.AzureEmission, dryRun bool) {
	invoiceHydroSchema := d.generateInvoiceHydroMessage(ctx, logger, enterpriseInfo, item, emission)

	if dryRun {
		logger.Info("Skipping message publishing because of dry run")
		return
	}

	err := d.hydroPublisher.Publish(invoiceHydroSchema)
	if err != nil {
		logger.WithError(err).Error("failed to publish invoice message")
	} else {
		logger.Info("published invoice message")
	}
}

func (d *DataService) generateInvoiceHydroMessage(ctx context.Context, logger log.Logger, enterpriseInfo *models.EnterpriseInfo, item *models.Item, emission *models.AzureEmission) *hydroSchema.Invoice {
	now := timestamppb.New(time.Now().UTC())

	partitionDetail, err := models.GetPartitionDetailForItemDiscountLookup(item)
	if err != nil {
		return nil
	}

	// get discount items
	discountTotals, _, err := d.usageEngine.GetDiscountTotal(ctx, logger, partitionDetail)
	if err != nil {
		return nil
	}

	discountAmount := discountTotals.ToDecimal().DiscountAmount
	netBilledAmount := models.ToDecimalAmount[int64](item.BilledAmount) - discountAmount

	var skus = []*hydro_schemas_billingplatform_v1_entities.SkuInvoice{
		{
			Name:                  item.GetSku(),
			Product:               item.GetProduct(),
			GrossQuantity:         models.ToDecimalAmount[int64](item.Quantity),
			DiscountQuantity:      discountTotals.ToDecimal().Quantity,
			NetQuantity:           models.ToDecimalAmount[int64](item.Quantity) - discountTotals.ToDecimal().Quantity,
			DiscountAmount:        discountAmount,
			GrossBilledAmount:     models.ToDecimalAmount[int64](item.BilledAmount),
			NetBilledAmount:       netBilledAmount,
			UnitType:              item.GetUnitType().String(),
			BillingTargetChargeId: item.Pricing.AzureMeterId,
		},
	}

	invoiceHydroSchema := hydroSchema.Invoice{
		InvoiceId:            emission.Id,
		CustomerId:           enterpriseInfo.EnterpriseCustomerId,
		Skus:                 skus,
		GrossBilledAmount:    models.ToDecimalAmount[int64](item.BilledAmount),
		DiscountAmount:       discountAmount,
		NetAmountDue:         netBilledAmount,
		PaymentProcessorId:   enterpriseInfo.AzureAccountId,
		UsageAt:              timestamppb.New(item.UsageAt.Time),
		GeneratedByBillingAt: now,
		Target:               hydro_schemas_billingplatform_v1_entities.BillingTarget_AZURE,
		InvoiceYear:          int64(item.UsageAt.Year()),
		InvoiceMonth:         int64(item.UsageAt.Month()),
		InvoiceDay:           int64(item.UsageAt.Day()),
		BillingTargetId:      enterpriseInfo.AzureAccountId,
	}

	if item.IsCostCenterProxy() {
		costCenterKey := &models.CostCenterKey{
			Key: &models.Key{
				PartitionKey: fmt.Sprintf("customer:%s:costCenters", enterpriseInfo.EnterpriseCustomerId),
				Id:           enterpriseInfo.CostCenterUUID,
			},
		}

		costCenter, err := d.costCenterEngine.Get(ctx, logger, costCenterKey)
		if err != nil {
			logger.WithError(err).Error("failed to find cost center")
		} else {
			costCenterEntity := &hydro_schemas_billingplatform_v1_entities.CostCenter{
				Uuid: costCenter.UUID,
				Name: costCenter.Name,
			}

			invoiceHydroSchema.CostCenter = costCenterEntity
		}
	}

	return &invoiceHydroSchema
}
