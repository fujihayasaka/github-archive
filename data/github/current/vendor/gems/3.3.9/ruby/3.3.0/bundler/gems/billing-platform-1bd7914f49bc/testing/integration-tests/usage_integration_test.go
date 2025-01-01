//go:build integration
// +build integration

package integrationtests_test

import (
	"context"
	"fmt"
	"strconv"
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	a "github.com/github/billing-platform/testing/assertions"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/integration-tests/helpers"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
	"github.com/stretchr/testify/assert"
)

func Test_UsageIngestion_ProcessingUsageThatsAlreadyBeenProcessed(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"product1", "product2"}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	sku1 := "sku-1"
	_ = client.UpsertPricing(&proto.Pricing{
		Sku:         sku1,
		Product:     "product1",
		Price:       2.0,
		EffectiveAt: time.Date(2010, 11, 1, 0, 0, 0, 0, time.UTC).Unix(), // Effective before ingestion date
	})

	sku2 := "sku-2"
	_ = client.UpsertPricing(&proto.Pricing{
		Sku:         sku2,
		Product:     "product2",
		Price:       3.0,
		EffectiveAt: time.Date(2010, 11, 1, 0, 0, 0, 0, time.UTC).Unix(), // Effective before ingestion date
	})

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), sku1, 10, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), sku2, 10, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1, usage2}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))

	u := client.GetUsageTotal("", "", customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(20.0), "usage daily for usage date")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(50.0))
}

func Test_UsageIngestion_When_CustomerIsDisabled_RollupsAreSkipped(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	sku1 := "sku-1"
	_ = client.UpsertPricing(&proto.Pricing{
		Sku:         sku1,
		Product:     "the-product-name",
		Price:       2.0,
		EffectiveAt: time.Date(2010, 11, 1, 0, 0, 0, 0, time.UTC).Unix(), // Effective before ingestion date
	})

	sku2 := "sku-2"
	_ = client.UpsertPricing(&proto.Pricing{
		Sku:         sku2,
		Product:     "the-other-product-name",
		Price:       3.0,
		EffectiveAt: time.Date(2010, 11, 1, 0, 0, 0, 0, time.UTC).Unix(), // Effective before ingestion date
	})

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), sku1, 10, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), sku2, 10, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1, usage2}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	// after the hourly job, get usage from hourly bucket from final total
	u := client.GetUsageTotal("", "", customerId, usageDate, proto.BillingPeriod_Hourly)
	g.Expect(u.Quantity).Should(gomega.Equal(0.0), "usage quantity from hourly bucket")
	g.Expect(u.BillableAmount).Should(gomega.Equal(0.0), "usage billed amount from hourly bucket")

	client.RunDailyJob(len(usages))
	// after the daily job, get usage from daily bucket from final total
	u = client.GetUsageTotal("", "", customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(0.0), "usage from daily bucket")
	g.Expect(u.BillableAmount).Should(gomega.Equal(0.0), "usage billed amount from daily bucket")

	client.RunMonthlyJob(len(usages))
	// after the monthly job, get usage from monthly bucket from running total
	u = client.GetUsageTotal("", "", customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(0.0), "usage from monthly bucket")
	g.Expect(u.BillableAmount).Should(gomega.Equal(0.0), "usage billed amount from monthly bucket")

	client.RunYearlyJob(len(usages))
	// after the yearly job, get usage from monthly bucket from running total
	u = client.GetUsageTotal("", "", customerId, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(0.0), "usage from yearly bucket")
	g.Expect(u.BillableAmount).Should(gomega.Equal(0.0), "usage billed amount from yearly bucket")
}

func Test_UsageIngestion_When_SkuIsDisabled_RollupsAreSkipped(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	sku1 := "sku-1"
	_ = client.UpsertPricing(&proto.Pricing{
		Sku:         sku1,
		Product:     "the-product-name",
		Price:       2.0,
		EffectiveAt: time.Date(2010, 11, 30, 0, 0, 0, 0, time.UTC).Unix(), // Effective after ingestion date
	})

	sku2 := "sku-2"
	_ = client.UpsertPricing(&proto.Pricing{
		Sku:         sku2,
		Product:     "the-other-product-name",
		Price:       3.0,
		EffectiveAt: time.Date(2010, 11, 30, 0, 0, 0, 0, time.UTC).Unix(), // Effective after ingestion date
	})

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), sku1, 10, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), sku2, 10, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1, usage2}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	// after the hourly job, get usage from hourly bucket from final total
	u := client.GetUsageTotal("", "", customerId, usageDate, proto.BillingPeriod_Hourly)
	g.Expect(u.Quantity).Should(gomega.Equal(0.0), "usage quantity from hourly bucket")
	g.Expect(u.BillableAmount).Should(gomega.Equal(0.0), "usage billed amount from hourly bucket")

	client.RunDailyJob(len(usages))
	// after the daily job, get usage from daily bucket from final total
	u = client.GetUsageTotal("", "", customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(0.0), "usage from daily bucket")
	g.Expect(u.BillableAmount).Should(gomega.Equal(0.0), "usage billed amount from daily bucket")

	client.RunMonthlyJob(len(usages))
	// after the daily job, get usage from monthly bucket from running total
	u = client.GetUsageTotal("", "", customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(0.0), "usage from monthly bucket")
	g.Expect(u.BillableAmount).Should(gomega.Equal(0.0), "usage billed amount from monthly bucket")

	client.RunYearlyJob(len(usages))
	// after the yearly job, get usage from monthly bucket from running total
	u = client.GetUsageTotal("", "", customerId, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(0.0), "usage from yearly bucket")
	g.Expect(u.BillableAmount).Should(gomega.Equal(0.0), "usage billed amount from yearly bucket")
}

func Test_UsageIngestion_When_OnlyPartiaLDateIsSent_WeMaintain_the_Correct_one(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(0.08, "actions_linux", "actions", "Actions")

	// produce message and run ingestion
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 5, 4, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 1, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))
	// after the daily job, get usage from monthly bucket from running total
	u := client.GetUsageLineItemsDateParts("", pricing.GetSku(), customerId, proto.BillingPeriod_Monthly, 2023, 5, 0, 0, proto.UsageGroupBy_NoGroupBy)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "usage from monthly bucket from running total")
}

func Test_UsageIngestion_When_RollupsAreRun_ASingleUsage_Is_RecordedInAGivenHour(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(0.08, "actions_linux", "actions", "Actions")

	// produce message and run ingestion
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	var quantity float64 = 3.0
	var targetBilledAmount float64 = 0.24

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))
	// after the daily job, get usage from daily bucket from final total
	u := client.GetUsageTotal("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity), "usage from daily bucket from final total")
	g.Expect(u.BillableAmount).Should(gomega.Equal(targetBilledAmount), "usage billed amount from daily bucket from final total")

	client.RunMonthlyJob(len(usages))
	// after the daily job, get usage from monthly bucket from running total
	u = client.GetUsageTotal("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity), "usage from monthly bucket from running total")
	g.Expect(u.BillableAmount).Should(gomega.Equal(targetBilledAmount), "usage billed amount from monthly bucket from final total")
}

func Test_UsageIngestion_When_Rollups_PivotFromSku_ToCustomer(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// produce message
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"product1", "product2"}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	sku1 := "sku-1"
	_ = client.UpsertPricing(&proto.Pricing{
		Sku:         sku1,
		Product:     "product1",
		Price:       2.0,
		EffectiveAt: time.Date(2010, 11, 1, 0, 0, 0, 0, time.UTC).Unix(), // Enabled before ingestion date
	})

	sku2 := "sku-2"
	_ = client.UpsertPricing(&proto.Pricing{
		Sku:         sku2,
		Product:     "product2",
		Price:       3.0,
		EffectiveAt: time.Date(2010, 11, 1, 0, 0, 0, 0, time.UTC).Unix(), // Enabled before ingestion date
	})

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), sku1, 10, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), sku2, 10, customerId, usageDate)

	usageDate2 := time.Date(2010, 11, 18, 12, 0, 0, 0, time.UTC)
	usage3 := stubs.CreateUsage(uuid.NewString(), sku1, 77, customerId, usageDate2)
	usage4 := stubs.CreateUsage(uuid.NewString(), sku2, 13, customerId, usageDate2)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))
	// after the hourly job, get usage from customer hourly bucket from final total
	u := client.GetUsageTotal("", "", customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(20.0), "usage daily for usage date")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(50.0))

	u = client.GetUsageTotal("", "", customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(20.0), "usage daily for usage date")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(50.0))

	u = client.GetUsageTotal("", "", customerId, usageDate2, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(90.0), "usage daily for usage date2")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(193.0))

	u = client.GetUsageTotal("", sku2, customerId, usageDate2, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(13.0), "usage daily for sku2 and usage date2")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(13 * 3.0))

	u = client.GetUsageTotal("product2", "", customerId, usageDate2, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(13.0), "usage daily for product2 and usage date2")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(13 * 3.0))

	client.RunMonthlyJob(len(usages))

	// after the daily job, get usage from daily bucket from final total
	u = client.GetUsageTotal("", "", customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(110.0), "monthly customer data")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(243.0))

	u = client.GetUsageTotal("", sku1, customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(87.0), "monthly data for customer and sku")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(174.0))
}

