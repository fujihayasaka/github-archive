package models

type GenericDiscountAmount[T any] struct {
	DiscountAmount         T
	Quantity               T
	AppliedCostPerQuantity T
}

type DiscountAmounts GenericDiscountAmount[int64]
type DecimalDiscountAmounts GenericDiscountAmount[float64]

func NewDiscountAmountAsWholeNumbers(discountAmount, quantity float64) *DiscountAmounts {
	return &DiscountAmounts{
		DiscountAmount: ToWholeAmount[int64](discountAmount),
		Quantity:       ToWholeAmount[int64](quantity),
	}
}

func (amount *DiscountAmounts) ToDecimal() DecimalDiscountAmounts {
	return DecimalDiscountAmounts{
		DiscountAmount:         ToDecimalAmount(amount.DiscountAmount),
		Quantity:               ToDecimalAmount(amount.Quantity),
		AppliedCostPerQuantity: ToDecimalAmount(amount.AppliedCostPerQuantity),
	}
}

func (amount *DecimalDiscountAmounts) ToWholeAmount() DiscountAmounts {
	return DiscountAmounts{
		DiscountAmount:         ToWholeAmount[int64](amount.DiscountAmount),
		Quantity:               ToWholeAmount[int64](amount.Quantity),
		AppliedCostPerQuantity: ToWholeAmount[int64](amount.AppliedCostPerQuantity),
	}
}
