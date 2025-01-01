package data

import (
	"context"
	"fmt"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydro_schemas_billingplatform_v1_entities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type DataService struct {
	hydroPublisher   interfaces.HydroPublisher
	usageEngine      engines.UsageEngineInterface
	costCenterEngine engines.CostCenterEngineInterface
	discountEngine   engines.DiscountEngineInterface
	logger           log.Logger
	statter          stats.Client
}

func NewDataService(hydroPublisher interfaces.HydroPublisher, usageEngine engines.UsageEngineInterface, costCenterEngine engines.CostCenterEngineInterface, discountEngine engines.DiscountEngineInterface, logger log.Logger, statter stats.Client) *DataService {
	return &DataService{
		hydroPublisher:   hydroPublisher,
		usageEngine:      usageEngine,
		costCenterEngine: costCenterEngine,
		discountEngine:   discountEngine,
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

	if invoiceHydroSchema == nil {
		logger.Info("Skipping message publishing because invoiceHydroSchema is nil")
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
	discountQuantity, err := d.discountEngine.GetDailyDiscountQuantity(ctx, logger, item)
	if err != nil {
		logger.WithError(err).Error("failed to get daily discount quantity for invoice message")
		return nil
	}

	// we need to convert to nano to avoid overflows when calculating the $ amounts
	nanoPricing := nano.NewFromInt(item.AppliedCostPerQuantity)
	nanoQuantity := nano.NewFromInt(item.Quantity)
	nanoDiscountQuantity := nano.NewFromInt(
		models.ToWholeAmount[int64](discountQuantity),
	)

	// we should not use item.BilledAmount to calculate the $ amounts here as the billed amount does not
	// take into account proration adjustments for watermark and high watermark SKUs
	billedAmount := nanoPricing.Mul(nanoQuantity)
	discountAmount := nanoPricing.Mul(nanoDiscountQuantity)
	netBilledAmount := billedAmount.Sub(discountAmount)

	skuInvoice := &hydro_schemas_billingplatform_v1_entities.SkuInvoice{
		Name:                  item.GetSku(),
		Product:               item.GetProduct(),
		GrossQuantity:         models.ToDecimalAmount[int64](item.Quantity),
		DiscountQuantity:      discountQuantity,
		NetQuantity:           models.ToDecimalAmount[int64](nanoQuantity.Sub(nanoDiscountQuantity).Int64()),
		DiscountAmount:        models.ToDecimalAmount[int64](discountAmount.Int64()),
		GrossBilledAmount:     models.ToDecimalAmount[int64](billedAmount.Int64()),
		NetBilledAmount:       models.ToDecimalAmount[int64](netBilledAmount.Int64()),
		UnitType:              item.GetUnitType().String(),
		BillingTargetChargeId: item.Pricing.AzureMeterId,
	}

	invoiceHydroSchema := hydroSchema.Invoice{
		InvoiceId:            emission.Id,
		CustomerId:           enterpriseInfo.EnterpriseCustomerId,
		Skus:                 []*hydro_schemas_billingplatform_v1_entities.SkuInvoice{skuInvoice},
		GrossBilledAmount:    skuInvoice.GrossBilledAmount,
		DiscountAmount:       skuInvoice.DiscountAmount,
		NetAmountDue:         skuInvoice.NetBilledAmount,
		PaymentProcessorId:   enterpriseInfo.AzureAccountId,
		UsageAt:              timestamppb.New(item.UsageAt.Time),
		GeneratedByBillingAt: timestamppb.New(time.Now().UTC()),
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
