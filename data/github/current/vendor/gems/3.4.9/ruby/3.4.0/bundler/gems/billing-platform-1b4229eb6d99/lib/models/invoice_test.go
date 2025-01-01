package models

import (
	"fmt"
	"testing"
	"time"

	"github.com/github/billing-platform/testing/stubs"
	"github.com/onsi/gomega"
)

func Test_InvoiceToProto(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	customerId := stubs.GetRandomId64AsString()
	year := int64(2019)
	month := int64(3)

	invoice := NewInvoice(&InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     InvoiceMonthly,
		Year:       year,
		Month:      month,
	}, []*Item{}, []*DiscountItem{})

	proto := invoice.ToProto()
	g.Expect(proto).ShouldNot(gomega.BeNil())
	g.Expect(proto.CustomerId).Should(gomega.Equal(customerId))
	g.Expect(proto.Year).Should(gomega.Equal(year))
	g.Expect(proto.Month).Should(gomega.Equal(month))
	g.Expect(proto.UsageTotal).ShouldNot(gomega.BeNil())
	g.Expect(proto.UsageTotal.Gross).Should(gomega.Equal(float64(0)))
	g.Expect(proto.UsageTotal.Discount).Should(gomega.Equal(float64(0)))
	g.Expect(proto.UsageTotal.Net).Should(gomega.Equal(float64(0)))
	g.Expect(proto.UsageTotal.Quantity).Should(gomega.Equal(float64(0)))
	g.Expect(proto.ProductTotals).ShouldNot(gomega.BeNil())
	g.Expect(proto.ProductTotals).Should(gomega.HaveLen(0))
}

func Test_CreatesEmptyInvoiceWhenItemsAreNil(t *testing.T) {
	customerId := stubs.GetRandomId64AsString()
	year := int64(2019)
	month := int64(3)

	invoice := NewInvoice(&InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     InvoiceMonthly,
		Year:       year,
		Month:      month,
	}, nil, nil)
	if invoice == nil {
		t.Error("Expected invoice to be created")
	}
}

func Test_CreatesEmptyInvoiceWhenItemsAreEmpty(t *testing.T) {
	customerId := stubs.GetRandomId64AsString()
	year := int64(2019)
	month := int64(3)

	invoice := NewInvoice(&InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     InvoiceMonthly,
		Year:       year,
		Month:      month,
	}, []*Item{}, []*DiscountItem{})
	if invoice == nil {
		t.Error("Expected invoice to be created")
	}
}

func Test_PopulatesBasicFields(t *testing.T) {
	customerId := stubs.GetRandomId64AsString()
	year := int64(2019)
	month := int64(3)

	invoice := NewInvoice(&InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     InvoiceMonthly,
		Year:       year,
		Month:      month,
	}, []*Item{}, []*DiscountItem{})

	expectedInvoiceKey := fmt.Sprintf("customer:%s:invoices", customerId)
	if invoice.GetKey().PartitionKey != expectedInvoiceKey {
		t.Errorf("Expected key to be %s, got %s", expectedInvoiceKey, invoice.Key)
	}
	if invoice.CustomerId != customerId {
		t.Errorf("Expected customer id to be %s, got %s", customerId, invoice.CustomerId)
	}
	if invoice.Year != year {
		t.Errorf("Expected year to be %d, got %d", year, invoice.Year)
	}
	if invoice.Month != month {
		t.Errorf("Expected month to be %d, got %d", month, invoice.Month)
	}
	if invoice.Period != InvoiceMonthly {
		t.Errorf("Expected period to be %s, got %s", InvoiceMonthly, invoice.Period)
	}
	if invoice.State != Active {
		t.Errorf("Expected state to be %s, got %s", Active, invoice.State)
	}
}

