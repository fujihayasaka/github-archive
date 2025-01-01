//go:build integration
// +build integration

package integrationtests_test

import (
	"context"
	"fmt"
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
)

func Test_Invoice_WhenRollupsAreRun_ActiveInvoiceItemIsRecorded(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing1 := client.EnsureSpecificPricingExists(0.5, "sku1", "product1", "SKU 1")
	pricing2 := client.EnsureSpecificPricingExists(1, "sku2", "product1", "SKU 2")
	pricing3 := client.EnsureSpecificPricingExists(2, "sku3", "product2", "SKU 3")
	pricing4 := client.EnsureSpecificPricingExists(3, "sku4", "product3", "SKU 4")
	pricing5 := client.EnsureSpecificPricingExists(4, "sku5", "product4", "SKU 5")
	pricing6 := client.EnsureSpecificPricingExists(5, "sku6", "product4", "SKU 6")

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"product1", "product2", "product3", "product4"}
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)

	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing2.Sku, 50))
	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing3.Sku, 50))
	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing6.Sku, 50))

	// create usage fo reach sku
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing2.Sku, 10, customerId, usageDate)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing3.Sku, 100, customerId, usageDate)
	usage4 := stubs.CreateUsage(uuid.NewString(), pricing4.Sku, 1000, customerId, usageDate)
	usage5 := stubs.CreateUsage(uuid.NewString(), pricing5.Sku, 10000, customerId, usageDate)
	usage6 := stubs.CreateUsage(uuid.NewString(), pricing6.Sku, 100000, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5, usage6}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	ipd := &models.InvoicePartitionDetail{
		CustomerId: customerId,
		Period:     models.InvoiceMonthly,
		Year:       int64(usageDate.Year()),
		Month:      int64(usageDate.Month()),
	}
	item, _ := db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(item).ShouldNot(gomega.BeNil(), "active invoice item should exist")
	g.Expect(item.PartitionKey).Should(gomega.Equal("invoices:active:2010:11"))
	g.Expect(item.Id).Should(gomega.Equal(fmt.Sprintf("customer:%s:invoices:2010:11", customerId)))
	g.Expect(item.ProcessedAt).Should(gomega.BeNil())
}

func Test_Invoice_Invoice_Is_Almagamated_From_UsageRollUps(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"product1", "product2", "product3", "product4"}
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)

	pricing1 := client.EnsureSpecificPricingExists(0.5, "sku1", "product1", "SKU 1")
	pricing2 := client.EnsureSpecificPricingExists(1, "sku2", "product1", "SKU 2")
	pricing3 := client.EnsureSpecificPricingExists(2, "sku3", "product2", "SKU 3")
	pricing4 := client.EnsureSpecificPricingExists(3, "sku4", "product3", "SKU 4")
	pricing5 := client.EnsureSpecificPricingExists(4, "sku5", "product4", "SKU 5")
	pricing6 := client.EnsureSpecificPricingExists(5, "sku6", "product4", "SKU 6")

	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing2.Sku, 100))
	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing3.Sku, 100))
	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing6.Sku, 100))

	// Create some usage
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing2.Sku, 10, customerId, usageDate)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing3.Sku, 100, customerId, usageDate)
	usage4 := stubs.CreateUsage(uuid.NewString(), pricing4.Sku, 1000, customerId, usageDate)
	usage5 := stubs.CreateUsage(uuid.NewString(), pricing5.Sku, 10000, customerId, usageDate)
	usage6 := stubs.CreateUsage(uuid.NewString(), pricing6.Sku, 100000, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5, usage6}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// Schedule invoice generation for the desired year and month
	// This puts a new request with an invoice partition detail into the request handler queue
	client.ScheduleInvoiceGeneration(2010, 11)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	// Run the request handler
	// This populates the Zuora emission queue with invoices matching the invoice partition detail
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	// Process the Zuora emission queue
	// This emits usage to Zuora
	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)

	response := client.GetInvoice(customerId, usageDate.Year(), int(usageDate.Month()))
	invoice := response.Invoice

	g.Expect(invoice).ShouldNot(gomega.BeNil())
	g.Expect(invoice.UsageTotal.Gross).Should(gomega.Equal(543210.5))
	// 100000 * 5 + 10000 * 4 + 1000 * 3 + 100 * 2 + 10 * 1 + 1 * 0.5 - without discounts applied
	g.Expect(invoice.UsageTotal.Gross).Should(gomega.Equal(543210.5))
	// 10000 * 4 + 1000 * 3 + 1 * 0.5 = 43 000.5 - with discounts applied
	g.Expect(invoice.UsageTotal.Net).Should(gomega.Equal(43000.5))
	g.Expect(invoice.UsageTotal.Discount).Should(gomega.Equal(543210.5 - 43000.5))
	// the usages for the days this month will now be one line item for each month
	g.Expect(invoice.UsageTotal.GetQuantity()).Should(gomega.Equal(100000 + 10000 + 1000 + 100 + 10 + 1.0))
	g.Expect(invoice.ProductTotals).Should(gomega.HaveLen(4))
}