func Test_UsageIngestion_When_RollupsAreRun_TwoUsages_Are_RecordedInAGivenHour(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureRandomPricingExists()

	// produce message and run ingestion
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 32.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1, usage2}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))

	u := client.GetUsageTotal("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(u.Quantity).Should(gomega.Equal(64.0))
	g.Expect(u.BillableAmount).Should(gomega.Equal(64.0 * pricing.GetPrice()))
}

func Test_UsageIngestion_When_RollupsAreRun_LineItemsAreRecorded(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	price := 0.5
	price2 := 1.5
	pricing := client.EnsureSpecificPricingExists(price, "product-1_sku-1", "product-1", "SKU 1")
	pricing2 := client.EnsureSpecificPricingExists(price2, "product-1_sku-2", "product-1", "SKU 2")

	// produce message
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{pricing.Product, pricing2.Product}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 32.0

	// create 8 usage for 4 different hours over 2 days.
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity+1, customerId, usageDate)

	usageDate2 := time.Date(2010, 11, 14, 4, 0, 0, 0, time.UTC)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity+2, customerId, usageDate2)
	usage4 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity+3, customerId, usageDate2)
	// create 1 usage for the same product, but different SKU
	usage5 := stubs.CreateUsage(uuid.NewString(), pricing2.Sku, quantity+3, customerId, usageDate2)

	usageDate3 := time.Date(2010, 11, 16, 12, 0, 0, 0, time.UTC)
	usage6 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity+4, customerId, usageDate3)
	usage7 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity+5, customerId, usageDate3)

	usageDate4 := time.Date(2010, 11, 16, 17, 0, 0, 0, time.UTC)
	usage8 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity+6, customerId, usageDate4)
	usage9 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity+7, customerId, usageDate4)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5, usage6, usage7, usage8, usage9}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	matchingOnAmounts := func(quantity float64, billedAmount float64, appliedCostPerQuantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Quantity == quantity && item.FullQuantity == quantity && item.BilledAmount == billedAmount && item.AppliedCostPerQuantity == appliedCostPerQuantity
		}
	}

	client.RunDailyJob(len(usages))

	// query by product - 5 usages for `usageDate` should be rolled up into 3 line items, one for each active hour/SKU pair
	u := client.GetUsageLineItems(pricing.Product, "", customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(65.0, 32.5, price)))  // sku-1 for hour 3
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(69.0, 34.5, price)))  // sku-1 for hour 4
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(35.0, 52.5, price2))) // sku-2 for hour 4

	u = client.GetUsageLineItems("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Daily)
	// the 4 usages for the first day should be rolled up into 2 line items, one for each active hour in the day
	// the usages from the 14th one record for the 3rd and one for the 4th hour of the day
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(65.0, 32.5, price)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(69.0, 34.5, price)))

	u = client.GetUsageLineItems("", pricing.GetSku(), customerId, usageDate3, proto.BillingPeriod_Daily)
	// the 4 usages for the 2nd day should be rolled up into 2 line items, one for each active hour in the day
	// the usages from the 16th one record for the 12th and one for the 17th hour of the day
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(73, 36.5, price)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(77, 38.5, price)))

	client.RunMonthlyJob(len(usages))
	// we can use any of the dates here, as they all roll up to the same month
	u = client.GetUsageLineItems("", pricing.GetSku(), customerId, usageDate3, proto.BillingPeriod_Monthly)
	// the usages for the hours on each day will now be one line item for each day
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(65+69, 32.5+34.5, price)), "Expected 1 line items on the 14th")
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(73+77, 36.5+38.5, price)), "Expected 1 line items on the 16th")

	// // we can use any of the dates here, as they all rol up to the same year
	// u = client.GetUsageLineItems("", pricing.GetSku(), customerId, usageDate3, proto.BillingPeriod_Yearly)
	// // the usages for the days this month will now be one line item for each month
	// g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(65+69+73+77, 32.5+34.5+36.5+38.5, price)), "Expected 1 line item for november")

	// we also roll the daily records from the sku/customer to the customer level for the month
	u = client.GetUsageLineItems("", "", customerId, usageDate3, proto.BillingPeriod_Monthly)
	// the usages for the hours on each day will now be one line item for each day
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(65+69, 32.5+34.5, price)), "Expected 1 line items on the 14th at the customer level")
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(73+77, 36.5+38.5, price)), "Expected 1 line items on the 16th at the customer level")

	// Test that orgId and repoId are set to their zero values in the monthly ByCustomer roll up
	u = client.GetUsageLineItems("", "", customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(u.BillingItems[0].RepoId).Should(gomega.Equal(int64(0)))
	g.Expect(u.BillingItems[0].OrgId).Should(gomega.Equal(int64(0)))
}

func Test_UsageIngestion_GetLineItems_Returns_Calculated_Fields(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	price := 0.5
	sku := "product-1_sku-1"
	product := "product-1"
	friendlySkuName := "SKU 1"
	pricing := client.EnsureSpecificPricingExists(price, sku, product, friendlySkuName)

	// produce message
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{product}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 32.0

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, usageDate, proto.BillingPeriod_Daily)
	// BillingItems should not be empty
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty())
	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity))
	g.Expect(billingItem.FullQuantity).Should(gomega.Equal(quantity))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_UsageIngestion_Watermark_Level(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", models.PricingMeterPerHourUnitCharge, "name", proto.UnitType_GigabyteHours)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{pricing.Product}
	customerId := customerProto.CustomerId

	usageDate1 := time.Date(2023, 5, 4, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 1, customerId, usageDate1)

	usageDate2 := time.Date(2023, 5, 5, 3, 0, 0, 0, time.UTC)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 1, customerId, usageDate2)

	usage3 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), 3, customerId, usageDate1, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usage4 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), 5, customerId, usageDate2, usage2.Entity.RepoId, usage2.Entity.OrganizationId)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4}

	// return 0 when there is no customer yet
	l := client.GetWatermarkLevel(customerId, pricing.GetSku(), usage1.Entity.OrganizationId, usage1.Entity.RepoId)
	g.Expect(l.Quantity).Should(gomega.Equal(0.0), "quantity should be == 0")

	_ = client.CreateCustomer(customerProto)

	// return 0 when there is no usage yet
	l = client.GetWatermarkLevel(customerId, pricing.GetSku(), usage1.Entity.OrganizationId, usage1.Entity.RepoId)
	g.Expect(l.Quantity).Should(gomega.Equal(0.0), "quantity should be == 0")

	now := time.Date(2023, 5, 6, 3, 0, 0, 0, time.UTC)
	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})

	l = client.GetWatermarkLevel(customerId, pricing.GetSku(), 0, 0)
	g.Expect(l.Quantity).Should(gomega.Equal(10.0))

	l = client.GetWatermarkLevel(customerId, pricing.GetSku(), usage1.Entity.OrganizationId, usage1.Entity.RepoId)
	g.Expect(l.Quantity).Should(gomega.Equal(4.0))

	l = client.GetWatermarkLevel(customerId, pricing.GetSku(), usage2.Entity.OrganizationId, usage2.Entity.RepoId)
	g.Expect(l.Quantity).Should(gomega.Equal(6.0))
}