func Test_A_SingleLineItemMapsProductAndSku(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	customerId := stubs.GetRandomId64AsString()
	year := int64(2019)
	month := int64(3)

	product := "product1"
	sku := "sku1"

	usageAt := int64(1234567890000)
	anItem := &Item{
		Pricing: &Pricing{
			Product:     product,
			Sku:         sku,
			EffectiveAt: time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
		},
		UsageAt: NewUsageTimeFromUnixMilli(usageAt),
		Amounts: &Amounts{
			Quantity:     NanoOne,
			BilledAmount: NanoTen,
		}}
	billingItems := []*Item{anItem}

	invoice := NewInvoice(&InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     InvoiceMonthly,
		Year:       year,
		Month:      month,
	}, billingItems, []*DiscountItem{})

	g.Expect(invoice.ProductTotals).Should(gomega.HaveKey(product))

	productTotal := invoice.ProductTotals[product]
	g.Expect(productTotal.SkuTotals).Should(gomega.HaveKey(sku))

	skuTotal := productTotal.SkuTotals[sku]
	g.Expect(skuTotal.Sku).Should(gomega.Equal(sku))
	g.Expect(&UsageTotal{
		Gross:    10,
		Discount: 0,
		Net:      10,
		Quantity: 1,
	}).Should(gomega.Equal(skuTotal.UsageTotal))
	g.Expect(anItem).Should(gomega.Equal(skuTotal.BillingItems[0]))
}

func Test_MultipleSkus_RollUp_UnderOneProduct(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	customerId := stubs.GetRandomId64AsString()
	year := int64(2019)
	month := int64(3)

	product := "product1"
	sku := "sku1"
	sku2 := "sku2"

	usageAt := int64(1234567890000)
	item1 := &Item{Pricing: &Pricing{
		Product: product,
		Sku:     sku,
	},
		UsageAt: NewUsageTimeFromUnixMilli(usageAt),
	}
	item2 := &Item{Pricing: &Pricing{
		Product: product,
		Sku:     sku2,
	},
		UsageAt: NewUsageTimeFromUnixMilli(usageAt),
	}

	invoice := NewInvoice(&InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     InvoiceMonthly,
		Year:       year,
		Month:      month,
	}, []*Item{item1, item2}, []*DiscountItem{})

	g.Expect(invoice.ProductTotals).Should(gomega.HaveKey(product))

	productTotal := invoice.ProductTotals[product]
	g.Expect(productTotal.SkuTotals).Should(gomega.HaveKey(sku))
	g.Expect(productTotal.SkuTotals).Should(gomega.HaveKey(sku2))

	skuTotal := productTotal.SkuTotals[sku]
	g.Expect(skuTotal.Sku).Should(gomega.Equal(sku))
	g.Expect(item1).Should(gomega.Equal(skuTotal.BillingItems[0]))

	skuTotal2 := productTotal.SkuTotals[sku2]
	g.Expect(skuTotal2.Sku).Should(gomega.Equal(sku2))
	g.Expect(item2).Should(gomega.Equal(skuTotal2.BillingItems[0]))
}

func Test_MultipleProducts_RollUp_ToMultipleProductTotals(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	customerId := stubs.GetRandomId64AsString()
	year := int64(2019)
	month := int64(3)

	product1 := "product1"
	product2 := "product2"
	sku := "sku1"
	sku2 := "sku2"

	usageAt := int64(1234567890000)
	item1 := &Item{Pricing: &Pricing{
		Product: product1,
		Sku:     sku,
	},
		UsageAt: NewUsageTimeFromUnixMilli(usageAt),
	}
	item2 := &Item{Pricing: &Pricing{
		Product: product2,
		Sku:     sku2,
	},
		UsageAt: NewUsageTimeFromUnixMilli(usageAt),
	}

	invoice := NewInvoice(&InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     InvoiceMonthly,
		Year:       year,
		Month:      month,
	}, []*Item{
		item1, item2}, []*DiscountItem{})

	g.Expect(invoice.ProductTotals).Should(gomega.HaveKey(product1))
	g.Expect(invoice.ProductTotals).Should(gomega.HaveKey(product2))

	productTotal1 := invoice.ProductTotals[product1]
	g.Expect(productTotal1.SkuTotals).Should(gomega.HaveKey(sku))

	productTotal2 := invoice.ProductTotals[product2]
	g.Expect(productTotal2.SkuTotals).Should(gomega.HaveKey(sku2))

	skuTotal := productTotal1.SkuTotals[sku]
	g.Expect(skuTotal.Sku).Should(gomega.Equal(sku))
	g.Expect([]*Item{item1}).Should(gomega.Equal(skuTotal.BillingItems))

	skuTotal2 := productTotal2.SkuTotals[sku2]
	g.Expect(skuTotal2.Sku).Should(gomega.Equal(sku2))
	g.Expect([]*Item{item2}).Should(gomega.Equal(skuTotal2.BillingItems))
}

