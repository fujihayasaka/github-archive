package models

import (
	"fmt"

	"github.com/pkg/errors"
)

// UsageDate represents the target date the usage was captured for emission.
// This represents the Year/Month/Day.
type UsageDate struct {
	Year  int64
	Month int64
	Day   int64
}

type TargetType int

type ActiveUsageItem struct {
	*Key
	Target BillingTarget `json:"target"`
}

func NewActiveUsageItem(item *Item, customer *Customer) (*ActiveUsageItem, error) {
	// Check if item is null
	if item == nil {
		return nil, errors.New("item cannot be null")
	}

	// Check if customer is null
	if customer == nil {
		return nil, errors.New("customer cannot be null")
	}

	customerId := item.GetCustomerId()
	target := customer.BillingTarget // Azure or Zuora

	return &ActiveUsageItem{
		Key: &Key{
			PartitionKey: NewActiveUsageItemPartitionKey(item.UsageAt),
			Id:           customerId,
		},
		Target: target,
	}, nil
}

// PartitionKey: "activeUsageItems:YYYY:M:D"
// e.g. "activeUsageItems:2020:5:22"
func NewActiveUsageItemPartitionKey(usageTime UsageTime) string {
	usageTimestr := usageTime.ToPartitionKey(Daily)
	return fmt.Sprintf("activeUsageItems:%s", usageTimestr)
}

func GetUsageTimeFromUsageDate(usageDate *UsageDate) UsageTime {
	usageTime := NewUsageTime().WithYear(usageDate.Year).WithMonthInt(usageDate.Month).WithDay(int(usageDate.Day))
	return *usageTime
}