func Test_UsageIngestion_Event_Is_Created_When_Usage_Is_For_Watermark_Product(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", models.PricingMeterPerHourUnitCharge, "name", proto.UnitType_GigabyteHours)

	// emit an event for a watermarked sku
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{pricing.Product}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 5, 4, 3, 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 1, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage}

	client.ProduceMeteredUsage(usages)

	// Run jobs to ensure they don't pick up the usage event
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// We should not create a line item for watermark events
	// TODO we need to update this expectation now that we do return materialized line items for watermarks.
	// Is there a way we can distinguish them?
	//  u := client.GetUsageLineItems("", "", customerId, usageDate, proto.BillingPeriod_Hourly)
	// g.Expect(u.BillingItems).Should(gomega.BeEmpty(), "a line item should not be created yet")

	// A watermark event should be created
	u := client.GetUsageEventItems("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Hourly)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "an event is expected")
}

func Test_UsageIngestion_Event_Is_Created_When_Usage_Is_For_Watermark_Product_For_Missing_Customer(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", models.PricingMeterPerHourUnitCharge, "name", proto.UnitType_GigabyteHours)

	customerId := "10000001000" // non-existent customer id

	usageDate := time.Date(2023, 4, 12, 3, 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 1, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 3, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage, usage2}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	// A watermark event should be created
	u := client.GetUsageEventItems("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Hourly)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "an event is expected")

	l := client.GetWatermarkLevel(customerId, pricing.GetSku(), 0, 0)
	g.Expect(l.Quantity).Should(gomega.Equal(4.0))

	l = client.GetWatermarkLevel(customerId, pricing.GetSku(), usage.Entity.OrganizationId, usage.Entity.RepoId)
	g.Expect(l.Quantity).Should(gomega.Equal(1.0))

}

func Test_UsageIngestion_Usage_Is_NOT_Created_For_Missing_Customer(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(0.08, "actions_linux", "actions", "Actions")

	// customer ID not onboarded to billing platform
	customerId := "1000010000"

	usageDate := time.Date(2024, 4, 12, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 1, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, usageDate, proto.BillingPeriod_Hourly)
	g.Expect(u.BillingItems).Should(gomega.BeEmpty(), "a line item should not be created")
}

func Test_UsageIngestion_RollupsMissingCustomerId_Are_NotRecorded(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	price := 0.5
	sku := "product-1_sku-1"
	product := "product-1"
	friendlySkuName := "SKU 1"
	pricing := client.EnsureSpecificPricingExists(price, sku, product, friendlySkuName)

	// produce message
	customerId := ""
	quantity := 32.0

	usage1Id := uuid.NewString()
	usage2Id := uuid.NewString()
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(usage1Id, pricing.GetSku(), quantity, customerId, usageDate)
	usage2 := stubs.CreateUsage(usage2Id, pricing.GetSku(), quantity*2, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1, usage2}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	u := client.GetUsageLineItemsGroupBy("", "", customerId, usageDate, proto.BillingPeriod_Hourly, proto.UsageGroupBy_GroupByOrgRepoProductSku)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(0))
}

func Test_UsageIngestion_Repo_Usage_Monthly(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureRandomPricingExists()

	// produce message
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 1.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usageDate2 := time.Date(2010, 11, 15, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), 33, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usage3 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), 50, customerId, usageDate2, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))

	u := client.GetRepoUsageLineItemsGroupBy(customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems[0].Quantity).Should(gomega.Equal(34.0))

	matchingOnAmounts := func(quantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Quantity == quantity
		}
	}

	client.RunMonthlyJob(len(usages))
	u = client.GetRepoUsageLineItemsGroupBy(customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(34.0)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(50.0)))
}

func Test_UsageIngestion_Get_Different_Repo_Usage_Same_Day(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureRandomPricingExists()

	// produce message
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 1.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usageDate2 := time.Date(2010, 11, 14, 6, 0, 0, 0, time.UTC)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 33, customerId, usageDate2)
	usage4 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity, customerId, usageDate2, usage3.Entity.RepoId, usage3.Entity.OrganizationId)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4}

	matchingOnAmounts := func(quantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Quantity == quantity
		}
	}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))
	u := client.GetRepoUsageLineItemsGroupBy(customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(2))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(quantity * 2)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(quantity + 33)))
}

func Test_UsageIngestion_Get_Different_Repo_Usage_Different_Day(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureRandomPricingExists()

	// produce message
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 1.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usageDate2 := time.Date(2010, 11, 15, 6, 0, 0, 0, time.UTC)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 33, customerId, usageDate2)
	usage4 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity, customerId, usageDate2, usage3.Entity.RepoId, usage3.Entity.OrganizationId)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4}

	matchingOnAmounts := func(quantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Quantity == quantity
		}
	}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	client.RunMonthlyJob(len(usages))
	u := client.GetRepoUsageLineItemsGroupBy(customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(quantity * 2)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(quantity + 33)))
}

func Test_UsageIngestion_RollUp_CostCenter_Azure_Usage(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the azure emission scheduler will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProto)

	// create cost center specific usage
	entity := &proto.EntityDetail{
		CustomerId: customerProto.CustomerId,
		OwnerId:    stubs.GetRandomId64(),
		RepoId:     stubs.GetRandomId64(),
		ActorId:    stubs.GetRandomId64(),
	}
	costCenter := stubs.CreateAzureCostCenterWithCustomerId(customerProto.CustomerId)
	response, _ := client.CreateCostCenter(costCenter)
	costCenterKey := response.CostCenter.CostCenterKey
	resource := stubs.GetResource(entity, proto.ResourceType_Org)
	_, err := client.CostCenterAddResourceTo(costCenterKey, []*proto.Resource{resource})
	g.Expect(err).ToNot(gomega.HaveOccurred())

	g.Expect(costCenterKey.TargetType).Should(gomega.BeEquivalentTo(models.AzureSubscription))

	pricing := client.EnsureRandomPricingExists()

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	quantity := 1.0
	usage := stubs.CreateUsageFrom(pricing, entity, usageDate, quantity)
	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage})
	client.RunUsageIngestion(1)

	client.ValidateQueue(1, models.WorkerTypeCustomerAzureEmissionDailyRollup)

	client.RunAzureDailyRollupJob(1)
	client.RunDailyJob(1)

	item, _ := db.NewQuerier[*models.Item](client.DB).ReadItem(context.Background(), client.Logger, &models.Key{PartitionKey: "2010:11:14:byAzureEmission", Id: fmt.Sprintf("%s:%s:2010:11:14", costCenterKey.Uuid, pricing.GetSku())}, nil)
	g.Expect(item.EntityDetail.CustomerId).Should(gomega.Equal(costCenterKey.Uuid))
}