func Test_A_SingleLineAmountRollsUpToProductAndInvoiceTotals(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	customerId := stubs.GetRandomId64AsString()
	year := int64(2019)
	month := int64(3)

	product := "product1"
	sku := "sku1"

	invoice := NewInvoice(&InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     InvoiceMonthly,
		Year:       year,
		Month:      month,
	}, []*Item{
		{
			Pricing: &Pricing{
				Product:     product,
				Sku:         sku,
				EffectiveAt: time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
			},
			Amounts: &Amounts{
				Quantity:     NanoOne,
				BilledAmount: NanoTen,
			},
		},
	}, []*DiscountItem{})

	usageTotal := &UsageTotal{
		Gross:    10,
		Discount: 0,
		Net:      10,
		Quantity: 1,
	}

	g.Expect(invoice.ProductTotals).Should(gomega.HaveKey(product))
	productTotal := invoice.ProductTotals[product]
	g.Expect(productTotal.SkuTotals).Should(gomega.HaveKey(sku))
	skuTotal := productTotal.SkuTotals[sku]

	g.Expect(skuTotal.Sku).Should(gomega.Equal(sku))
	g.Expect(usageTotal).Should(gomega.Equal(productTotal.UsageTotal))
	g.Expect(usageTotal).Should(gomega.Equal(invoice.UsageTotal))
}

func Test_TwoSkuRecordsUpdateProductUsagetotals(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	customerId := stubs.GetRandomId64AsString()
	year := int64(2019)
	month := int64(3)

	product := "product1"
	product2 := "product2"
	sku := "sku1"
	sku2 := "sku2"

	invoice := NewInvoice(&InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     InvoiceMonthly,
		Year:       year,
		Month:      month,
	}, []*Item{
		{
			Pricing: &Pricing{
				Product:     product,
				Sku:         sku,
				EffectiveAt: time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
			},
			Amounts: &Amounts{
				Quantity:     NanoOne,
				BilledAmount: NanoTen,
			},
		},
		{
			Pricing: &Pricing{
				Product:     product2,
				Sku:         sku2,
				EffectiveAt: time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
			},
			Amounts: &Amounts{
				Quantity:     NanoOne,
				BilledAmount: NanoTen,
			},
		},
	}, []*DiscountItem{})

	usageTotal := &UsageTotal{
		Gross:    10,
		Discount: 0,
		Net:      10,
		Quantity: 1,
	}

	g.Expect(invoice.ProductTotals).Should(gomega.HaveKey(product))
	g.Expect(invoice.ProductTotals).Should(gomega.HaveKey(product2))
	productTotal := invoice.ProductTotals[product]
	productTotal2 := invoice.ProductTotals[product2]

	g.Expect(usageTotal).Should(gomega.Equal(productTotal.UsageTotal))
	g.Expect(usageTotal).Should(gomega.Equal(productTotal2.UsageTotal))
	g.Expect(&UsageTotal{
		Gross:    20,
		Discount: 0,
		Net:      20,
		Quantity: 2,
	}).Should(gomega.Equal(invoice.UsageTotal))
}

