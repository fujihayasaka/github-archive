package models

import (
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
)

type GenericAmount[T any] struct {
	BilledAmount           T
	FullQuantity           T // Quantity provided by emitter, prior to proration and adjustments. Used by high watermark
	Quantity               T // Quantity after proration and adjustments. Used for billing.
	AppliedCostPerQuantity T
	FractionalQuantity     T // Fractional quantity for partial units. Used by watermark
}

type Amounts GenericAmount[int64]
type DecimalAmounts GenericAmount[float64]

type AmountsItem struct {
	*Key
	*Amounts
}

func NewAmountAsWholeNumbers(billedAmount, quantity float64) *Amounts {
	return &Amounts{
		BilledAmount: ToWholeAmount[int64](billedAmount),
		Quantity:     ToWholeAmount[int64](quantity),
		FullQuantity: ToWholeAmount[int64](quantity),
	}
}

func (amount *Amounts) ToDecimal() DecimalAmounts {
	return DecimalAmounts{
		BilledAmount:           ToDecimalAmount(amount.BilledAmount),
		Quantity:               ToDecimalAmount(amount.Quantity),
		FullQuantity:           ToDecimalAmount(amount.FullQuantity),
		AppliedCostPerQuantity: ToDecimalAmount(amount.AppliedCostPerQuantity),
	}
}

func (amount *DecimalAmounts) ToWholeAmount() Amounts {
	return Amounts{
		BilledAmount:           ToWholeAmount[int64](amount.BilledAmount),
		Quantity:               ToWholeAmount[int64](amount.Quantity),
		AppliedCostPerQuantity: ToWholeAmount[int64](amount.AppliedCostPerQuantity),
	}
}

// func (amounts *Amounts) Copy(withAppliedCostPerQuantity bool) *Amounts {
// 	var appliedCostPerQuantity int64
// 	if withAppliedCostPerQuantity {
// 		appliedCostPerQuantity = amounts.AppliedCostPerQuantity
// 	}

// 	return &Amounts{
// 		BilledAmount:           amounts.BilledAmount,
// 		Quantity:               amounts.Quantity,
// 		AppliedCostPerQuantity: appliedCostPerQuantity,
// 	}
// }

// This function will mutate the original amounts object
// subtracting the overage amounts from the original amounts
func (amounts *Amounts) RemoveOverages(overageAmount *Amounts) {
	if overageAmount == nil {
		return
	}

	updatedAmounts := amounts.Minus(overageAmount)
	updatedAmounts.EnsureNonNegative()

	amounts.BilledAmount = updatedAmounts.BilledAmount
	amounts.Quantity = updatedAmounts.Quantity
}

func (minuend Amounts) Minus(subtrahend *Amounts) *Amounts {
	if subtrahend == nil {
		return &minuend
	}

	return &Amounts{
		BilledAmount: minuend.BilledAmount - subtrahend.BilledAmount,
		Quantity:     minuend.Quantity - subtrahend.Quantity,
	}
}

func (amounts *Amounts) EnsureNonNegative() *Amounts {
	if amounts == nil {
		return nil
	}

	if amounts.BilledAmount < 0 || amounts.Quantity < 0 {
		amounts.BilledAmount = 0
		amounts.Quantity = 0
	}
	return amounts
}

func (a *AmountsItem) GetAmounts() *Amounts {
	return a.Amounts
}

func getAmountsPatchOperations(amounts *Amounts) azcosmos.PatchOperations {
	po := azcosmos.PatchOperations{}
	po.AppendIncrement("/BilledAmount", amounts.BilledAmount)
	po.AppendIncrement("/Quantity", amounts.Quantity)
	// +/- events are expected for delta quantities but we can skip the extra RUs for 0 values
	if amounts.FractionalQuantity != 0 {
		po.AppendIncrement("/FractionalQuantity", amounts.FractionalQuantity)
	}
	po.AppendIncrement("/FullQuantity", amounts.FullQuantity)

	return po
}

func (a *AmountsItem) GetPatchOperations() azcosmos.PatchOperations {
	amounts := a.GetAmounts()
	return getAmountsPatchOperations(amounts)
}

func (billingItem *Item) GetPatchOperations() azcosmos.PatchOperations {
	amounts := billingItem.GetAmounts()
	return getAmountsPatchOperations(amounts)
}