func Test_UsageIngestion_GroupBy_OrgRepoProductSku_Daily_and_Monthly(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	price := 0.5
	pricing1 := client.EnsureSpecificPricingExists(price, "actions_windows_64_core", "actions", "Actions")
	pricing2 := client.EnsureSpecificPricingExists(price, "codespaces_compute_d32", "codespaces", "codespaces")

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"actions", "codespaces"}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 32.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	differentDate := time.Date(2010, 11, 15, 3, 0, 0, 0, time.UTC)
	nextMonth := time.Date(2010, 12, 15, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, quantity, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing1.Sku, quantity+1, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usage3 := stubs.CreateUsageWithOrgRepo(pricing1.Sku, quantity+1, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usage4 := stubs.CreateUsageWithOrgRepo(pricing2.Sku, quantity+2, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usage5 := stubs.CreateUsageWithOrgRepo(pricing2.Sku, quantity+50, customerId, differentDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usage6 := stubs.CreateUsageWithOrgRepo(pricing2.Sku, quantity+70, customerId, nextMonth, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usage7 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, quantity, customerId, nextMonth)

	// produce message
	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5, usage6, usage7}
	matchingOnAmountsAndSkus := func(sku string, quantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Sku == sku && item.Quantity == quantity
		}
	}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	u := client.GetOrgRepoProductSkuUsageLineItems(customerId, usageDate, proto.BillingPeriod_Hourly)

	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing1.Sku, 32)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing1.Sku, 33)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing2.Sku, 34)))
	client.RunDailyJob(len(usages))
	u = client.GetOrgRepoProductSkuUsageLineItems(customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(2))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing1.Sku, 32+33+33)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing2.Sku, 34)))

	client.RunMonthlyJob(len(usages))
	u = client.GetOrgRepoProductSkuUsageLineItems(customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(3))

	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing1.Sku, 32+33+33)))
	// we only expect 34 here since the usages for pricing2.Sku all have different usage date times
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing2.Sku, 34)))

	client.RunYearlyJob(len(usages))
	u = client.GetOrgRepoProductSkuUsageLineItems(customerId, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(4))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing1.Sku, 32+33+33)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing2.Sku, 34+82)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing1.Sku, 32))) // different org/repo
}

func TestZeroOutQuantities_ReturnsLineItemWithTotalMinusBackfillAmount(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing1 := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", models.PricingMeterPerHourUnitCharge, "name", proto.UnitType_GigabyteHours)

	customerProto1 := stubs.CreateEnabledCustomerWithId("1", proto.BillingTarget_Zuora)
	customerProto1.EnabledProducts = []string{pricing1.Product}
	customerId := customerProto1.CustomerId
	_ = client.CreateCustomer(customerProto1)

	quantity := 32.0
	now := time.Now()
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	regularUsage := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 10.0, customerId, usageDate)
	backfillUsage := stubs.CreateBackfillUsage(uuid.NewString(), pricing1.Sku, quantity, customerId, usageDate)

	// generate "organic" watermark usage
	client.ProcessWatermarkUsage(usageDate, []*hydroSchema.Usage{regularUsage}, integration.ProcessWatermarkUsageOpts{})

	// generate a backfill event for shared storage
	client.ProduceMeteredUsage([]*hydroSchema.Usage{backfillUsage})
	client.RunUsageIngestion(1)

	// run the zero-out workflow
	client.ScheduleZeroOutQuantities(customerId, pricing1.Sku, usageDate)
	client.RunRequestHandler(1)
	client.RunZeroOutQuantitiesHandler(1)
	client.RunUsageIngestion(1)

	originalEvents := client.GetUsageEventItems(pricing1.Product, pricing1.Sku, customerId, usageDate, proto.BillingPeriod_Hourly)
	newEvents := client.GetUsageEventItems(pricing1.Product, pricing1.Sku, customerId, now, proto.BillingPeriod_Hourly)

	matchingOnAmountsAndSkus := func(sku string, quantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Sku == sku && item.Quantity == quantity
		}
	}

	g.Expect(originalEvents.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing1.Sku, quantity)))
	g.Expect(newEvents.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing1.Sku, quantity*-1)))

	client.RunDailyJob(1)

	lineItems := client.GetRepoUsageLineItemsGroupBy(customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(lineItems.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	billingItem := lineItems.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(10.0))
	g.Expect(billingItem.UsageEntityId).Should(gomega.Equal(customerId))
}

func TestZeroOutQuantities_ReturnsNoLineItemWhen0Quantity(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing1 := client.EnsureSpecificPricingExistsWithAll(0.0008, "sku1", "product1", models.PricingMeterPerHourUnitCharge, "name", proto.UnitType_GigabyteHours)

	customerProto1 := stubs.CreateEnabledCustomerWithId("1", proto.BillingTarget_Zuora)
	customerProto1.EnabledProducts = []string{pricing1.Product}
	customerId := customerProto1.CustomerId
	_ = client.CreateCustomer(customerProto1)

	quantity := 32.0
	now := time.Now()
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	backfillUsage := stubs.CreateBackfillUsage(uuid.NewString(), pricing1.Sku, quantity, customerId, usageDate)

	// generate a backfill event for shared storage
	client.ProduceMeteredUsage([]*hydroSchema.Usage{backfillUsage})
	client.RunUsageIngestion(1)

	// run the zero-out workflow
	client.ScheduleZeroOutQuantities(customerId, pricing1.Sku, usageDate)
	client.RunRequestHandler(1)
	client.RunZeroOutQuantitiesHandler(1)
	client.RunUsageIngestion(1)

	// we have to run this query twice - once to get the events from the original usage date and again to get the event created by the zero out workflow
	originalEvents := client.GetUsageEventItems(pricing1.Product, pricing1.Sku, customerId, usageDate, proto.BillingPeriod_Hourly)
	newEvents := client.GetUsageEventItems(pricing1.Product, pricing1.Sku, customerId, now, proto.BillingPeriod_Hourly)

	matchingOnAmountsAndSkus := func(sku string, quantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Sku == sku && item.Quantity == quantity
		}
	}

	g.Expect(originalEvents.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing1.Sku, quantity)))
	g.Expect(newEvents.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus(pricing1.Sku, quantity*-1)))

	lineItems := client.GetRepoUsageLineItemsGroupBy(customerId, usageDate, proto.BillingPeriod_Hourly)
	g.Expect(lineItems.BillingItems).Should(gomega.BeEmpty(), "no line items should be created")
}

func Test_UsageIngestion_Default_UnitType_Pricing_Finds_Correct_UnitType(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// Create a pricing record with default unit type
	sku := "actions_storage"
	product := "actions"
	price := 0.0008
	pricing := client.EnsureSpecificPricingExistsWithUnitType(price, sku, product, proto.UnitType_Unknown)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{product}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 10, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty())
	g.Expect(u.BillingItems[0].UnitType).Should(gomega.Equal(proto.UnitType_GigabyteHours))
}

