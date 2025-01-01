package models

import (
	"testing"

	"github.com/github/billing-platform/testing/stubs"
	"github.com/onsi/gomega"
)

func Test_EmissionToProto(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	customerId := stubs.GetRandomId64AsString()
	year := int64(2019)
	month := int64(3)
	day := int64(1)

	emission := NewEmission(&EmissionPartitionDetail{
		CustomerId: customerId,
		Year:       year,
		Month:      month,
		Day:        day,
	}, []*Item{}, []*DiscountItem{}, nil)

	proto := emission.ToProto(&EmissionPartitionDetail{
		CustomerId: customerId,
		Year:       year,
		Month:      month,
		Day:        day,
	})
	g.Expect(proto).ShouldNot(gomega.BeNil())
	g.Expect(proto.CustomerId).Should(gomega.Equal(customerId))
	g.Expect(proto.Year).Should(gomega.Equal(year))
	g.Expect(proto.Month).Should(gomega.Equal(month))
	g.Expect(proto.Day).Should(gomega.Equal(day))
	g.Expect(proto.UsageTotal).ShouldNot(gomega.BeNil())
	g.Expect(proto.UsageTotal.Gross).Should(gomega.Equal(float64(0)))
	g.Expect(proto.UsageTotal.Discount).Should(gomega.Equal(float64(0)))
	g.Expect(proto.UsageTotal.Net).Should(gomega.Equal(float64(0)))
	g.Expect(proto.UsageTotal.Quantity).Should(gomega.Equal(float64(0)))
	g.Expect(proto.ProductTotals).ShouldNot(gomega.BeNil())
	g.Expect(proto.ProductTotals).Should(gomega.HaveLen(0))
}
