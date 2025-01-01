package models

import (
	"fmt"
)

// PartitionKey: "[customer_id]:[sku]:YYYY:MM:DD:HH"
// e.g. "1061737:actions_linux_16_core:2023:6:28:13"
func NewCustomerSkuHourlyRollup(item *Item) *Item {
	usageTime := item.UsageAt.ToPartitionKey(Hourly)
	customerId := item.GetCustomerId()
	sku := item.GetSku()
	partitionKey := fmt.Sprintf("%s:%s:%s", customerId, sku, usageTime) // ByCustomerSku
	return copyItemWithPartitionKey(item, partitionKey)
}

// PartitionKey: "[customer_id]:YYYY:MM:DD:HH:byOrgRepoProductSku"
// e.g. "1061737:2023:6:28:13:byOrgRepoProductSku"
func NewCustomerOrgRepoProductSkuHourlyRollup(item *Item) *Item {
	usageTime := item.UsageAt.ToPartitionKey(Hourly)
	customerId := item.GetCustomerId()
	partitionKey := fmt.Sprintf("%s:%s:%s", customerId, usageTime, "byOrgRepoProductSku") // ByCustomerOrgRepoProductSku
	return copyItemWithPartitionKey(item, partitionKey)
}

func copyItemWithPartitionKey(item *Item, partitionKey string) *Item {
	// Copy item and amounts separately to maintain value rather than pointer to original value
	itemCopy := *item
	amountsCopy := *item.Amounts
	itemCopy.Amounts = &amountsCopy

	itemCopy.Id = itemCopy.PartitionKey
	itemCopy.PartitionKey = partitionKey
	return &itemCopy
}