func TestUsage_SimulateSkippedUsageFromCustomerFlagDisabled(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(0.08, "actions_linux", "actions", "Actions")

	// produce message and run ingestion
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	// explicitly set to false to ensure we aren't billed
	customerProto.BillForPublicRepoUsage = false
	_ = client.CreateCustomer(customerProto)

	// validate the customer has the flag set to false
	customerResponse := client.GetCustomer(customerId)
	g.Expect(customerResponse.Customer.BillForPublicRepoUsage).To(gomega.BeFalse())

	quantity := 50_000.0
	targetBilledAmount := 4_000.00

	// exhaust plan discount for actions

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))
	// after the daily job, get usage from daily bucket from final total
	u := client.GetUsageTotal("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity), "usage from daily bucket from final total")
	g.Expect(u.BillableAmount).Should(gomega.Equal(targetBilledAmount), "usage billed amount from daily bucket from final total")

	client.RunMonthlyJob(len(usages))
	// after the daily job, get usage from monthly bucket from running total
	u = client.GetUsageTotal("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity), "usage from monthly bucket from running total")
	g.Expect(u.BillableAmount).Should(gomega.Equal(targetBilledAmount), "usage billed amount from monthly bucket from final total")

	// ingest usage that will be treated as free since it's for a public repo

	usageDate = time.Date(2010, 11, 14, 4, 0, 0, 0, time.UTC)
	usage1 = stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)

	usages = []*hydroSchema.Usage{usage1}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))
	// after the daily job, get usage from daily bucket from final total
	u = client.GetUsageTotal("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*2), "usage from daily bucket from final total")
	g.Expect(u.BillableAmount).Should(gomega.Equal(targetBilledAmount*2), "usage billed amount from daily bucket from final total")

	client.RunMonthlyJob(len(usages))
	// after the daily job, get usage from monthly bucket from running total
	u = client.GetUsageTotal("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*2), "usage from monthly bucket from running total")
	g.Expect(u.BillableAmount).Should(gomega.Equal(targetBilledAmount*2), "usage billed amount from monthly bucket from final total")

	// validate that discount line items were written to make the public repo usage free
	d := client.GetDiscountTotal(pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(d.Quantity)).Should(gomega.Equal(5_000.0), "free for public repo discounts applied")
	g.Expect(d.DiscountAmount).Should(gomega.Equal(400.0), "free for public repo discounts applied")

	// ingest usage that will be billed despite being for a public repo

	patchProto := &proto.Customer{
		CustomerId:             customerId,
		BillForPublicRepoUsage: true,
		EnabledProducts:        []string{"actions"},
	}
	_ = client.UpsertCustomer(patchProto)

	// validate the customer has the flag updated to true
	customerResponse = client.GetCustomer(customerId)
	g.Expect(customerResponse.Customer.BillForPublicRepoUsage).To(gomega.BeTrue())

	usageDate = time.Date(2010, 11, 14, 5, 0, 0, 0, time.UTC)
	usage1 = stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)

	usages = []*hydroSchema.Usage{usage1}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))
	// after the daily job, get usage from daily bucket from final total
	u = client.GetUsageTotal("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*3), "usage from daily bucket from final total")
	g.Expect(u.BillableAmount).Should(gomega.Equal(targetBilledAmount*3), "usage billed amount from daily bucket from final total")

	client.RunMonthlyJob(len(usages))
	// after the daily job, get usage from monthly bucket from running total
	u = client.GetUsageTotal("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity*3), "usage from monthly bucket from running total")
	g.Expect(u.BillableAmount).Should(gomega.Equal(targetBilledAmount*3), "usage billed amount from monthly bucket from final total")

	// validate that no new discount line items were written since free public repo usage was disabled for the customer
	d = client.GetDiscountTotal(pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(float64(d.Quantity)).Should(gomega.Equal(5_000.0), "free for public repo discounts applied")
	g.Expect(d.DiscountAmount).Should(gomega.Equal(400.0), "free for public repo discounts applied")
}

func Test_UsageIngestion_Usage_Ingestion_Invoicing_With_Customer_With_No_Enabled_Products(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{}
	_ = client.CreateCustomer(customerProto)

	client.EnsureProductExists("actions", "Actions", "GitHub Actions Usage")

	// Enabled SKU
	pricing1 := client.EnsureSpecificPricingExistsWithEffectiveAt(
		0.016,
		"actions_linux_4_core",
		"actions",
		proto.PricingMeterType_Default,
		time.Date(2022, 5, 1, 0, 0, 0, 0, time.UTC).Unix(),
	)

	// Create some usage
	usageDate := time.Date(2023, 5, 10, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerProto.CustomerId, usageDate)
	usages := []*hydroSchema.Usage{usage1}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	ipd := &models.InvoicePartitionDetail{
		CustomerId: customerProto.CustomerId,
		Period:     models.InvoiceMonthly,
		Year:       2023,
		Month:      5,
	}
	// No active invoice should be created for customers who have no enabled products
	activeInvoice, _ := db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice).To(gomega.BeNil())
}

func Test_Usage_ByOrgandRepoPartitionItems(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(0.08, "actions_linux", "actions", "Actions")
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)
	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	orgId := stubs.GetRandomId64()
	repoId := stubs.GetRandomId64()

	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: orgId,
		RepoId:         repoId,
		ActorId:        stubs.GetRandomId64(),
	}

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	quantity := 1000.0

	usage := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity, customerId, usageDate, entity.RepoId, entity.OrganizationId)
	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage})
	client.RunUsageIngestion(1)
	client.RunDailyJob(1)

	validateItemFields := func(items []*proto.BillingItem, expectedItemsLength int) {
		g.Expect(len(items)).To(gomega.Equal(expectedItemsLength))
		g.Expect(items[0].OrgId).To(gomega.Equal(entity.OrganizationId))
		g.Expect(items[0].RepoId).To(gomega.Equal(entity.RepoId))
		g.Expect(items[0].UsageEntityId).To(gomega.Equal(customerId))
		// When unmarshalling a nil Pricing struct from JSON, all of its fields are set to their zero values.
		g.Expect(items[0].Sku).To(gomega.Equal(""))
		g.Expect(items[0].Product).To(gomega.Equal(""))
		g.Expect(items[0].UnitType).To(gomega.Equal(proto.UnitType_Unknown))
		g.Expect(items[0].FriendlySkuName).To(gomega.Equal(""))
	}

	// Daily items
	response := client.GetUsageLineItemsGroupBy("", "", customerId, usageDate, proto.BillingPeriod_Daily, proto.UsageGroupBy_GroupByOrganization)
	items := response.BillingItems

	validateItemFields(items, 1)

	// Monthly items
	client.RunMonthlyJob(1)
	response = client.GetUsageLineItemsGroupBy("", "", customerId, usageDate, proto.BillingPeriod_Monthly, proto.UsageGroupBy_GroupByOrganization)
	items = response.BillingItems

	validateItemFields(items, 1)

	// Yearly items
	client.RunYearlyJob(1)
	response = client.GetUsageLineItemsGroupBy("", "", customerId, usageDate, proto.BillingPeriod_Yearly, proto.UsageGroupBy_GroupByOrganization)
	items = response.BillingItems

	validateItemFields(items, 1)
}

func Test_Usage_ByCustomerOrgAndByCustomerRepoPartitionItems(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithUnitType(0.08, "actions_linux", "actions", proto.UnitType_Minutes)
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)
	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	orgId := stubs.GetRandomId64()
	repoId := stubs.GetRandomId64()

	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: orgId,
		RepoId:         repoId,
		ActorId:        stubs.GetRandomId64(),
	}
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usageDate1 := time.Date(2010, 11, 14, 4, 0, 0, 0, time.UTC)
	quantity := 1000.0

	usage := stubs.CreateUsageWithOrgRepo(pricing.Sku, quantity, customerId, usageDate, entity.RepoId, entity.OrganizationId)
	usage1 := stubs.CreateUsageWithOrgRepo(pricing.Sku, quantity, customerId, usageDate1, entity.RepoId, entity.OrganizationId)
	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage, usage1})
	client.RunUsageIngestion(2)

	validateItemFields := func(items []*proto.BillingItem, expectedItemsLength int) {
		g.Expect(len(items)).To(gomega.Equal(expectedItemsLength))
		g.Expect(items[0].OrgId).To(gomega.Equal(entity.OrganizationId))
		g.Expect(items[0].RepoId).To(gomega.Equal(entity.RepoId))
		g.Expect(items[0].UsageEntityId).To(gomega.Equal(customerId))
		g.Expect(items[0].Sku).To(gomega.Equal(pricing.Sku))
		g.Expect(items[0].Product).To(gomega.Equal(pricing.Product))
		g.Expect(items[0].UnitType).To(gomega.Equal(pricing.UnitType))
		g.Expect(items[0].FriendlySkuName).To(gomega.Equal(pricing.FriendlyName))
	}

	// Daily items with an org id
	client.RunDailyJob(2)
	response := client.GetOrgRepoUsageLineItems(entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Daily)
	items := response.BillingItems

	validateItemFields(items, 2)

	// Monthly items with a repo id
	client.RunMonthlyJob(2)
	response = client.GetOrgRepoUsageLineItems(0, entity.RepoId, customerId, usageDate, proto.BillingPeriod_Monthly)
	items = response.BillingItems

	validateItemFields(items, 1)

	// Yearly items with an org id
	client.RunYearlyJob(2)
	response = client.GetOrgRepoUsageLineItems(entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Yearly)
	items = response.BillingItems

	validateItemFields(items, 1)
}

