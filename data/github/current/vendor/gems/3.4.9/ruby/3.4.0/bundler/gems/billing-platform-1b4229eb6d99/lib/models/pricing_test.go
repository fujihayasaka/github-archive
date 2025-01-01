package models

import (
	"testing"
	"time"

	"github.com/github/billing-platform/internal/nano"
	"github.com/stretchr/testify/assert"

	"github.com/onsi/gomega"
)

func Test_NewPricing_Converts_To_WholePrices(t *testing.T) {

	price, err := NewPricingAsWholeAmount("", "", 8)

	if err != nil {
		t.Errorf("expected no error, got %s", err)
	}
	if price.Price != 8000000000 {
		t.Errorf("expected price to be 800000, got %d", price.Price)
	}

	// smallest price supported is
	price, err = NewPricingAsWholeAmount("", "", PricingMinimumSupportedDecimalPrice)
	if err != nil {
		t.Errorf("expected no error, got %s", err)
	}
	if price.Price != 1 {
		t.Errorf("expected price to be 1, got %d", price.Price)
	}

	// max price supported is
	price, err = NewPricingAsWholeAmount("", "", PricingMaximumSupportedDecimalPrice)
	if err != nil {
		t.Errorf("expected no error, got %s", err)
	}
	if price.Price != PricingMaxValueAsNano {
		t.Errorf("expected price to be %d, got %d", PricingMaxValueAsNano, price.Price)
	}

	// price to small, throw error
	price, err = NewPricingAsWholeAmount("", "", PricingMinimumSupportedDecimalPrice/10)
	if err == nil {
		t.Errorf("expected error when price to small, got %s", err)
	}
	if price != nil {
		t.Errorf("expected price to be nil, got %d", price.Price)
	}

	// overthrow
	price, err = NewPricingAsWholeAmount("", "", 92233720368547758077)
	if err == nil {
		t.Errorf("expected error when price to small, got %s", err)
	}
	if price != nil {
		t.Errorf("expected price to be nil, got %d", price.Price)
	}
}

func Test_ToWholeAmountOverflow(t *testing.T) {
	amount := ToWholeAmount[int64](PricingMaximumSupportedDecimalPrice)
	if amount != PricingMaxValueAsNano {
		t.Errorf("expected amount to be 9223372036000000000, got %d, why is max not working?", amount)
	}
	// when we add 1 to the max, we should overflow. we know its overflown because the amount is negative
	amount = ToWholeAmount[int64](9223372036 + 1)
	if amount > 0 {
		t.Errorf("expected amount to have overflown, got %d, why is max not working?", amount)
	}

}

func Test_ToWholeAmount(t *testing.T) {
	tests := []struct {
		name                string
		input               float64
		expectedAmountWhole int64
	}{
		{"isThisAnFloatIssue", 4.1, 4100000000}, // 4.0999999999999996447286321199499070644378662109375 unless we round
		{"isThisAnFloatIssue", 4.01, 4010000000},
		{"isThisAnFloatIssue", 4.001, 4001000000},
		{"isThisAnFloatIssue", 4.0001, 4000100000},
		{"isThisAnFloatIssue", 4.00001, 4000010000},
		{"maxPercision", 4.0000000001, 4000000000}, // only support 5 decimal places of preciion
		{"RoundingIsCorrectForGreaterThan5", 99.5, 99500000000},
		{"RoundingIsCorrectFor9A", 99.9, 99900000000},
		{"RoundingIsCorrectFor9B", 99.9999, 99999900000},
		{"RoundingIsCorrectFor9C", 99.9998, 99999800000},
		{"RoundingIsCorrectFor9H", 99.99999999999, 99999999999},
		{"RoundingIsCorrectFor9G", 99.999999999999, 99999999999},
		{"0", 0, 0},
		{"small", 0.00001, 10000},
		{"small", 0.000000001, 1},
		{"min", 0.000000067, 67},
		{"max", PricingMaximumSupportedDecimalPrice, PricingMaxValueAsNano},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			amount := ToWholeAmount[int64](tt.input)
			if amount != tt.expectedAmountWhole {
				t.Errorf("expected billed amount to be %d, got %d", tt.expectedAmountWhole, amount)
			}
		})
	}
}