func Test_DiscountIsCorrectlyCalculated(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	customerId := stubs.GetRandomId64AsString()
	year := int64(2019)
	month := int64(3)

	product := "product1"
	sku := "sku1"

	invoice := NewInvoice(&InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     InvoiceMonthly,
		Year:       year,
		Month:      month,
	}, []*Item{
		{
			Pricing: &Pricing{
				Product:     product,
				Sku:         sku,
				EffectiveAt: time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
			},
			Amounts: &Amounts{
				Quantity:     ToWholeAmount[int64](0.00103),
				BilledAmount: ToWholeAmount[int64](0.002537218),
			},
		},
		{
			Pricing: &Pricing{
				Product:     product,
				Sku:         sku,
				EffectiveAt: time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
			},
			Amounts: &Amounts{
				Quantity:     ToWholeAmount[int64](0.00103),
				BilledAmount: ToWholeAmount[int64](0.045310299),
			},
		},
		{
			Pricing: &Pricing{
				Product:     product,
				Sku:         sku,
				EffectiveAt: time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
			},
			Amounts: &Amounts{
				Quantity:     ToWholeAmount[int64](0.00103),
				BilledAmount: ToWholeAmount[int64](0.249423513),
			},
		},
	}, []*DiscountItem{
		{
			DiscountAmount: ToWholeAmount[int64](0.002537218),
			Pricing: &Pricing{
				Product:     product,
				Sku:         sku,
				EffectiveAt: time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
			},
			Quantity: ToWholeAmount[int64](0.00103),
		},
		{
			DiscountAmount: ToWholeAmount[int64](0.045310299),
			Pricing: &Pricing{
				Product:     product,
				Sku:         sku,
				EffectiveAt: time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
			},
			Quantity: ToWholeAmount[int64](0.00103),
		},
		{
			DiscountAmount: ToWholeAmount[int64](0.249423513),
			Pricing: &Pricing{
				Product:     product,
				Sku:         sku,
				EffectiveAt: time.Date(2023, 6, 30, 0, 0, 0, 0, time.UTC).Unix(),
			},
			Quantity: ToWholeAmount[int64](0.00103),
		},
	})

	usageTotal := &UsageTotal{
		Gross:    0.29727103,
		Discount: 0.29727103,
		Net:      0,
		Quantity: 0.00309,
	}

	g.Expect(invoice.ProductTotals).Should(gomega.HaveKey(product))
	productTotal := invoice.ProductTotals[product]

	g.Expect(productTotal.SkuTotals).Should(gomega.HaveKey(sku))
	skuTotal := productTotal.SkuTotals[sku]

	g.Expect(usageTotal).Should(gomega.Equal(skuTotal.UsageTotal))
	g.Expect(usageTotal).Should(gomega.Equal(productTotal.UsageTotal))
	g.Expect(usageTotal).Should(gomega.Equal(invoice.UsageTotal))
}

func Test_ActiveInvoiceItemsAreGeneratedCorrectly(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	keyMonthly := &Key{
		PartitionKey: "customer:123:invoices",
		Id:           "customer:123:invoices:2019:3",
	}
	keyDaily := &Key{
		PartitionKey: "customer:123:invoices",
		Id:           "customer:123:invoices:2019:3:15",
	}
	ipdMonthly, err := InvoicePartitionDetailFromInvoiceKey(keyMonthly)
	g.Expect(err).Should(gomega.BeNil())

	ipdDaily, err := InvoicePartitionDetailFromInvoiceKey(keyDaily)
	g.Expect(err).Should(gomega.BeNil())

	processedAt := time.Now()
	monthlyItem := NewActiveInvoiceItem(ipdMonthly, &processedAt)
	dailyItem := NewActiveInvoiceItem(ipdDaily, &processedAt)

	g.Expect(monthlyItem.PartitionKey).Should(gomega.Equal("invoices:active:2019:3"))
	g.Expect(monthlyItem.Id).Should(gomega.Equal("customer:123:invoices:2019:3"))
	g.Expect(monthlyItem.ProcessedAt).Should(gomega.Equal(&processedAt))

	g.Expect(dailyItem.PartitionKey).Should(gomega.Equal("invoices:active:2019:3:15"))
	g.Expect(dailyItem.Id).Should(gomega.Equal("customer:123:invoices:2019:3:15"))
	g.Expect(dailyItem.ProcessedAt).Should(gomega.Equal(&processedAt))
}

func Test_SubmittedInvoiceItemsAreGeneratedCorrectly(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	keyMonthly := &Key{
		PartitionKey: "customer:123:invoices",
		Id:           "customer:123:invoices:2019:3",
	}
	keyDaily := &Key{
		PartitionKey: "customer:123:invoices",
		Id:           "customer:123:invoices:2019:3:15",
	}
	ipdMonthly, err := InvoicePartitionDetailFromInvoiceKey(keyMonthly)
	g.Expect(err).Should(gomega.BeNil())

	ipdDaily, err := InvoicePartitionDetailFromInvoiceKey(keyDaily)
	g.Expect(err).Should(gomega.BeNil())

	submittedAt := time.Now()
	monthlyItem := NewSubmittedInvoiceItem(ipdMonthly, &submittedAt)
	dailyItem := NewSubmittedInvoiceItem(ipdDaily, &submittedAt)

	g.Expect(monthlyItem.PartitionKey).Should(gomega.Equal("invoices:submitted:2019:3"))
	g.Expect(monthlyItem.Id).Should(gomega.Equal("customer:123:invoices:2019:3"))
	g.Expect(monthlyItem.SubmittedAt).Should(gomega.Equal(&submittedAt))

	g.Expect(dailyItem.PartitionKey).Should(gomega.Equal("invoices:submitted:2019:3:15"))
	g.Expect(dailyItem.Id).Should(gomega.Equal("customer:123:invoices:2019:3:15"))
	g.Expect(dailyItem.SubmittedAt).Should(gomega.Equal(&submittedAt))
}

