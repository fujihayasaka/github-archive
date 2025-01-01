package models

import (
	"testing"
	"time"

	"github.com/github/billing-platform/lib/twirp/proto"

	"github.com/onsi/gomega"
	"github.com/stretchr/testify/assert"
)

func Test_IsValidFor(t *testing.T) {
	today := time.Now().UTC()
	lastYear := today.AddDate(-1, 0, 1)
	yesterday := today.AddDate(0, 0, -1)
	tomorrow := today.AddDate(0, 0, 1)

	tests := []struct {
		name      string
		startDate time.Time
		endDate   time.Time
		isValid   bool
	}{
		{"valid date", yesterday, tomorrow, true},
		{"invalid date", tomorrow, yesterday, false},
		{"expired", lastYear, yesterday, false},
		{"valid till today", lastYear, today, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			discount := NewDiscount("123", []*proto.DiscountTarget{}, 100, 0, tt.startDate.Unix(), tt.endDate.Unix())
			isValid := discount.IsValidFor(NewUsageTimeFromTime(time.Now().UTC()))
			if isValid != tt.isValid {
				t.Errorf("expected IsValidFor to be %t, got %t", tt.isValid, isValid)
			}
		})
	}
}

func Test_CalculatePercentageDiscountAmount(t *testing.T) {

	// For discount we record the item as a unique item with postive price
	// a billing $20 item with 10% discount we would then store the discount for that item, ie $2
	// for something with $100 and 100% discount we would store $100 as the discount
	// in the invoice total we'll sum all the usage and then all the discount as two separate line items
	// then subtract the discount from the usage to get the total

	tests := []struct {
		name                        string
		discountPercent             float64
		billedAmount                int64
		quantity                    float64
		expectedDiscountAmountWhole int64
		expectedQuantityWhole       int64
	}{
		{"simpleDiscount", 10, 200000000000, 77, 20000000000, 7700000000},
		{"complexDiscount", 37.25, 100000000000, 77, 37250000000, 28682500000},
		{"100%Discount", 100, 200000000000, 77, 200000000000, 77000000000},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			targets := []*proto.DiscountTarget{
				{
					Id:   "actions_linux",
					Type: proto.DiscountTargetType_SkuDiscount,
				},
			}
			yesterday := time.Now().AddDate(0, 0, -1).Unix()
			nextYear := time.Now().AddDate(1, 0, 0).Unix()
			discount := NewDiscount("123", targets, tt.discountPercent, 0, yesterday, nextYear)

			discountAmount := discount.CalculatePercentageDiscountAmount(tt.billedAmount)

			if discountAmount != tt.expectedDiscountAmountWhole {
				t.Errorf("expected billed amount to be %d, got %d", tt.expectedDiscountAmountWhole, discountAmount)
			}
		})
	}
}

func Test_AsDiscountItemWithAmount(t *testing.T) {
	tests := []struct {
		name                     string
		quantity                 int64
		billedAmount             int64
		price                    int64
		amountAfterDiscounts     int64
		expectedDiscountAmount   int64
		expectedDiscountQuantity int64
	}{
		{"0%", 32000000, 256, 8000, 256, 0, 0},
		{"10%", 32000000, 256, 8000, 231, 25, 3125000},
		{"50%", 32000000, 256, 8000, 128, 128, 16000000},
		{"100%", 5550001084, 1864911, 336020, 0, 1864911, 5550001084},
		{"100%", 118000000000, 944000000, 8000000, 0, 944000000, 118000000000},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			item := &Item{
				Amounts: &Amounts{
					Quantity:               tt.quantity,
					BilledAmount:           tt.billedAmount,
					AppliedCostPerQuantity: tt.price,
				},
			}

			discountItem := item.AsDiscountItemWithAmount(tt.amountAfterDiscounts)
			if discountItem.Quantity != tt.expectedDiscountQuantity {
				t.Errorf("expected discount quantity to be %d, got %d", tt.expectedDiscountQuantity, discountItem.Quantity)
			}

			if discountItem.DiscountAmount != tt.expectedDiscountAmount {
				t.Errorf("expected discount amount to be %d, got %d", tt.expectedDiscountAmount, discountItem.DiscountAmount)
			}
		})
	}
}

func Test_AmountsWithDiscountApplied_WithNilDiscount_ReturnsUsageAmount(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	var discountItem *DiscountItem
	amounts := NewAmountAsWholeNumbers(10, 100)
	amountsWithDiscountApplied := amounts.AmountsWithDiscountApplied(discountItem)

	g.Expect(amountsWithDiscountApplied.BilledAmount).To(gomega.Equal(amounts.BilledAmount))
	g.Expect(amountsWithDiscountApplied.Quantity).To(gomega.Equal(amounts.Quantity))
	g.Expect(amountsWithDiscountApplied.FullQuantity).To(gomega.Equal(amounts.FullQuantity))
}

func Test_AmountsWithDiscountApplied_WithDiscount_ReturnsUpdatedAmount(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	discountItem := &DiscountItem{
		DiscountAmount: ToWholeAmount[int64](10),
		Quantity:       ToWholeAmount[int64](1),
	}
	amounts := NewAmountAsWholeNumbers(100, 10)
	amountsWithDiscountApplied := amounts.AmountsWithDiscountApplied(discountItem)

	g.Expect(amountsWithDiscountApplied.BilledAmount).To(gomega.Equal(ToWholeAmount[int64](90)))
	g.Expect(amountsWithDiscountApplied.Quantity).To(gomega.Equal(ToWholeAmount[int64](9)))
	g.Expect(amountsWithDiscountApplied.FullQuantity).To(gomega.Equal(amounts.FullQuantity))
}

func Test_AmountsWithDiscountsApplied_WithDiscountGreaterThanUsageAmount_ReturnsZeroAmount(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	discountItem := &DiscountItem{
		DiscountAmount: ToWholeAmount[int64](110),
		Quantity:       ToWholeAmount[int64](11),
	}
	amounts := NewAmountAsWholeNumbers(100, 10)
	amountsWithDiscountApplied := amounts.AmountsWithDiscountApplied(discountItem)

	g.Expect(amountsWithDiscountApplied.BilledAmount).To(gomega.Equal(ToWholeAmount[int64](0)))
	g.Expect(amountsWithDiscountApplied.Quantity).To(gomega.Equal(ToWholeAmount[int64](0)))
	g.Expect(amountsWithDiscountApplied.FullQuantity).To(gomega.Equal(amounts.FullQuantity))
}

func Test_DeepCopy(t *testing.T) {
	discountItem := &DiscountItem{
		DiscountAmount: ToWholeAmount[int64](10),
		Quantity:       ToWholeAmount[int64](1),
	}

	deepCopy, err := discountItem.DeepCopy()

	assert.NoError(t, err)
	assert.Equal(t, discountItem.DiscountAmount, deepCopy.DiscountAmount)
	assert.Equal(t, discountItem.Quantity, deepCopy.Quantity)

	// assert that we have different memory addresses
	assert.NotEqual(t, discountItem, deepCopy)
}