func Test_ApplyPricing(t *testing.T) {
	tests := []struct {
		name                  string
		price                 float64
		quantity              float64
		expectedAmountWhole   int64
		expectedAmountDecimal float64
	}{
		{"minAmount", PricingMinimumSupportedDecimalPrice, 1, 1, PricingMinimumSupportedDecimalPrice},
		{"maxAmount", PricingMaximumSupportedDecimalPrice, 1, 9223372036000000000, 9223372036},
		{"maxQuantityForMinPrice", PricingMinimumSupportedDecimalPrice, PricingMaximumSupportedDecimalPrice, 9223372036, 9.2233720360},
		{"randomRegularAmounts", 0.08, 1892382382, 151390590560000000, 151390590.560000},
		{"moreTestAmounts", 2, 100, 200000000000, 200},
		{"isThisAnFloatIssue", 4.1, 4.1, 16810000000, 16.810000},
		{"budgetExample", 13.7464, 4.56735, 62784620040, 62.78462004},
		{"actions_storage", 0.00033602, 5.550001084, 1864911, 0.001864911},
		{"actions_storage rounding issue", 0.00033602, 5.550000000, 1864911, 0.001864911}, // pointing out that we ignore the 1084 part due to rounding
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			billingItem := &Item{
				Amounts: NewAmountAsWholeNumbers(0, tt.quantity),
			}
			targetPrice := tt.price
			pricing, err := NewPricingAsWholeAmount("", "", targetPrice)
			if err != nil {
				t.Errorf("expected no error, got %s", err)
			}

			billingItem.ApplyPricing(pricing)

			wholeAmount := billingItem.Amounts
			if wholeAmount.BilledAmount != tt.expectedAmountWhole {
				t.Errorf("expected billed amount to be %d, got %d", tt.expectedAmountWhole, wholeAmount.BilledAmount)
			}

			amount := billingItem.Amounts.ToDecimal()
			if amount.BilledAmount != tt.expectedAmountDecimal {
				t.Errorf("expected billed amount to be %.10f, got %.10f", tt.expectedAmountDecimal, amount.BilledAmount)
			}
		})
	}
}

func Test_CalculateQuantity(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	pricing := Pricing{Price: 10}
	quantity := pricing.CalculateQuantity(100)
	humanReadableQuantity := nano.ToInt64(quantity)
	g.Expect(humanReadableQuantity).To(gomega.Equal(int64(10)))

	pricing = Pricing{Price: 33}
	quantity = pricing.CalculateQuantity(100)
	humanReadableQuantity = nano.ToInt64(quantity)
	g.Expect(humanReadableQuantity).To(gomega.Equal(int64(3)))
}

func Test_Pricing_GetProduct(t *testing.T) {
	testPricing := &Pricing{
		Price:              100,
		Product:            "actions",
		Sku:                "actions_linux",
		MeterType:          PricingMeterDefault,
		FriendlyName:       "Actions Linux",
		AzureMeterId:       "123",
		FreeForPublicRepos: false,
		EffectiveAt:        time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
		UnitType:           UnitTypeMinutes,
	}
	product := testPricing.GetProduct()
	if product != testPricing.Product {
		t.Errorf("expected product to be %s, got %s", testPricing.Product, product)
	}
	testPricing = nil
	product = testPricing.GetProduct()
	if product != "" {
		t.Errorf("expected product to be empty, got %s", product)
	}
}

func Test_Pricing_GetSku(t *testing.T) {
	testPricing := &Pricing{
		Price:              100,
		Product:            "actions",
		Sku:                "actions_linux",
		MeterType:          PricingMeterDefault,
		FriendlyName:       "Actions Linux",
		AzureMeterId:       "123",
		FreeForPublicRepos: false,
		EffectiveAt:        time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
		UnitType:           UnitTypeMinutes,
	}
	sku := testPricing.GetSku()
	if sku != testPricing.Sku {
		t.Errorf("expected product to be %s, got %s", testPricing.Sku, sku)
	}
	testPricing = nil
	sku = testPricing.GetSku()
	if sku != "" {
		t.Errorf("expected product to be empty, got %s", sku)
	}
}

