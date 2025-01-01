package models

import (
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/internal/nano"
)

type HighWatermarkRolloverJobRun struct {
	Year  int64
	Month int64
	// Dry run mode (does not send any usage events during the rollover).
	DryRun bool
	// (Optional) Trigger high watermark workflow for a specific customer. Runs for all customers if not provided.
	CustomerId string
	// (Optional) Trigger high watermark workflow for a specific SKU. Runs for all SKUs if not provided.
	Sku string
}

func (jobRun *HighWatermarkRolloverJobRun) WithSku(sku string) *HighWatermarkRolloverJobRun {
	copy := *jobRun
	copy.Sku = sku

	return &copy
}

func (jobRun *HighWatermarkRolloverJobRun) WithCustomerId(customerId string) *HighWatermarkRolloverJobRun {
	copy := *jobRun
	copy.CustomerId = customerId

	return &copy
}

type HighWatermarkRolloverJob struct {
	ActiveCustomer *Key
	JobRun         *HighWatermarkRolloverJobRun
}

type HighWatermarkPartitionKey struct {
	KeyID      string
	ProductSKU string
	Year       int
	Month      int
}

type WatermarkID struct {
	KeyID      string
	ProductSKU string
	OrgID      int64
	RepoID     int64
}

type WatermarkPartitionKey struct {
	KeyID      string
	ProductSKU string
}

func (hwpk *HighWatermarkPartitionKey) String() string {
	return fmt.Sprintf("%s:highWatermark:%s:%d:%d", hwpk.KeyID, hwpk.ProductSKU, hwpk.Year, hwpk.Month)
}

type HighWatermarkEvent struct {
	Key
	FullQuantity           int64
	Quantity               int64
	BilledAmount           int64
	AppliedCostPerQuantity int64
	DailyDiscountQuantity  int64
	Product                string
	Sku                    string
	CustomerID             string
	UsageAt                UsageTime
}

func NewHighWatermarkEvent(item *Item) *HighWatermarkEvent {
	return &HighWatermarkEvent{
		Key:                    highWatermarkKeyForItem(item),
		FullQuantity:           item.FullQuantity,
		Quantity:               proratedQuantity(item.FullQuantity, item.UsageAt),
		BilledAmount:           item.BilledAmount,
		AppliedCostPerQuantity: item.AppliedCostPerQuantity,
		DailyDiscountQuantity:  0,
		Product:                item.GetProduct(),
		Sku:                    item.GetSku(),
		CustomerID:             item.EntityDetail.CustomerId,
		UsageAt:                item.UsageAt,
	}
}

// "${customerId}:highWatermark:${sku}:${year}:${month}"
// ex: "1234:highWatermark:copilot_for_business:2020:1"
func highWatermarkKeyForItem(item *Item) Key {
	key := ToSubscriptionPartitionKeyForGivenMonthHighWaterMark(
		item.EntityDetail.CustomerId,
		item.GetSku(),
		item.UsageAt,
	)
	// key := HighWatermarkPartitionKeyForItem(item)
	return Key{
		PartitionKey: key.PartitionKey,
		Id:           key.Id,
	}
}

func (hwid *WatermarkPartitionKey) String() string {
	return fmt.Sprintf("%s:watermark:%s", hwid.KeyID, hwid.ProductSKU)
}

func (hwid *WatermarkID) String() string {
	// TODO: make sure to account for lack of repoid/orgid with colon
	if hwid.RepoID == 0 {
		return fmt.Sprintf("%s:watermark:%s:%d", hwid.KeyID, hwid.ProductSKU, hwid.OrgID)
	} else if hwid.OrgID == 0 {
		return fmt.Sprintf("%s:watermark:%s", hwid.KeyID, hwid.ProductSKU)
	}
	return fmt.Sprintf("%s:watermark:%s:%d:%d", hwid.KeyID, hwid.ProductSKU, hwid.OrgID, hwid.RepoID)
}

func (billingItem *Item) IsHighWatermarkEvent() bool {
	return billingItem.GetMeterType() == PricingMeterDailyUnitCharge
}

// Partition used to know which customers to fetch high watermark events for. We always use the parent Customer (i.e, never a cost center)
// given cost center assignment happens when we generate line items.
func (billingItem *Item) AsActiveHighWatermarkCustomerProductSku() *Key {
	return &Key{
		PartitionKey: fmt.Sprintf(PartitionKeyActiveEvent, billingItem.GetSku()),
		Id:           billingItem.EntityDetail.CustomerId,
	}
}

func (highWatermarkEvent *HighWatermarkEvent) GetSku() string {
	return highWatermarkEvent.Sku
}

func (highWatermarkEvent *HighWatermarkEvent) ApplyPricing(pricing *Pricing) {
	currentPricing := pricing.GetPrice()

	nanoPricing := nano.NewFromInt(currentPricing)
	nanoQuantity := nano.NewFromInt(highWatermarkEvent.Quantity)

	result := nanoPricing.Mul(nanoQuantity)

	highWatermarkEvent.BilledAmount = result.Int64()
	highWatermarkEvent.AppliedCostPerQuantity = currentPricing
}

func proratedQuantity(originalQuantity int64, usageAt UsageTime) int64 {
	remainingDaysInMonth := int64(usageAt.RemainingDaysInMonth())
	lastDayOfTheMonth := int64(usageAt.LastDayOfTheMonth())

	// full item quantity --> number of days in the month
	// prorated quantity --> remaining days in the month
	// prorated quantity = full item quantity * remaining days in the month / number of days in the month
	return nano.NewFromInt(originalQuantity).Mul(nano.NewFromInt(remainingDaysInMonth)).Div(nano.NewFromInt(lastDayOfTheMonth)).Int64()
}

func (highWatermarkEvent *HighWatermarkEvent) DailyQuantity() (int, int64) {
	remainingDaysInMonth := highWatermarkEvent.UsageAt.RemainingDaysInMonth()
	dailyQuantity := nano.NewFromInt(highWatermarkEvent.Quantity).Div(nano.NewFromInt(int64(remainingDaysInMonth) * nano.NanoDivisor))

	return remainingDaysInMonth, dailyQuantity.Int64()
}

func (highWatermarkEvent *HighWatermarkEvent) SetDailyDiscountQuantity(discountItem *DiscountItem) {
	remainingDaysInMonth := int64(highWatermarkEvent.UsageAt.RemainingDaysInMonth())
	dailyQuantity := nano.NewFromInt(discountItem.Quantity).Div(nano.NewFromInt(remainingDaysInMonth * nano.NanoDivisor))
	highWatermarkEvent.DailyDiscountQuantity = dailyQuantity.Int64()
}

func (highWatermarkEvent *HighWatermarkEvent) GetPatchOperations() azcosmos.PatchOperations {
	po := azcosmos.PatchOperations{}
	po.AppendAdd("/UsageAt", highWatermarkEvent.UsageAt.UnixNano())
	po.AppendIncrement("/BilledAmount", highWatermarkEvent.BilledAmount)
	po.AppendIncrement("/FullQuantity", highWatermarkEvent.FullQuantity)
	po.AppendIncrement("/Quantity", highWatermarkEvent.Quantity)
	po.AppendIncrement("/DailyDiscountQuantity", highWatermarkEvent.DailyDiscountQuantity)

	return po
}
