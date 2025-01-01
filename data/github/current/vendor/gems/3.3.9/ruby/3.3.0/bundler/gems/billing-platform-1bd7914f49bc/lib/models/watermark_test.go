package models

import (
	"testing"
	"time"
)

// These test examples use floats to represent actual amounts for readability. The
// test function will convert them to nano amounts as expected by the code under test.
type TestData struct {
	testCase                   string
	quantity                   float64
	usageAt                    *UsageTime
	expectedDailyQuantity      float64
	expectedFractionalQuantity float64
}

func TestAsItemWithWatermarkRollupPartitionKey(t *testing.T) {
	t.Parallel()

	january2021 := NewUsageTime().WithYear(2021).WithMonth(time.January)
	january1st2021 := january2021.WithDay(1)

	tests := []TestData{
		{
			testCase:                   "Full hour of usage",
			quantity:                   10.0,
			usageAt:                    january1st2021,
			expectedDailyQuantity:      240.0,
			expectedFractionalQuantity: 240.0,
		},
		{
			testCase:                   "Half hour of usage",
			quantity:                   10.0,
			usageAt:                    january1st2021.WithMinute(30),
			expectedDailyQuantity:      240.0,
			expectedFractionalQuantity: 235.0,
		},
		{
			testCase:                   "Full hour of usage halfway month",
			quantity:                   10.0,
			usageAt:                    january2021.WithDay(15),
			expectedDailyQuantity:      240.0,
			expectedFractionalQuantity: 240.0,
		},
		{
			testCase:                   "Full hour of negative usage",
			quantity:                   -10.0,
			usageAt:                    january1st2021,
			expectedDailyQuantity:      -240.0,
			expectedFractionalQuantity: -240.0,
		},
		{
			testCase:                   "Half hour of negative usage",
			quantity:                   -10.0,
			usageAt:                    january1st2021.WithMinute(30),
			expectedDailyQuantity:      -240.0,
			expectedFractionalQuantity: -235.0,
		},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.testCase, func(t *testing.T) {
			testRollup(t, tc)
		})
	}
}

func testRollup(t *testing.T, tc TestData) {
	item := &Item{
		UsageAt: *tc.usageAt,
		Amounts: &Amounts{
			Quantity: ToWholeAmount[int64](tc.quantity),
		},
		EntityDetail: &EntityDetail{
			CustomerId: "1",
		},
	}

	wholeDailyQuantity := ToWholeAmount[int64](tc.expectedDailyQuantity)
	wholeFractionalQuantity := ToWholeAmount[int64](tc.expectedFractionalQuantity)
	rollup := item.AsItemWithWatermarkRollupPartitionKey()

	if rollup.Amounts.Quantity != wholeDailyQuantity {
		t.Errorf("Expected %d, got %d for Quantity", wholeDailyQuantity, rollup.Amounts.Quantity)
	}

	if rollup.Amounts.FractionalQuantity != wholeFractionalQuantity {
		t.Errorf("Expected %d, got %d for FractionalQuantity", wholeFractionalQuantity, rollup.Amounts.FractionalQuantity)
	}
}

func TestAsActiveWatermarkCustomerProductSku(t *testing.T) {
	item := &Item{
		EntityDetail: &EntityDetail{
			CustomerId: "1",
		},
		Pricing: &Pricing{
			Product: "actions",
			Sku:     "actions_storage",
		},
	}

	calculatedKey := item.AsActiveWatermarkCustomerProductSku()
	expectedKey := "active:actions_storage:events"

	if calculatedKey.PartitionKey != expectedKey {
		t.Errorf("Expected %s, got %s for PartitionKey", expectedKey, calculatedKey.PartitionKey)
	}
}
