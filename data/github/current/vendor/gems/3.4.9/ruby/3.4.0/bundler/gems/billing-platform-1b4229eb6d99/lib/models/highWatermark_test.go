package models

import (
	"testing"
	"time"
)

// These test examples use floats to represent actual amounts for readability. The
// test function will convert them to nano amounts as expected by the code under test.
type HighWatermarkTestData struct {
	testCase                 string
	quantity                 float64
	usageAt                  *UsageTime
	highWatermarkExpected    float64
	regularWatermarkExpected float64
	fullQuantityExpected     float64
}

func TestAsItemWithHighWatermarkPartitionKey(t *testing.T) {
	t.Parallel()

	november2021 := NewUsageTime().WithYear(2021).WithMonth(time.November)
	november1st2021 := november2021.WithDay(1)
	november16th2021 := november2021.WithDay(16)

	tests := []HighWatermarkTestData{
		{
			testCase:                 "positive seat emissions",
			quantity:                 10.0,
			usageAt:                  november1st2021,
			highWatermarkExpected:    10.0,
			regularWatermarkExpected: 10.0,
			fullQuantityExpected:     10.0,
		},
		{
			testCase:                 "negative seat emissions",
			quantity:                 -10.0,
			usageAt:                  november1st2021,
			highWatermarkExpected:    -10.0,
			regularWatermarkExpected: -10.0,
			fullQuantityExpected:     -10.0,
		},
		{
			testCase:                 "positive seat emission mid month",
			quantity:                 10.0,
			usageAt:                  november16th2021,
			highWatermarkExpected:    5.0,
			regularWatermarkExpected: 10.0,
			fullQuantityExpected:     10.0,
		},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.testCase, func(t *testing.T) {
			testHighWatermark(t, tc)
		})
	}
}

func createItem(tc HighWatermarkTestData) *Item {
	return &Item{
		UsageAt: *tc.usageAt,
		Amounts: &Amounts{
			Quantity:     ToWholeAmount[int64](tc.quantity),
			FullQuantity: ToWholeAmount[int64](tc.quantity),
		},
		EntityDetail: &EntityDetail{
			CustomerId: "1",
		},
		Pricing: &Pricing{
			Product: "product",
			Sku:     "sku",
		},
	}
}

func testHighWatermark(t *testing.T, tc HighWatermarkTestData) {
	item := createItem(tc)

	highWatermarkActual := NewHighWatermarkEvent(item)
	regularWatermarkActual := item.AsActualSubscriptionCountPartitionKey()

	highWatermarkExpected := ToWholeAmount[int64](tc.highWatermarkExpected)
	regularWatermarkExpected := ToWholeAmount[int64](tc.regularWatermarkExpected)
	fullQuantityExpected := ToWholeAmount[int64](tc.fullQuantityExpected)

	if highWatermarkActual.Quantity != highWatermarkExpected {
		t.Errorf("Expected %d, got %d for Quantity", highWatermarkExpected, highWatermarkActual.Quantity)
	}

	if highWatermarkActual.FullQuantity != fullQuantityExpected {
		t.Errorf("Expected %d, got %d for FullQuantity", fullQuantityExpected, highWatermarkActual.FullQuantity)
	}

	if regularWatermarkActual.Quantity != regularWatermarkExpected {
		t.Errorf("Expected %d, got %d for regular watermark", regularWatermarkExpected, regularWatermarkActual.Quantity)
	}
}