func Test_Usage_ByCustomerSkuAndByCustomerProductPartitionItems(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithUnitType(0.08, "actions_linux", "actions", proto.UnitType_Minutes)
	pricing1 := client.EnsureSpecificPricingExistsWithUnitType(0.0875, "git_lfs_bandwidth", "git_lfs", proto.UnitType_Gigabytes)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{pricing.Product, pricing1.Product}
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)
	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	orgId := stubs.GetRandomId64()
	repoId := stubs.GetRandomId64()

	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: orgId,
		RepoId:         repoId,
		ActorId:        stubs.GetRandomId64(),
	}
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usageDate1 := time.Date(2010, 11, 14, 3, 22, 0, 0, time.UTC)
	quantity := 1000.0

	usage := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.GetSku(), quantity, usageDate, entity)
	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing1.Sku, quantity, usageDate1, entity)

	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage, usage1})
	client.RunUsageIngestion(2)
	client.RunDailyJob(2)

	validateItemFields := func(items []*proto.NetUsageItem, expectedItemsLength int, usage *hydroSchema.Usage, pricing *proto.Pricing) {
		g.Expect(len(items)).To(gomega.Equal(expectedItemsLength))
		g.Expect(items[0].OrgId).To(gomega.Equal(int64(0)))
		g.Expect(items[0].RepoId).To(gomega.Equal(int64(0)))
		g.Expect(items[0].UsageEntityId).To(gomega.Equal(customerId))
		g.Expect(items[0].Sku).To(gomega.Equal(pricing.GetSku()))
		g.Expect(items[0].Product).To(gomega.Equal(pricing.Product))
		g.Expect(items[0].Quantity).To(gomega.Equal(usage.Quantity))
		g.Expect(items[0].GrossAmount).To(gomega.Equal(usage.Quantity * pricing.GetPrice()))
		g.Expect(items[0].UnitType).To(gomega.Equal(pricing.UnitType))
	}

	// Daily items with a SKU
	linuxNetUsage := client.GetNetUsageLineItems("", "actions_linux", strconv.FormatInt(entity.CustomerId, 10), usageDate, proto.BillingPeriod_Daily)
	linuxItems := linuxNetUsage.NetUsageItems

	validateItemFields(linuxItems, 1, usage, pricing)

	lfsNetUsage := client.GetNetUsageLineItems("", "git_lfs_bandwidth", strconv.FormatInt(entity.CustomerId, 10), usageDate, proto.BillingPeriod_Daily)
	lfsItems := lfsNetUsage.NetUsageItems

	validateItemFields(lfsItems, 1, usage1, pricing1)

	// Monthly items with a SKU
	client.RunMonthlyJob(2)
	linuxNetUsage = client.GetNetUsageLineItems("", "actions_linux", strconv.FormatInt(entity.CustomerId, 10), usageDate, proto.BillingPeriod_Monthly)
	linuxItems = linuxNetUsage.NetUsageItems

	validateItemFields(linuxItems, 1, usage, pricing)

	lfsNetUsage = client.GetNetUsageLineItems("", "git_lfs_bandwidth", strconv.FormatInt(entity.CustomerId, 10), usageDate, proto.BillingPeriod_Monthly)
	lfsItems = lfsNetUsage.NetUsageItems

	validateItemFields(lfsItems, 1, usage1, pricing1)

	// Yearly items with a SKU
	client.RunYearlyJob(2)
	linuxNetUsage = client.GetNetUsageLineItems("", "actions_linux", strconv.FormatInt(entity.CustomerId, 10), usageDate, proto.BillingPeriod_Yearly)
	linuxItems = linuxNetUsage.NetUsageItems

	validateItemFields(linuxItems, 1, usage, pricing)

	lfsNetUsage = client.GetNetUsageLineItems("", "git_lfs_bandwidth", strconv.FormatInt(entity.CustomerId, 10), usageDate, proto.BillingPeriod_Yearly)
	lfsItems = lfsNetUsage.NetUsageItems

	validateItemFields(lfsItems, 1, usage1, pricing1)

	// Daily items with a product
	actionsNetUsage := client.GetNetUsageLineItems("actions", "", strconv.FormatInt(entity.CustomerId, 10), usageDate, proto.BillingPeriod_Daily)
	actionsItems := actionsNetUsage.NetUsageItems

	validateItemFields(actionsItems, 1, usage, pricing)

	// Monthly items with a product
	lfsNetUsage = client.GetNetUsageLineItems("git_lfs", "", strconv.FormatInt(entity.CustomerId, 10), usageDate, proto.BillingPeriod_Monthly)
	lfsItems = lfsNetUsage.NetUsageItems

	validateItemFields(lfsItems, 1, usage1, pricing1)

	// Yearly items with a product
	actionsNetUsage = client.GetNetUsageLineItems("actions", "", strconv.FormatInt(entity.CustomerId, 10), usageDate, proto.BillingPeriod_Yearly)
	actionsItems = actionsNetUsage.NetUsageItems

	validateItemFields(actionsItems, 1, usage, pricing)
}

func Test_Usage_ByCustomerPartitionItems(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithUnitType(0.08, "actions_linux", "actions", proto.UnitType_Minutes)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{pricing.Product}
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)
	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	orgId := stubs.GetRandomId64()
	repoId := stubs.GetRandomId64()

	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: orgId,
		RepoId:         repoId,
		ActorId:        stubs.GetRandomId64(),
	}
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usageDate1 := time.Date(2010, 11, 14, 4, 0, 0, 0, time.UTC)
	quantity := 1000.0

	usage := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate, entity)
	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.Sku, quantity, usageDate1, entity)

	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage, usage1})
	client.RunUsageIngestion(2)
	client.RunDailyJob(2)

	validateItemFields := func(items []*proto.NetUsageItem, expectedItemsLength int, expectedQuantity float64, pricing *proto.Pricing) {
		g.Expect(len(items)).To(gomega.Equal(expectedItemsLength))
		g.Expect(items[0].OrgId).To(gomega.Equal(int64(0)))
		g.Expect(items[0].RepoId).To(gomega.Equal(int64(0)))
		g.Expect(items[0].UsageEntityId).To(gomega.Equal(customerId))
		g.Expect(items[0].Sku).To(gomega.Equal(pricing.Sku))
		g.Expect(items[0].Product).To(gomega.Equal(pricing.Product))
		g.Expect(items[0].Quantity).To(gomega.Equal(expectedQuantity))
		g.Expect(items[0].GrossAmount).To(gomega.Equal(expectedQuantity * pricing.Price))
		g.Expect(items[0].UnitType).To(gomega.Equal(pricing.UnitType))
	}

	// Daily items
	netUsage := client.GetNetUsageLineItems("", "", strconv.FormatInt(entity.CustomerId, 10), usageDate, proto.BillingPeriod_Daily)
	dailyItems := netUsage.NetUsageItems
	expectedQuantity := usage.Quantity

	validateItemFields(dailyItems, 2, expectedQuantity, pricing)

	// Monthly items
	client.RunMonthlyJob(2)
	netUsage = client.GetNetUsageLineItems("", "", strconv.FormatInt(entity.CustomerId, 10), usageDate, proto.BillingPeriod_Monthly)
	monthlyItems := netUsage.NetUsageItems
	expectedQuantity = usage.Quantity + usage1.Quantity

	validateItemFields(monthlyItems, 1, expectedQuantity, pricing)

	// Yearly items
	client.RunYearlyJob(2)
	netUsage = client.GetNetUsageLineItems("", "", strconv.FormatInt(entity.CustomerId, 10), usageDate, proto.BillingPeriod_Yearly)
	yearlyItems := netUsage.NetUsageItems
	expectedQuantity = usage.Quantity + usage1.Quantity

	validateItemFields(yearlyItems, 1, expectedQuantity, pricing)
}