func Test_ConfirmedInvoiceItemsAreGeneratedCorrectly(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	keyMonthly := &Key{
		PartitionKey: "customer:123:invoices",
		Id:           "customer:123:invoices:2019:3",
	}
	keyDaily := &Key{
		PartitionKey: "customer:123:invoices",
		Id:           "customer:123:invoices:2019:3:15",
	}
	ipdMonthly, err := InvoicePartitionDetailFromInvoiceKey(keyMonthly)
	g.Expect(err).Should(gomega.BeNil())

	ipdDaily, err := InvoicePartitionDetailFromInvoiceKey(keyDaily)
	g.Expect(err).Should(gomega.BeNil())

	confirmedAt := time.Now()
	monthlyItem := NewConfirmedInvoiceItem(ipdMonthly, &confirmedAt)
	dailyItem := NewConfirmedInvoiceItem(ipdDaily, &confirmedAt)

	g.Expect(monthlyItem.PartitionKey).Should(gomega.Equal("invoices:confirmed:2019:3"))
	g.Expect(monthlyItem.Id).Should(gomega.Equal("customer:123:invoices:2019:3"))
	g.Expect(monthlyItem.ConfirmedAt).Should(gomega.Equal(&confirmedAt))

	g.Expect(dailyItem.PartitionKey).Should(gomega.Equal("invoices:confirmed:2019:3:15"))
	g.Expect(dailyItem.Id).Should(gomega.Equal("customer:123:invoices:2019:3:15"))
	g.Expect(dailyItem.ConfirmedAt).Should(gomega.Equal(&confirmedAt))
}

func Test_RejectedInvoiceItemsAreGeneratedCorrectly(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	keyMonthly := &Key{
		PartitionKey: "customer:123:invoices",
		Id:           "customer:123:invoices:2019:3",
	}
	keyDaily := &Key{
		PartitionKey: "customer:123:invoices",
		Id:           "customer:123:invoices:2019:3:15",
	}
	ipdMonthly, err := InvoicePartitionDetailFromInvoiceKey(keyMonthly)
	g.Expect(err).Should(gomega.BeNil())

	ipdDaily, err := InvoicePartitionDetailFromInvoiceKey(keyDaily)
	g.Expect(err).Should(gomega.BeNil())

	RejectedAt := time.Now()
	monthlyItem := NewRejectedInvoiceItem(ipdMonthly, "555", "Something went wrong", &RejectedAt)
	dailyItem := NewRejectedInvoiceItem(ipdDaily, "555", "Something went wrong", &RejectedAt)

	g.Expect(monthlyItem.PartitionKey).Should(gomega.Equal("invoices:rejected:2019:3"))
	g.Expect(monthlyItem.Id).Should(gomega.Equal("customer:123:invoices:2019:3"))

	g.Expect(monthlyItem.ErrorCode).Should(gomega.Equal("555"))
	g.Expect(monthlyItem.ErrorMessage).Should(gomega.Equal("Something went wrong"))
	g.Expect(monthlyItem.RejectedAt).Should(gomega.Equal(&RejectedAt))

	g.Expect(dailyItem.PartitionKey).Should(gomega.Equal("invoices:rejected:2019:3:15"))
	g.Expect(dailyItem.Id).Should(gomega.Equal("customer:123:invoices:2019:3:15"))
	g.Expect(dailyItem.RejectedAt).Should(gomega.Equal(&RejectedAt))
	g.Expect(dailyItem.ErrorCode).Should(gomega.Equal("555"))
	g.Expect(dailyItem.ErrorMessage).Should(gomega.Equal("Something went wrong"))
}
