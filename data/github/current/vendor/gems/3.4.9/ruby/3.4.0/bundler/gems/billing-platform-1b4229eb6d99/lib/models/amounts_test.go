package models

import (
	"testing"

	"github.com/onsi/gomega"
)

func Test_NewAmountAsWholeNumbers(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	amounts := NewAmountAsWholeNumbers(10, 100)

	g.Expect(amounts.BilledAmount).To(gomega.Equal(int64(10000000000)))  // 10 * 10^9
	g.Expect(amounts.Quantity).To(gomega.Equal(int64(100000000000)))     // 100 * 10^9
	g.Expect(amounts.FullQuantity).To(gomega.Equal(int64(100000000000))) // 100 * 10^9
}

func Test_RemoveOverages(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	amounts := NewAmountAsWholeNumbers(100, 10)
	overageAmounts := NewAmountAsWholeNumbers(10, 1)

	amounts.RemoveOverages(overageAmounts)

	g.Expect(amounts.BilledAmount).To(gomega.Equal(ToWholeAmount[int64](90)))
	g.Expect(amounts.Quantity).To(gomega.Equal(ToWholeAmount[int64](9)))
	g.Expect(amounts.FullQuantity).To(gomega.Equal(ToWholeAmount[int64](10)))
}

func Test_RemoveOverages_WithOveragesGreaterThanUsageAmount_ReturnsZeroAmount(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	amounts := NewAmountAsWholeNumbers(100, 10)
	overageAmounts := NewAmountAsWholeNumbers(110, 11)

	amounts.RemoveOverages(overageAmounts)

	g.Expect(amounts.BilledAmount).To(gomega.Equal(ToWholeAmount[int64](0)))
	g.Expect(amounts.Quantity).To(gomega.Equal(ToWholeAmount[int64](0)))
	g.Expect(amounts.FullQuantity).To(gomega.Equal(ToWholeAmount[int64](10)))
}

func Test_RemoveOverages_WithNilOverages_ReturnsUsageAmount(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	amounts := NewAmountAsWholeNumbers(100, 10)
	var overageAmounts *Amounts

	amounts.RemoveOverages(overageAmounts)

	g.Expect(amounts.BilledAmount).To(gomega.Equal(ToWholeAmount[int64](100)))
	g.Expect(amounts.Quantity).To(gomega.Equal(ToWholeAmount[int64](10)))
	g.Expect(amounts.FullQuantity).To(gomega.Equal(ToWholeAmount[int64](10)))
}

func Test_Minus_ReturnsNewAmountsWithDifference(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	minuend := NewAmountAsWholeNumbers(100, 10)
	subtrahend := NewAmountAsWholeNumbers(10, 1)

	result := minuend.Minus(subtrahend)

	g.Expect(result.BilledAmount).To(gomega.Equal(ToWholeAmount[int64](90)))
	g.Expect(result.Quantity).To(gomega.Equal(ToWholeAmount[int64](9)))

	// Original amount is not mutated
	g.Expect(minuend.BilledAmount).To(gomega.Equal(ToWholeAmount[int64](100)))
	g.Expect(minuend.Quantity).To(gomega.Equal(ToWholeAmount[int64](10)))
}

func Test_Minus_WithNilSubtrahend_ReturnsOriginalAmount(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	minuend := NewAmountAsWholeNumbers(100, 10)
	var subtrahend *Amounts

	result := minuend.Minus(subtrahend)

	g.Expect(result.BilledAmount).To(gomega.Equal(ToWholeAmount[int64](100)))
	g.Expect(result.Quantity).To(gomega.Equal(ToWholeAmount[int64](10)))
}

func Test_Minus_WithGreaterSubtrahend_ReturnsNegativeAmount(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	minuend := NewAmountAsWholeNumbers(10, 1)
	subtrahend := NewAmountAsWholeNumbers(100, 10)

	result := minuend.Minus(subtrahend)

	g.Expect(result.BilledAmount).To(gomega.Equal(ToWholeAmount[int64](-90)))
	g.Expect(result.Quantity).To(gomega.Equal(ToWholeAmount[int64](-9)))
}

func Test_EnsureNonNegative_WithNegativeAmounts_ReturnsZeroAmounts(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	amounts := NewAmountAsWholeNumbers(-10, -1)

	amounts.EnsureNonNegative()

	g.Expect(amounts.BilledAmount).To(gomega.Equal(ToWholeAmount[int64](0)))
	g.Expect(amounts.Quantity).To(gomega.Equal(ToWholeAmount[int64](0)))
}

func Test_EnsureNonNegative_WithNilAmounts_ReturnsNil(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	var amounts *Amounts

	result := amounts.EnsureNonNegative()

	g.Expect(result).To(gomega.BeNil())
}

func Test_EnsureNonNegative_WithPositiveAmounts_ReturnsOriginalAmounts(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	amounts := NewAmountAsWholeNumbers(10, 1)

	amounts.EnsureNonNegative()

	g.Expect(amounts.BilledAmount).To(gomega.Equal(ToWholeAmount[int64](10)))
	g.Expect(amounts.Quantity).To(gomega.Equal(ToWholeAmount[int64](1)))
}
