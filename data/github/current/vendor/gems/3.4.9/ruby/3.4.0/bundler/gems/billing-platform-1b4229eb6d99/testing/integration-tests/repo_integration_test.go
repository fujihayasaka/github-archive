//go:build integration
// +build integration

package integrationtests_test

import (
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/lib/twirp/proto"
	a "github.com/github/billing-platform/testing/assertions"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
)

func Test_Repo_When_Rollups_Are_Run_Two_Usages_Are_Recorded_In_A_Given_Hour_For_Repo(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureRandomPricingExists()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 32.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usages := []*hydroSchema.Usage{usage1, usage2}
	// produce message
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))

	u := client.GetUsageTotalByRepo(usage1.Entity.RepoId, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(u.Quantity).Should(gomega.Equal(64.0))
}

func Test_Repo_When_Rollups_Are_Run_A_Single_Usage_Is_Recorded_For_A_Given_Repo(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureRandomPricingExists()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 32.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1}
	// produce messages
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	matchingOnAmounts := func(quantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Quantity == quantity
		}
	}

	client.RunDailyJob(len(usages))

	u := client.GetOrgRepoUsageLineItems(0, usage1.Entity.RepoId, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity)))

	client.RunMonthlyJob(len(usages))

	u = client.GetOrgRepoUsageLineItems(0, usage1.Entity.RepoId, customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity)))

	client.RunYearlyJob(len(usages))

	u = client.GetOrgRepoUsageLineItems(0, usage1.Entity.RepoId, customerId, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity)))
}

func Test_Repo_When_Rollups_Are_Run_A_Single_Usage_Is_Recorded_For_A_Given_Org(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureRandomPricingExists()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 33.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1}
	// produce message
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	matchingOnAmounts := func(quantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Quantity == quantity
		}
	}

	client.RunDailyJob(len(usages))

	u := client.GetOrgRepoUsageLineItems(usage1.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity)))

	client.RunMonthlyJob(len(usages))

	u = client.GetOrgRepoUsageLineItems(usage1.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity)))

	client.RunYearlyJob(len(usages))

	u = client.GetOrgRepoUsageLineItems(usage1.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity)))
}