func Test_Invoice_Invoice_Is_Generated_For_Offboarded_Customers_For_Period_Onboarded(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"product1", "product2"}
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)

	pricing1 := client.EnsureSpecificPricingExists(0.5, "sku1", "product1", "SKU 1")
	pricing2 := client.EnsureSpecificPricingExists(1, "sku2", "product1", "SKU 2")
	pricing3 := client.EnsureSpecificPricingExists(2, "sku3", "product2", "SKU 3")

	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing1.Sku, 100))

	// Create some usage
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing2.Sku, 10, customerId, usageDate)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing3.Sku, 100, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// Offboard the customer from product1
	customerProto.EnabledProducts = []string{}
	client.PatchCustomer(customerProto)

	// Create some usage
	usageDate2 := time.Date(2010, 11, 16, 3, 0, 0, 0, time.UTC)
	anotherUsage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate2)
	anotherUsage2 := stubs.CreateUsage(uuid.NewString(), pricing2.Sku, 10, customerId, usageDate2)
	anotherUsage3 := stubs.CreateUsage(uuid.NewString(), pricing3.Sku, 100, customerId, usageDate2)

	anotherUsages := []*hydroSchema.Usage{anotherUsage1, anotherUsage2, anotherUsage3}

	client.ProduceMeteredUsage(anotherUsages)
	client.RunUsageIngestion(len(anotherUsages))
	client.RunDailyJob(len(anotherUsages))
	client.RunMonthlyJob(len(anotherUsages))

	// Schedule invoice generation for the desired year and month
	// This puts a new request with an invoice partition detail into the request handler queue
	client.ScheduleInvoiceGeneration(2010, 11)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	// Run the request handler
	// This populates the Zuora emission queue with invoices matching the invoice partition detail
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	// Process the Zuora emission queue
	// This emits usage to Zuora
	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)

	response := client.GetInvoice(customerId, usageDate.Year(), int(usageDate.Month()))
	invoice := response.Invoice

	// The invoice should only contain the usage from the first day
	// The customer was onboarded to product1 and product2 before the first ingestion
	// And offboarded before the second ingestion
	// The usage from the second day should be ignored
	g.Expect(invoice).ShouldNot(gomega.BeNil())
	// 100 * 2 + 10 * 1 + 1 * 0.5 - without discounts applied
	g.Expect(invoice.UsageTotal.Gross).Should(gomega.Equal(210.5))
	// 100 * 2 + 10 * 1 - with discounts applied
	g.Expect(invoice.UsageTotal.Net).Should(gomega.Equal(210.0))
	g.Expect(invoice.UsageTotal.Discount).Should(gomega.Equal(210.5 - 210))
	// the usages for the days this month will now be one line item for each month
	g.Expect(invoice.UsageTotal.GetQuantity()).Should(gomega.Equal(100 + 10 + 1.0))
	g.Expect(invoice.ProductTotals).Should(gomega.HaveLen(2))
}

func Test_Invoice_Invoice_Rejects_Copilot_Line_Items_When_Product_Is_Disabled(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(19.0, "copilot_for_business", "copilot", proto.PricingMeterType_DailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	client.CreateCustomer(customerProto)

	quantity := 1.0
	usageDate := time.Date(2023, time.October, 1, 10, 30, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerID, usageDate)
	usages := []*hydroSchema.Usage{usage1}

	// Ingest usage and create rollups
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// Offboard customer from Copilot
	customerProto.EnabledProducts = []string{}
	_ = client.PatchCustomer(customerProto)

	// Schedule invoice generation for the desired year and month
	// This puts a new request with an invoice partition detail into the request handler queue
	client.ScheduleInvoiceGeneration(2023, 10)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	// Run the request handler
	// This populates the Zuora emission queue with invoices matching the invoice partition detail
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	// Process the Zuora emission queue
	// This emits usage to Zuora
	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)

	response := client.GetInvoice(customerID, usageDate.Year(), int(usageDate.Month()))
	invoice := response.Invoice

	g.Expect(invoice).ShouldNot(gomega.BeNil())
	g.Expect(invoice.UsageTotal.GetQuantity()).Should(gomega.Equal(0.0))
	g.Expect(invoice.ProductTotals).Should(gomega.HaveLen(0))
}