func Test_UsageIngestion_TrialCustomer_Overages_Calculated(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithUnitType(0.008, "actions_linux", "actions", proto.UnitType_Minutes)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{pricing.Product}
	customerProto.DiscountPlanName = "enterprise_trial"
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)
	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	orgId := stubs.GetRandomId64()
	repoId := stubs.GetRandomId64()

	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: orgId,
		RepoId:         repoId,
		ActorId:        stubs.GetRandomId64(),
	}
	initialUsageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	overageUsageDate := time.Date(2010, 11, 14, 3, 22, 0, 0, time.UTC)
	// Plan discount includes 3000 minutes
	initialQuantity := 2995.0
	overageUsageQuantity := 10.0
	expectedUsageQuantityMinusOverage := 3000.0
	fullQuantity := initialQuantity + overageUsageQuantity

	initialUsage := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.GetSku(), initialQuantity, initialUsageDate, entity)
	overageUsage := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.GetSku(), overageUsageQuantity, overageUsageDate, entity)

	client.ProduceMeteredUsage([]*hydroSchema.Usage{initialUsage, overageUsage})
	client.RunUsageIngestion(2)
	client.RunDailyJob(2)

	// Daily items with a SKU
	dailyUsage := client.GetNetUsageLineItems("", "actions_linux", strconv.FormatInt(entity.CustomerId, 10), initialUsageDate, proto.BillingPeriod_Daily)
	dailyItems := dailyUsage.NetUsageItems
	g.Expect(len(dailyItems)).To(gomega.Equal(1))
	g.Expect(dailyItems[0].Quantity).To(gomega.Equal(expectedUsageQuantityMinusOverage))
	g.Expect(dailyItems[0].FullQuantity).To(gomega.Equal(fullQuantity))
	g.Expect(dailyItems[0].GrossAmount).To(gomega.Equal(expectedUsageQuantityMinusOverage * pricing.GetPrice()))
	g.Expect(dailyItems[0].UnitType).To(gomega.Equal(pricing.UnitType))
}

func Test_UsageIngestion_TrialCustomerFirstUsage_Overages_Calculated(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithUnitType(0.008, "actions_linux", "actions", proto.UnitType_Minutes)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{pricing.Product}
	customerProto.DiscountPlanName = "enterprise_trial"
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)
	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	orgId := stubs.GetRandomId64()
	repoId := stubs.GetRandomId64()

	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: orgId,
		RepoId:         repoId,
		ActorId:        stubs.GetRandomId64(),
	}
	initialUsageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	// Plan discount includes 3000 minutes
	initialQuantity := 3005.0
	expectedUsageQuantityMinusOverage := 3000.0
	fullQuantity := initialQuantity

	initialUsage := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.GetSku(), initialQuantity, initialUsageDate, entity)

	client.ProduceMeteredUsage([]*hydroSchema.Usage{initialUsage})
	client.RunUsageIngestion(2)
	client.RunDailyJob(2)

	// Daily items with a SKU
	dailyUsage := client.GetNetUsageLineItems("", "actions_linux", strconv.FormatInt(entity.CustomerId, 10), initialUsageDate, proto.BillingPeriod_Daily)
	dailyItems := dailyUsage.NetUsageItems
	g.Expect(len(dailyItems)).To(gomega.Equal(1))
	g.Expect(dailyItems[0].Quantity).To(gomega.Equal(expectedUsageQuantityMinusOverage))
	g.Expect(dailyItems[0].FullQuantity).To(gomega.Equal(fullQuantity))
	g.Expect(dailyItems[0].GrossAmount).To(gomega.Equal(expectedUsageQuantityMinusOverage * pricing.GetPrice()))
	g.Expect(dailyItems[0].UnitType).To(gomega.Equal(pricing.UnitType))
}

func Test_UsageIngestion_TrialCustomerCostCenter_Overages_Calculated(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithUnitType(0.008, "actions_linux", "actions", proto.UnitType_Minutes)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{pricing.Product}
	customerProto.DiscountPlanName = "enterprise_trial"
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)
	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	orgId := stubs.GetRandomId64()
	repoId := stubs.GetRandomId64()

	// cost center without Azure or Zuora details
	costCenterProto := &proto.CostCenter{
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: customerId,
			TargetType: proto.CostCenterType_ZuoraSubscription,
			TargetId:   "",
		},
		Name: "TestCostCenter",
		Resources: []*proto.Resource{
			{
				Id:   fmt.Sprintf("%d", repoId),
				Type: proto.ResourceType_Repo,
			}},
	}

	costCenterResponse, _ := client.CreateCostCenter(costCenterProto)

	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: orgId,
		RepoId:         repoId,
		ActorId:        stubs.GetRandomId64(),
	}
	initialUsageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	overageUsageDate := time.Date(2010, 11, 14, 3, 22, 0, 0, time.UTC)
	// Plan discount includes 3000 minutes
	initialQuantity := 2995.0
	overageUsageQuantity := 10.0
	expectedUsageQuantityMinusOverage := 3000.0
	fullQuantity := initialQuantity + overageUsageQuantity

	initialUsage := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.GetSku(), initialQuantity, initialUsageDate, entity)
	overageUsage := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.GetSku(), overageUsageQuantity, overageUsageDate, entity)

	client.ProduceMeteredUsage([]*hydroSchema.Usage{initialUsage, overageUsage})
	client.RunUsageIngestion(2)
	client.RunDailyJob(2)

	// Daily items with a SKU
	dailyUsage := client.GetNetUsageLineItems("", "actions_linux", costCenterResponse.CostCenter.GetCostCenterKey().GetUuid(), initialUsageDate, proto.BillingPeriod_Daily)
	dailyItems := dailyUsage.NetUsageItems
	g.Expect(len(dailyItems)).To(gomega.Equal(1))
	g.Expect(dailyItems[0].Quantity).To(gomega.Equal(expectedUsageQuantityMinusOverage))
	g.Expect(dailyItems[0].FullQuantity).To(gomega.Equal(fullQuantity))
	g.Expect(dailyItems[0].GrossAmount).To(gomega.Equal(expectedUsageQuantityMinusOverage * pricing.GetPrice()))
	g.Expect(dailyItems[0].UnitType).To(gomega.Equal(pricing.UnitType))
}

func Test_UsageIngestion_EnterpriseCustomerWithBudget_Overages_Calculated(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithUnitType(0.008, "actions_linux", "actions", proto.UnitType_Minutes)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{pricing.Product}
	customerProto.DiscountPlanName = "enterprise"
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)
	customerIdInt, _ := strconv.ParseInt(customerId, 10, 64)
	orgId := stubs.GetRandomId64()
	repoId := stubs.GetRandomId64()

	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     customerIdInt,
		OrganizationId: orgId,
		RepoId:         repoId,
		ActorId:        stubs.GetRandomId64(),
	}

	amount := 0.0
	targetType := proto.ResourceType_Enterprise
	budget := stubs.CreateBudgetWithLimitType(customerId, targetType, customerId, proto.PricingTargetType_SkuPricing, "actions_linux", amount, proto.BudgetLimitType_PreventFurtherUsage)

	_ = client.UpsertBudget(budget)

	initialUsageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	// Plan discount includes 50000 minutes
	initialQuantity := 50100.0
	expectedUsageQuantityMinusOverage := 50000.0

	initialUsage := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.GetSku(), initialQuantity, initialUsageDate, entity)

	client.ProduceMeteredUsage([]*hydroSchema.Usage{initialUsage})
	client.RunUsageIngestion(1)
	client.RunDailyJob(1)

	// Daily items with a SKU
	dailyUsage := client.GetNetUsageLineItems("", "actions_linux", strconv.FormatInt(entity.CustomerId, 10), initialUsageDate, proto.BillingPeriod_Daily)
	dailyItems := dailyUsage.NetUsageItems
	g.Expect(dailyItems[0].Quantity).To(gomega.Equal(expectedUsageQuantityMinusOverage))
	g.Expect(dailyItems[0].FullQuantity).To(gomega.Equal(initialQuantity))
	g.Expect(dailyItems[0].GrossAmount).To(gomega.Equal(expectedUsageQuantityMinusOverage * pricing.GetPrice()))
	g.Expect(len(dailyItems)).To(gomega.Equal(1))
	g.Expect(dailyItems[0].UnitType).To(gomega.Equal(pricing.UnitType))
}