func Test_Repo_When_A_Usage_Is_Recorded_Repo_Usage_Are_Retrievalable_Via_Usage_By_Repo(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	price := 0.5
	pricing := client.EnsureSpecificPricingExists(price, "product-1_sku-1", "product-1", "Product 1 SKU 1")
	quantity := 32.0

	// produce message
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{pricing.Product}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)

	usages := []*hydroSchema.Usage{usage1}
	// produce message
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))

	u := client.GetUsageByRepo(customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(u.RepoUsages[0].Quantity).Should(gomega.Equal(usage1.Quantity), "usage from daily bucket from final total")

	client.RunMonthlyJob(len(usages))

	u = client.GetUsageByRepo(customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(u.RepoUsages[0].Quantity).Should(gomega.Equal(usage1.Quantity), "usage from monthly bucket from final total")

	client.RunYearlyJob(len(usages))

	u = client.GetUsageByRepo(customerId, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(u.RepoUsages[0].Quantity).Should(gomega.Equal(usage1.Quantity), "usage from monthly bucket from final total")
}

func Test_Repo_When_Rollups_Are_Run_Two_Usages_Are_Recorded_For_Same_Repo(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureRandomPricingExists()
	quantity := 32.0

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity+1, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usages := []*hydroSchema.Usage{usage1, usage2}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))

	u := client.GetUsageByRepo(customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(u.RepoUsages[0].Quantity).Should(gomega.Equal(usage1.Quantity+usage2.Quantity), "usage from daily bucket from final total")

	client.RunMonthlyJob(len(usages))

	u = client.GetUsageByRepo(customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(u.RepoUsages[0].Quantity).Should(gomega.Equal(usage1.Quantity+usage2.Quantity), "usage from monthly bucket from final total")

	client.RunYearlyJob(len(usages))

	u = client.GetUsageByRepo(customerId, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(u.RepoUsages[0].Quantity).Should(gomega.Equal(usage1.Quantity+usage2.Quantity), "usage from monthly bucket from final total")
}

func Test_Repo_When_Rollups_Are_Run_Two_Usages_Are_Recorded_In_A_Given_Hour_Different_Repos(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureRandomPricingExists()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 30.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 32, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), 33, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usageDate2 := time.Date(2010, 11, 14, 5, 0, 0, 0, time.UTC)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 34, customerId, usageDate2)
	// Same org as the one from usage1, usage 3
	usage4 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), 35, customerId, usageDate2, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usageDate3 := time.Date(2010, 11, 15, 4, 0, 0, 0, time.UTC)
	usage5 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity+4, customerId, usageDate3)
	usage6 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity+5, customerId, usageDate3, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5, usage6}

	matchingOnAmounts := func(quantity float64) func(*proto.RepoUsage) bool {
		return func(item *proto.RepoUsage) bool {
			return item.Quantity == quantity
		}
	}
	// produce message
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))

	u := client.GetUsageByRepo(customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(u.RepoUsages).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity + usage2.Quantity)))
	g.Expect(u.RepoUsages).Should(a.IncludeItem(matchingOnAmounts(usage3.Quantity)))
	g.Expect(u.RepoUsages).Should(a.IncludeItem(matchingOnAmounts(usage4.Quantity)))

	u = client.GetUsageByRepo(customerId, usageDate3, proto.BillingPeriod_Daily)
	g.Expect(u.RepoUsages).Should(a.IncludeItem(matchingOnAmounts(usage5.Quantity)))
	g.Expect(u.RepoUsages).Should(a.IncludeItem(matchingOnAmounts(usage6.Quantity)))

	client.RunMonthlyJob(len(usages))

	u = client.GetUsageByRepo(customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(u.RepoUsages).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity + usage2.Quantity + usage4.Quantity)))
	g.Expect(u.RepoUsages).Should(a.IncludeItem(matchingOnAmounts(usage3.Quantity)))
	g.Expect(u.RepoUsages).Should(a.IncludeItem(matchingOnAmounts(usage5.Quantity)))
	g.Expect(u.RepoUsages).Should(a.IncludeItem(matchingOnAmounts(usage6.Quantity)))

	client.RunYearlyJob(len(usages))

	u = client.GetUsageByRepo(customerId, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(u.RepoUsages).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity + usage2.Quantity + usage4.Quantity + usage6.Quantity)))
	g.Expect(u.RepoUsages).Should(a.IncludeItem(matchingOnAmounts(usage3.Quantity)))
	g.Expect(u.RepoUsages).Should(a.IncludeItem(matchingOnAmounts(usage5.Quantity)))
}

func Test_Repo_When_Rollups_Are_Run_Two_Usages_Are_Recorded_In_A_Given_Hour_Different_Orgs(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureRandomPricingExists()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 30.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 32, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), 33, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usageDate2 := time.Date(2010, 11, 14, 5, 0, 0, 0, time.UTC)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 34, customerId, usageDate2)
	// Same org as the one from usage1, usage 3
	usage4 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), 35, customerId, usageDate2, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usageDate3 := time.Date(2010, 11, 15, 4, 0, 0, 0, time.UTC)
	usage5 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity+4, customerId, usageDate3)
	usage6 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity+5, customerId, usageDate3, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5, usage6}

	matchingOnAmounts := func(quantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Quantity == quantity
		}
	}
	// produce message
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))

	u := client.GetOrgRepoUsageLineItems(usage1.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity + usage2.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage4.Quantity)))
	u = client.GetOrgRepoUsageLineItems(usage3.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage3.Quantity)))
	u = client.GetOrgRepoUsageLineItems(usage1.Entity.OrganizationId, 0, customerId, usageDate3, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage6.Quantity)))
	u = client.GetOrgRepoUsageLineItems(usage5.Entity.OrganizationId, 0, customerId, usageDate3, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage5.Quantity)))

	client.RunMonthlyJob(len(usages))
	u = client.GetOrgRepoUsageLineItems(usage1.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity + usage2.Quantity + usage4.Quantity)))
	u = client.GetOrgRepoUsageLineItems(usage3.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage3.Quantity)))
	u = client.GetOrgRepoUsageLineItems(usage5.Entity.OrganizationId, 0, customerId, usageDate3, proto.BillingPeriod_Monthly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage5.Quantity)))
	u = client.GetOrgRepoUsageLineItems(usage1.Entity.OrganizationId, 0, customerId, usageDate3, proto.BillingPeriod_Monthly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage6.Quantity)))

	client.RunYearlyJob(len(usages))
	u = client.GetOrgRepoUsageLineItems(usage1.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity + usage2.Quantity + usage4.Quantity + usage6.Quantity)))
	u = client.GetOrgRepoUsageLineItems(usage3.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage3.Quantity)))
	u = client.GetOrgRepoUsageLineItems(usage5.Entity.OrganizationId, 0, customerId, usageDate3, proto.BillingPeriod_Yearly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage5.Quantity)))
}

