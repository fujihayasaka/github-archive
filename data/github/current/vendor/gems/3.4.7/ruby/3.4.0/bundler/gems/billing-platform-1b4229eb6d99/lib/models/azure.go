package models

import (
	"encoding/base64"
	"encoding/json"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/data/aztables"
	"github.com/google/uuid"
)

// AzureUsageDate represents the target date the usage was captured for emission.
// CustomerId can be supplied to specify the usage for a specific customer.
// This represents the Year/Month/Day and a CustomerId.
type AzureUsageDate struct {
	CustomerId string
	Year       int64
	Month      int64
	Day        int64
}

func GenerateUUID() string {
	return uuid.NewString()
}

func NewAzureEntity() aztables.Entity {
	return aztables.Entity{
		PartitionKey: GenerateUUID(),
		RowKey:       GenerateUUID(),
	}
}

func NewAzureEntityProperties(azureAccountId string, item *Item, location string, discountQuantity float64) map[string]interface{} {
	customerId := item.GetCustomerId()
	return map[string]interface{}{
		"SubscriptionId": azureAccountId,
		"Quantity":       GetAzureQuantity(item, discountQuantity),
		"MeterId":        item.GetAzureMeterId(),
		"EventDateTime":  aztables.EDMDateTime(item.UsageAt.Time),
		"ResourceUri":    GetAzureResourceUri(azureAccountId, customerId),
		"Location":       location,
		"EventId":        GenerateAzureEventId(azureAccountId, customerId, item.GetAzureMeterId(), item.UsageAt),
	}

}

func CreateUsageEntity(azureAccountId string, item *Item, location string, discountQuantity float64) aztables.EDMEntity {
	return aztables.EDMEntity{
		Entity:     NewAzureEntity(),
		Properties: NewAzureEntityProperties(azureAccountId, item, location, discountQuantity),
	}
}

func GetAzureResourceUri(azureAccountId string, customerId string) string {
	return fmt.Sprintf("/subscriptions/%s/providers/GitHub/EnterpriseAccount/customer-%s", azureAccountId, customerId)
}

func GetAzureQuantity(item *Item, discountQuantity float64) float64 {
	itemQuantity := item.Amounts.ToDecimal().Quantity
	if discountQuantity > 0 {
		if (itemQuantity - discountQuantity) < 0 {
			return 0
		}

		return itemQuantity - discountQuantity
	}

	return itemQuantity
}

func GenerateAzureEventId(azureAccountId string, customerId string, azureMeterId string, usageAt UsageTime) string {
	return uuid.NewSHA1(uuid.NameSpaceOID, []byte(
		fmt.Sprintf("%s/providers/GitHub/EnterpriseAccount/customer-%s/%s/%s", azureAccountId, customerId, azureMeterId, usageAt),
	)).String()
}

func GenerateAzureQueueMessage(usageItem aztables.EDMEntity) (string, error) {
	data := map[string]interface{}{
		"partitionId": usageItem.PartitionKey,
		"batchId":     GenerateUUID(),
	}

	byteData, err := json.Marshal(data)
	if err != nil {
		return "", fmt.Errorf("error marshalling data for queue message: %w", err)
	}

	encodedData := base64.StdEncoding.EncodeToString(byteData)

	return encodedData, nil
}

func GetPartitionDetailForDailyAzureEmission(usageDate *AzureUsageDate) (*UsagePartitionDetail, error) {
	activeType := Daily
	usageTime := NewUsageTime().WithYear(usageDate.Year).WithMonthInt(usageDate.Month).WithDay(int(usageDate.Day))

	return &UsagePartitionDetail{
		UsageTime:  usageTime,
		ActiveType: activeType,
	}, nil
}