func Test_Invoice_Invoice_Is_Almagamated_From_UsageRollUps_With_Complex_Discount(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"product1", "product2", "product3", "product4"}
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)

	pricing1 := client.EnsureSpecificPricingExists(0.5, "sku1", "product1", "")
	pricing2 := client.EnsureSpecificPricingExists(1, "sku2", "product1", "")
	pricing3 := client.EnsureSpecificPricingExists(2, "sku3", "product2", "")
	pricing4 := client.EnsureSpecificPricingExists(3, "sku4", "product3", "")
	pricing5 := client.EnsureSpecificPricingExists(4, "sku5", "product4", "")
	pricing6 := client.EnsureSpecificPricingExists(5, "sku6", "product4", "")

	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing2.Sku, 75))
	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing3.Sku, 85))
	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing6.Sku, 25))

	// create usage fo reach sku
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing2.Sku, 10, customerId, usageDate)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing3.Sku, 100, customerId, usageDate)
	usage4 := stubs.CreateUsage(uuid.NewString(), pricing4.Sku, 1000, customerId, usageDate)
	usage5 := stubs.CreateUsage(uuid.NewString(), pricing5.Sku, 10000, customerId, usageDate)
	usage6 := stubs.CreateUsage(uuid.NewString(), pricing6.Sku, 100000, customerId, usageDate) //

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5, usage6}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// Schedule invoice generation for the desired year and month
	// This puts a new request with an invoice partition detail into the request handler queue
	client.ScheduleInvoiceGeneration(2010, 11)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	// Run the request handler
	// This populates the Zuora emission queue with invoices matching the invoice partition detail
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	// Process the Zuora emission queue
	// This emits usage to Zuora
	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)

	response := client.GetInvoice(customerId, usageDate.Year(), int(usageDate.Month()))
	invoice := response.Invoice

	g.Expect(invoice).ShouldNot(gomega.BeNil())
	g.Expect(invoice.UsageTotal.Gross).Should(gomega.Equal(543210.5))
	g.Expect(invoice.UsageTotal.Net).Should(gomega.Equal(418033.0)) // 43000.5
	g.Expect(invoice.UsageTotal.Discount).Should(gomega.Equal(543210.5 - 418033.0))
	// the usages for the days this month will now be one line item for each month
	g.Expect(invoice.ProductTotals).Should(gomega.HaveLen(4))
}

func Test_Invoice_Invoice_Is_Almagamated_From_UsageRollUps_At_Full_Discount(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"product1", "product2", "product3", "product4"}
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)

	pricing1 := client.EnsureSpecificPricingExists(0.5, "sku1", "product1", "")
	pricing2 := client.EnsureSpecificPricingExists(1, "sku2", "product1", "")
	pricing3 := client.EnsureSpecificPricingExists(2, "sku3", "product2", "")
	pricing4 := client.EnsureSpecificPricingExists(3, "sku4", "product3", "")
	pricing5 := client.EnsureSpecificPricingExists(4, "sku5", "product4", "")
	pricing6 := client.EnsureSpecificPricingExists(5, "sku6", "product4", "")

	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing2.Sku, 100))
	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing3.Sku, 100))
	_, _ = client.CreateDiscount(stubs.CreatePercentageDiscountForSku(customerId, pricing6.Sku, 100))

	// create usage fo reach sku
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing2.Sku, 10, customerId, usageDate)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing3.Sku, 100, customerId, usageDate)
	usage4 := stubs.CreateUsage(uuid.NewString(), pricing4.Sku, 1000, customerId, usageDate)
	usage5 := stubs.CreateUsage(uuid.NewString(), pricing5.Sku, 10000, customerId, usageDate)
	usage6 := stubs.CreateUsage(uuid.NewString(), pricing6.Sku, 100000, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5, usage6}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// Schedule invoice generation for the desired year and month
	// This puts a new request with an invoice partition detail into the request handler queue
	client.ScheduleInvoiceGeneration(2010, 11)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	// Run the request handler
	// This populates the Zuora emission queue with invoices matching the invoice partition detail
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	// Process the Zuora emission queue
	// This emits usage to Zuora
	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)

	response := client.GetInvoice(customerId, usageDate.Year(), int(usageDate.Month()))
	invoice := response.Invoice

	g.Expect(invoice).ShouldNot(gomega.BeNil())
	// 100000 * 5 + 10000 * 4 + 1000 * 3 + 100 * 2 + 10 * 1 + 1 * 0.5 - without discounts applied
	g.Expect(invoice.UsageTotal.Gross).Should(gomega.Equal(543210.5))
	// 10000 * 4 + 1000 * 3 + 1 * 0.5 = 43 000.5 - with discounts applied
	g.Expect(invoice.UsageTotal.Net).Should(gomega.Equal(43000.5))
	g.Expect(invoice.UsageTotal.Discount).Should(gomega.Equal(543210.5 - 43000.5))
	// the usages for the days this month will now be one line item for each month
	g.Expect(invoice.UsageTotal.GetQuantity()).Should(gomega.Equal(100000 + 10000 + 1000 + 100 + 10 + 1.0))
	g.Expect(invoice.ProductTotals).Should(gomega.HaveLen(4))
}
