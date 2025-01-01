package models

import (
	"testing"
	"time"

	"github.com/onsi/gomega"
)

func Test_AmountsAreCopiedByValue(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	quantity := 2.0
	nanoQuantity := int64(quantity * 1000000000)
	usageDate := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC) // first day of the month
	usageItem := newItem(ItemOptions{
		ID:           "billable",
		PartitionKey: "fooBar",
		UsageDate:    usageDate,
		Quantity:     quantity,
	})

	missingCustomerHourlyRollup := NewCustomerSkuHourlyRollup(usageItem)
	usageItem.Quantity = 0.0
	g.Expect(missingCustomerHourlyRollup.Quantity).To(gomega.Equal(nanoQuantity))
}

func Test_NewCustomerSkuHourlyRollup(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	quantity := 2.0
	nanoQuantity := int64(quantity * 1000000000)
	usageDate := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC) // first day of the month
	usageItem := newItem(ItemOptions{
		ID:           "billable",
		PartitionKey: "fooBar",
		Sku:          "bounce_a_lot_balloony_boots",
		CustomerID:   "1234567",
		UsageDate:    usageDate,
		Quantity:     quantity,
	})

	customerSkuHourlyRollup := NewCustomerSkuHourlyRollup(usageItem)
	g.Expect(customerSkuHourlyRollup.Id).To(gomega.Equal("fooBar"))
	g.Expect(customerSkuHourlyRollup.PartitionKey).To(gomega.Equal("1234567:bounce_a_lot_balloony_boots:2010:11:1:3"))
	g.Expect(customerSkuHourlyRollup.Quantity).To(gomega.Equal(nanoQuantity))
}

func Test_NewCustomerOrgRepoProductSkuHourlyRollup(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	quantity := 2.0
	nanoQuantity := int64(quantity * 1000000000)
	usageDate := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC) // first day of the month
	usageItem := newItem(ItemOptions{
		ID:           "billable",
		PartitionKey: "fooBar",
		CustomerID:   "1234567",
		UsageDate:    usageDate,
		Quantity:     quantity,
	})

	customerOrgRepoProductSkuHourlyRollup := NewCustomerOrgRepoProductSkuHourlyRollup(usageItem)
	g.Expect(customerOrgRepoProductSkuHourlyRollup.Id).To(gomega.Equal("fooBar"))
	g.Expect(customerOrgRepoProductSkuHourlyRollup.PartitionKey).To(gomega.Equal("1234567:2010:11:1:3:byOrgRepoProductSku"))
	g.Expect(customerOrgRepoProductSkuHourlyRollup.Quantity).To(gomega.Equal(nanoQuantity))
}

type ItemOptions struct {
	ID             string
	PartitionKey   string
	Sku            string
	Product        string
	CustomerID     string
	RepositoryID   int64
	OrganizationID int64
	UsageDate      time.Time
	Quantity       float64
}

func newItem(options ItemOptions) *Item {
	amounts := NewAmountAsWholeNumbers(0, options.Quantity)
	usageItem := &Item{
		Key: Key{
			Id:           options.ID,
			PartitionKey: options.PartitionKey,
		},
		Pricing: &Pricing{
			Sku:     options.Sku,
			Product: options.Product,
		},
		UsageAt: *NewUsageTimeFromTime(options.UsageDate),
		Amounts: amounts,
		EntityDetail: &EntityDetail{
			CustomerId: options.CustomerID,
			CostCenterDetail: &CostCenterDetail{
				EnterpriseCustomerId: options.CustomerID,
			},
			OrganizationId: options.OrganizationID,
			RepositoryId:   options.RepositoryID,
		},
	}
	return usageItem
}