func Test_Usage_GetUsageChartData(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(0.08, "actions_linux", "actions", "Actions")
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)
	orgId := stubs.GetRandomId64()
	repoId := stubs.GetRandomId64()
	groupBy := proto.UsageGroupBy_GroupBySku

	entity := hydroSchemaEntities.EntityDetail{
		OrganizationId: orgId,
		RepoId:         repoId,
	}

	usageDate := time.Date(2020, 10, 14, 3, 0, 0, 0, time.UTC)
	quantity := 1000.0

	usage := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity, customerId, usageDate, entity.RepoId, entity.OrganizationId)
	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage})
	client.RunUsageIngestion(1)
	client.RunDailyJob(1)

	validateItemFields := func(items []*proto.UsageChartDataset, expectedDatasetsLength int) {
		g.Expect(len(items)).To(gomega.Equal(expectedDatasetsLength))
		g.Expect(items[0].Name).To(gomega.Equal("Actions"))
		// expect data to be present
		g.Expect(items[0].Data).ToNot(gomega.BeNil())
		// expect first item in data to have x, y, custom amounts
		g.Expect(items[0].Data[0].X).To(gomega.BeNumerically(">", 0))
		g.Expect(items[0].Data[0].Y).To(gomega.Equal(float64(0)))
		g.Expect(items[0].Data[0].Custom.DiscountAmount).To(gomega.Equal("N/A"))
		g.Expect(items[0].Data[0].Custom.GrossAmount).To(gomega.Equal("N/A"))
		g.Expect(items[0].Data[0].Custom.TotalAmount).To(gomega.Equal("N/A"))
	}

	// Daily items
	response := client.GetUsageChartData("", "", customerId, usageDate, proto.BillingPeriod_Daily, groupBy, 0, 0, "")
	items := response.UsageChartData

	validateItemFields(items, 1)

	// Monthly items
	client.RunMonthlyJob(1)
	response = client.GetUsageChartData("", "", customerId, usageDate, proto.BillingPeriod_Monthly, groupBy, 0, 0, "")
	items = response.UsageChartData

	validateItemFields(items, 1)

	// Yearly items
	client.RunYearlyJob(1)
	response = client.GetUsageChartData("", "", customerId, usageDate, proto.BillingPeriod_Yearly, groupBy, 0, 0, "")
	items = response.UsageChartData

	validateItemFields(items, 1)
}

func Test_Usage_GetPaginatedAndTopUsageLineItems(t *testing.T) {
	/* This tests we can
	- Get Paginated usage line items
	- Get Top Usage line items
	*/
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(0.08, "actions_linux", "actions", "Actions")
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	client.CreateCustomer(customerProto)

	costCenterIdParam := "All" // Aggregate usage behavior

	usageDate := time.Date(2020, 10, 14, 3, 0, 0, 0, time.UTC)
	quantity := 1000.0

	numUsageItems := 20
	usageItems := make([]*hydroSchema.Usage, numUsageItems)
	orgIDs := make([]int64, 0, numUsageItems)
	repoIDs := make([]int64, 0, numUsageItems)
	for i := 0; i < numUsageItems; i++ {
		orgIDs = append(orgIDs, stubs.GetRandomId64())
		repoIDs = append(repoIDs, stubs.GetRandomId64())
	}
	firstFiveOrgIDs := orgIDs[:5]
	firstFiveRepoIDs := repoIDs[:5]

	// Create a cost centers with a few of these top orgs and repos
	orgResources := map[int64]proto.ResourceType{firstFiveOrgIDs[0]: proto.ResourceType_Org, firstFiveOrgIDs[1]: proto.ResourceType_Org}
	_, _ = helpers.CreateCostCenter(customerId, "costCenter1", orgResources, proto.CostCenterType_AzureSubscription, client)
	repoResources := map[int64]proto.ResourceType{firstFiveRepoIDs[0]: proto.ResourceType_Repo, firstFiveRepoIDs[1]: proto.ResourceType_Repo}
	_, _ = helpers.CreateCostCenter(customerId, "costCenter2", repoResources, proto.CostCenterType_AzureSubscription, client)

	for i := 0; i < numUsageItems; i++ {
		usage := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity, customerId, usageDate, repoIDs[i], orgIDs[i])
		usageItems[i] = usage
	}

	client.ProduceMeteredUsage(usageItems)
	client.RunUsageIngestion(numUsageItems)
	client.RunDailyJob(numUsageItems)
	client.RunMonthlyJob(numUsageItems)

	// request for the first page of line items
	response := client.GetPaginatedLineItems(customerId, costCenterIdParam, usageDate, proto.BillingPeriod_Daily, proto.UsageGroupBy_GroupByOrganization, 1)
	items := response.OrgRepoItems
	g.Expect(len(items)).To(gomega.Equal(17))

	// request for the second page of line items
	response = client.GetPaginatedLineItems(customerId, costCenterIdParam, usageDate, proto.BillingPeriod_Daily, proto.UsageGroupBy_GroupByOrganization, 2)
	items = response.OrgRepoItems
	g.Expect(len(items)).To(gomega.Equal(3))

	// request for the third page of line items
	response = client.GetPaginatedLineItems(customerId, costCenterIdParam, usageDate, proto.BillingPeriod_Daily, proto.UsageGroupBy_GroupByOrganization, 3)
	items = response.OrgRepoItems
	g.Expect(len(items)).To(gomega.Equal(0))
	customerIdInt, err := strconv.ParseInt(customerId, 10, 64)
	assert.NoError(t, err)

	// Test Top  Repos - Monthly with data from cache
	limit := int32(5)

	// Get top orgs usage

	// populate Cache with org ids create above
	input := &models.UsageRequest{CustomerId: customerIdInt, CostCenterId: costCenterIdParam, Year: int64(usageDate.Year()), Month: int64(usageDate.Month()), Day: int64(usageDate.Day()), Hour: int64(usageDate.Hour()), BillingPeriod: proto.BillingPeriod_Monthly, GroupBy: proto.UsageGroupBy_GroupByOrganization}
	err = helpers.PopulateCacheForTopOrgs(client, input, firstFiveOrgIDs)
	assert.NoError(t, err)
	topOrgUsage := client.GetTopOrgRepoUsageLineItems(customerIdInt, costCenterIdParam, limit, usageDate, proto.BillingPeriod_Monthly, proto.UsageGroupBy_GroupByOrganization, nil)
	g.Expect(len(topOrgUsage.TopUsages)).To(gomega.Equal(5))

	// Get top repos usage
	// populate cache with top repo ids create above
	input = &models.UsageRequest{CustomerId: customerIdInt, CostCenterId: costCenterIdParam, Year: int64(usageDate.Year()), Month: int64(usageDate.Month()), Day: int64(usageDate.Day()), Hour: int64(usageDate.Hour()), BillingPeriod: proto.BillingPeriod_Monthly, GroupBy: proto.UsageGroupBy_GroupByRepository}
	err = helpers.PopulateCacheForTopOrgs(client, input, firstFiveRepoIDs)
	assert.NoError(t, err)
	topRepoUsage := client.GetTopOrgRepoUsageLineItems(customerIdInt, costCenterIdParam, limit, usageDate, proto.BillingPeriod_Monthly, proto.UsageGroupBy_GroupByRepository, nil)
	g.Expect(len(topRepoUsage.TopUsages)).To(gomega.Equal(5))

}