func Test_Pricing_GetPrice(t *testing.T) {
	testPricing := &Pricing{
		Price:              100,
		Product:            "actions",
		Sku:                "actions_linux",
		MeterType:          PricingMeterDefault,
		FriendlyName:       "Actions Linux",
		AzureMeterId:       "123",
		FreeForPublicRepos: false,
		EffectiveAt:        time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
		UnitType:           UnitTypeMinutes,
	}
	price := testPricing.GetPrice()
	if price != testPricing.Price {
		t.Errorf("expected price to be %v, got %v", testPricing.Price, price)
	}
	testPricing = nil
	price = testPricing.GetPrice()
	if price != 0 {
		t.Errorf("expected price to be 0, got %v", price)
	}
}

func Test_Pricing_GetFreeForPublicRepos(t *testing.T) {
	testPricing := &Pricing{
		Price:              100,
		Product:            "actions",
		Sku:                "actions_linux",
		MeterType:          PricingMeterDefault,
		FriendlyName:       "Actions Linux",
		AzureMeterId:       "123",
		FreeForPublicRepos: false,
		EffectiveAt:        time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
		UnitType:           UnitTypeMinutes,
	}
	freeForPublicRepos := testPricing.GetFreeForPublicRepos()
	if freeForPublicRepos != testPricing.FreeForPublicRepos {
		t.Errorf("expected FreeForPublicRepos to be %v, got %v", testPricing.FreeForPublicRepos, freeForPublicRepos)
	}
	testPricing = nil
	freeForPublicRepos = testPricing.GetFreeForPublicRepos()
	if freeForPublicRepos != false {
		t.Errorf("expected FreeForPublicRepos to be false, got %v", freeForPublicRepos)
	}
}

func Test_Pricing_GetFriendlyName(t *testing.T) {
	testPricing := &Pricing{
		Price:              100,
		Product:            "actions",
		Sku:                "actions_linux",
		MeterType:          PricingMeterDefault,
		FriendlyName:       "Actions Linux",
		AzureMeterId:       "123",
		FreeForPublicRepos: false,
		EffectiveAt:        time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
		UnitType:           UnitTypeMinutes,
	}
	friendlyName := testPricing.GetFriendlyName()
	if friendlyName != testPricing.FriendlyName {
		t.Errorf("expected friendly name to be %s, got %s", testPricing.FriendlyName, friendlyName)
	}
	testPricing = nil
	friendlyName = testPricing.GetFriendlyName()
	if friendlyName != "" {
		t.Errorf("expected friendly name to be empty, got %s", friendlyName)
	}
}

func Test_IsLicensedSkuWithDailyEmission(t *testing.T) {
	tests := []struct {
		name     string
		pricing  *Pricing
		expected bool
	}{
		{
			name: "licensed SKU with daily emissions",
			pricing: &Pricing{
				Price:              int64(1000 * 1.9),
				Sku:                "copilot_enterprise",
				FriendlyName:       "Copilot Enterprise",
				Product:            "copilot",
				AzureMeterId:       "copilot-meter-id",
				MeterType:          PricingMeterDefault,
				FreeForPublicRepos: false,
				UnitType:           UnitTypeUserMonths,
			},
			expected: true,
		},
		{
			name: "Deprecated licensed sku without daily emissions",
			pricing: &Pricing{
				Sku:                "ghec_seats",
				FriendlyName:       "GitHub Enterprise Cloud seats",
				Product:            "ghec",
				MeterType:          PricingMeterDefault,
				FreeForPublicRepos: false,
				UnitType:           UnitTypeUserMonths,
			},
			expected: false,
		},
		{
			name: "Current non licensed sku (actions_linux)",
			pricing: &Pricing{
				Sku:                "actions_linux",
				FriendlyName:       "Actions Linux",
				Product:            "actions",
				MeterType:          PricingMeterDefault,
				FreeForPublicRepos: true,
				UnitType:           UnitTypeMinutes,
			},
			expected: false,
		},
		{
			name: "Unknown unit type",
			pricing: &Pricing{
				Price:              int64(1000 * 0.1),
				Sku:                "test_sku",
				FriendlyName:       "Test SKU",
				Product:            "test",
				AzureMeterId:       "test-meter-id",
				MeterType:          PricingMeterDefault,
				FreeForPublicRepos: false,
				UnitType:           UnitTypeUnknown,
			},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			actual := tt.pricing.IsLicensedSkuWithDailyEmission()
			assert.Equal(t, tt.expected, actual)
		})
	}
}