func Test_Repo_When_Rollups_Are_Run_Line_Items_Are_Recorded_For_Repo_Sku_Partition_Same_Org_And_Repo_Usage(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	price := 0.5
	pricing1 := client.EnsureSpecificPricingExists(price, "product-1_sku-1", "product-1", "Product 1 SKU 1")
	pricing2 := client.EnsureSpecificPricingExists(price, "product-1_sku-2", "product-1", "Product 1 SKU 2")

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"product-1"}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 32.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, quantity, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing2.Sku, quantity+1, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usage3 := stubs.CreateUsageWithOrgRepo(pricing2.Sku, quantity+2, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	// produce message
	usages := []*hydroSchema.Usage{usage1, usage2, usage3}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	matchingOnAmountsAndSkus := func(sku string, quantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Sku == sku && item.Quantity == quantity
		}
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////
	// Test for <customerId>:repo:<repoId>:<usageDate>:byProductSku>  ///////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////

	client.RunDailyJob(len(usages))

	u := client.GetOrgRepoUsageLineItems(0, usage1.Entity.RepoId, customerId, usageDate, proto.BillingPeriod_Daily)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(2), "usage from daily bucket from final total")

	u = client.GetOrgRepoUsageLineItemsGroupBy(0, usage1.Entity.RepoId, customerId, usageDate, proto.BillingPeriod_Daily, proto.UsageGroupBy_GroupBySku)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage1.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-2", usage2.Quantity+usage3.Quantity)))

	client.RunMonthlyJob(len(usages))
	u = client.GetOrgRepoUsageLineItemsGroupBy(0, usage1.Entity.RepoId, customerId, usageDate, proto.BillingPeriod_Monthly, proto.UsageGroupBy_GroupBySku)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage1.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-2", usage2.Quantity+usage3.Quantity)))

	client.RunYearlyJob(len(usages))
	u = client.GetOrgRepoUsageLineItemsGroupBy(0, usage1.Entity.RepoId, customerId, usageDate, proto.BillingPeriod_Yearly, proto.UsageGroupBy_GroupBySku)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage1.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-2", usage2.Quantity+usage3.Quantity)))

	////////////////////////////////////////////////////////////////////////////////////////////////////
	// Expect same results if we query by org i.e. <customerId>:org:<orgId>:<usageDate>:byProductSku////
	////////////////////////////////////////////////////////////////////////////////////////////////////

	u = client.GetOrgRepoUsageLineItemsGroupBy(usage1.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Daily, proto.UsageGroupBy_GroupBySku)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage1.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-2", usage2.Quantity+usage3.Quantity)))

	u = client.GetOrgRepoUsageLineItemsGroupBy(usage1.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Monthly, proto.UsageGroupBy_GroupBySku)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage1.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-2", usage2.Quantity+usage3.Quantity)))

	u = client.GetOrgRepoUsageLineItemsGroupBy(usage1.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Yearly, proto.UsageGroupBy_GroupBySku)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage1.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-2", usage2.Quantity+usage3.Quantity)))
}

