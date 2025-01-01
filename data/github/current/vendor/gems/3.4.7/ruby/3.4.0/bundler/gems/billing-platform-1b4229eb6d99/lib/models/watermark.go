package models

import (
	"fmt"

	"github.com/github/billing-platform/internal/nano"
)

type WatermarkJobRun struct {
	Year  int64
	Month int64
	Day   int64
	Hour  int64
	// (Optional) Trigger watermark workflow for a specific customer. Runs for all customers if not provided.
	CustomerId string
	// (Optional) Trigger watermark workflow for a specific SKU. Runs for all SKUs if not provided.
	Sku string
}

func (jobRun *WatermarkJobRun) WithSku(sku string) *WatermarkJobRun {
	copy := *jobRun
	copy.Sku = sku

	return &copy
}

func (jobRun *WatermarkJobRun) ToUsageTime() *UsageTime {
	// TODO: Why are we inconsisent with int and int64?
	return NewUsageTime().WithYear(jobRun.Year).WithMonthInt(jobRun.Month).WithDay(int(jobRun.Day)).WithHour(int(jobRun.Hour))
}

type WatermarkJob struct {
	ActiveCustomer  *Key
	PartitionDetail *UsagePartitionDetail
	JobRun          *WatermarkJobRun
}

// Determines if the item is a delta event that should be treated differently than a line item that
// gets generated internally (denoted by IsProcessed())
func (billingItem *Item) IsWatermarkEvent() bool {
	return billingItem.GetMeterType() == PricingMeterPerHourUnitCharge && !billingItem.IsProcessed()
}

func IsProcessableEvent(usageTime *UsageTime, event *Item, upd *UsagePartitionDetail) bool {
	// Include all events prior to usageTime Hour but exclude any in the future
	if (upd.ActiveType == Hourly) && event.UsageAt.StartOfHour().After(usageTime.StartOfHour()) {
		return false
	}
	// Include all events prior to usageTime Day but exclude any future days
	if (upd.ActiveType == Daily) && event.UsageAt.StartOfDay().After(usageTime.StartOfDay()) {
		return false
	}
	// Include all events prior to usageTime Month but exclude any future months
	if (upd.ActiveType == Monthly) && event.UsageAt.StartOfMonth().After(usageTime.StartOfMonth()) {
		return false
	}
	if upd.Product != "" && event.GetProduct() != upd.Product {
		return false
	}
	if upd.Sku != "" && event.GetSku() != upd.Sku {
		return false
	}
	return true
}

// Partition used by the hourly watermark job to know which customers to fetch events for. We always use the parent Customer (i.e, never a cost center)
// given cost center assignment happens when we generate line items.
func (billingItem *Item) AsActiveWatermarkCustomerProductSku() *Key {
	partitionKey := fmt.Sprintf(PartitionKeyActiveEvent, billingItem.GetSku())
	return &Key{
		PartitionKey: partitionKey,
		Id:           billingItem.EntityDetail.CustomerId,
	}
}

// Partition used to rollup deleta events per Customer/Organiation/Repository. We always aggregate at the parent Customer level so that cost center
// assignment can happen when we generate line items.
func (billingItem *Item) AsItemWithWatermarkRollupPartitionKey() *Item {
	copy := *billingItem
	usageTime := billingItem.UsageAt.ToPartitionKey(Daily)
	copy.Id = fmt.Sprintf("%s:%s:events:rollups:%s:%d:%d", copy.EntityDetail.CustomerId, copy.GetSku(), usageTime, copy.EntityDetail.OrganizationId, copy.EntityDetail.RepositoryId)
	// Make it a daily rollup by setting all days into a single month partition
	copy.PartitionKey = fmt.Sprintf("%s:%s:events:rollups", copy.EntityDetail.CustomerId, copy.GetSku())

	amounts := *billingItem.Amounts

	fractionalHour := billingItem.UsageAt.BillableHoursForUsageDate(Hourly, &billingItem.UsageAt)
	nanoQuantity := nano.NewFromInt(billingItem.Amounts.Quantity)

	hoursLeftInDay := 24 - billingItem.UsageAt.Hour()
	partialHourAmount := nano.NewFromFloat(fractionalHour).Mul(nanoQuantity).Int64()
	remainingHoursAmount := (billingItem.Amounts.Quantity * int64(hoursLeftInDay-1))
	dailyAmount := remainingHoursAmount + partialHourAmount

	// The fractional quantity must be adjusted to account for how many hours are left in the day. For example,
	// if 1 GiB comes in at 12:30 then we would expect to see 11.5 GiB-Hours of usage for the day. Given our hourly
	// job will divide the FractionalQuantiy by 24, we need to adjust it so that the remaining 12 hours will sum to 11.5.
	amounts.FractionalQuantity = dailyAmount * 24 / int64(hoursLeftInDay)
	amounts.Quantity = billingItem.Amounts.Quantity * 24

	copy.Amounts = &amounts

	return &copy
}

func (billingItem *Item) AsItemWithWatermarkTotalRollupPartitionKey() *WatermarkTotalItem {
	partitionKey := fmt.Sprintf("%s:%s:events:rollups", billingItem.EntityDetail.CustomerId, billingItem.GetSku())
	id := fmt.Sprintf("%s:%s:events:rollups:%d:%d", billingItem.EntityDetail.CustomerId, billingItem.GetSku(), billingItem.EntityDetail.OrganizationId, billingItem.EntityDetail.RepositoryId)

	return &WatermarkTotalItem{
		AmountsItem: &AmountsItem{
			Key:     &Key{Id: id, PartitionKey: partitionKey},
			Amounts: billingItem.Amounts,
		},
		EntityDetail: billingItem.EntityDetail,
		IsTotal:      true,
	}
}

// This returns the partition detail for the current month, which will encompass
// all the active daily rollups for the current month.
// Todo: Previous months will need to be fetched
func GetPartitionDetailForDailyWatermarkRollup(jobRun *WatermarkJobRun) *UsagePartitionDetail {
	activeType := Monthly

	usageTime := jobRun.ToUsageTime()

	return &UsagePartitionDetail{
		UsageTime:  usageTime,
		ActiveType: activeType,
		Sku:        jobRun.Sku,
	}
}
