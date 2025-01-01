package models

import (
	"fmt"
	"testing"
	"time"

	"github.com/github/billing-platform/testing/stubs"
	"github.com/stretchr/testify/assert"
)

func TestNewActiveUsageMatchItem(t *testing.T) {

	customerId := stubs.GetRandomId64AsString()
	mockItem := &Item{
		UsageAt: *NewUsageTimeFromTime(time.Now()),
		EntityDetail: &EntityDetail{
			CustomerId: customerId,
			CostCenterDetail: &CostCenterDetail{
				EnterpriseCustomerId: customerId,
			},
		},
		Amounts: &Amounts{
			BilledAmount: 100,
			Quantity:     10,
			FullQuantity: 10,
		},
	}
	mockCustomer := &Customer{
		BillingTarget: Azure,
	}

	usageTime := mockItem.UsageAt.ToPartitionKey(Daily)
	ExactPartitionKey := fmt.Sprintf("activeUsageItems:%s", usageTime)

	result, _ := NewActiveUsageItem(mockItem, mockCustomer)

	assert.NotNil(t, result)
	assert.Equal(t, result.Key.PartitionKey, ExactPartitionKey)
	assert.Equal(t, result.Key.Id, customerId)

}