func Test_Repo_When_RollupsAreRun_Line_Items_Are_Recorded_For_Repo_Sku_Partition_Different_Entities(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	price1 := 0.5
	price2 := 1.0
	pricing1 := client.EnsureSpecificPricingExists(price1, "product-1_sku-1", "product-1", "Product 1 SKU 1")
	pricing2 := client.EnsureSpecificPricingExists(price2, "product-1_sku-2", "product-1", "Product 1 SKU 2")

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"product-1"}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 32.0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 32, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing2.Sku, 33, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usageDate2 := time.Date(2010, 11, 14, 5, 0, 0, 0, time.UTC)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 34, customerId, usageDate2)
	// Same org as the one from usage1, usage 3
	usage4 := stubs.CreateUsageWithOrgRepo(pricing1.Sku, 35, customerId, usageDate2, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usageDate3 := time.Date(2010, 11, 15, 4, 0, 0, 0, time.UTC)
	usage5 := stubs.CreateUsageWithOrgRepo(pricing2.Sku, quantity+4, customerId, usageDate3, usage3.Entity.RepoId, usage3.Entity.OrganizationId)
	usage6 := stubs.CreateUsageWithOrgRepo(pricing2.Sku, quantity+5, customerId, usageDate3, usage1.Entity.RepoId, usage1.Entity.OrganizationId)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5, usage6}

	matchingOnAmountsAndSkus := func(sku string, quantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Sku == sku && item.Quantity == quantity
		}
	}
	// produce message
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))

	////////////////////////////////////////////////////////////////////////////////////////////////////
	// Test for <customerId>:repo:<repoId>:<usageDate>:byProductSku>  ///////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////

	// Repo from usage1.Entity.RepoId
	client.RunDailyJob(len(usages))
	u := client.GetOrgRepoUsageLineItemsGroupBy(0, usage1.Entity.RepoId, customerId, usageDate, proto.BillingPeriod_Daily, proto.UsageGroupBy_GroupBySku)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage1.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-2", usage2.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage4.Quantity)))

	client.RunMonthlyJob(len(usages))
	u = client.GetOrgRepoUsageLineItemsGroupBy(0, usage1.Entity.RepoId, customerId, usageDate, proto.BillingPeriod_Monthly, proto.UsageGroupBy_GroupBySku)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage1.Quantity+usage4.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-2", usage2.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-2", usage6.Quantity)))

	client.RunYearlyJob(len(usages))
	u = client.GetOrgRepoUsageLineItemsGroupBy(0, usage1.Entity.RepoId, customerId, usageDate, proto.BillingPeriod_Yearly, proto.UsageGroupBy_GroupBySku)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage1.Quantity+usage4.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-2", usage2.Quantity+usage6.Quantity)))

	// ////////////////////////////////////////////////////////////////////////////////////////////////////
	// //Expect same results if we query by org i.e. <customerId>:org:<orgId>:<usageDate>:byProductSku////
	// ////////////////////////////////////////////////////////////////////////////////////////////////////

	// Org from usage3.Entity.OrganizationId
	u = client.GetOrgRepoUsageLineItemsGroupBy(usage3.Entity.OrganizationId, 0, customerId, usageDate2, proto.BillingPeriod_Daily, proto.UsageGroupBy_GroupBySku)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage3.Quantity)))

	u = client.GetOrgRepoUsageLineItemsGroupBy(usage3.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Monthly, proto.UsageGroupBy_GroupBySku)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage3.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-2", usage5.Quantity)))

	u = client.GetOrgRepoUsageLineItemsGroupBy(usage3.Entity.OrganizationId, 0, customerId, usageDate, proto.BillingPeriod_Yearly, proto.UsageGroupBy_GroupBySku)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-1", usage3.Quantity)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmountsAndSkus("product-1_sku-2", usage5.Quantity)))
}
