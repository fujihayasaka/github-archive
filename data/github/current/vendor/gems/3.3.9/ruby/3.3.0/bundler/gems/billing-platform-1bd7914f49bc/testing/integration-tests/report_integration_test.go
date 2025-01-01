//go:build integration
// +build integration

package integrationtests_test

import (
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/onsi/gomega"
)

func Test_UsageReport_Get_Usage_Report_Different_Time_Periods(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	actionsLinuxPricing := client.EnsureSpecificPricingExistsWithUnitType(0.008, "actions_linux", "actions", proto.UnitType_Minutes)
	actionsWindowsPricing := client.EnsureSpecificPricingExistsWithUnitType(0.016, "actions_windows", "actions", proto.UnitType_Minutes)
	actionsStoragePricing := client.EnsureSpecificPricingExistsWithUnitType(0.00003, "actions_storage", "actions", proto.UnitType_Gigabytes)
	actionsMacosPricing := client.EnsureSpecificPricingExistsWithUnitType(0.08, "actions_macos", "actions", proto.UnitType_Minutes)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDateOne := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usageDateTwo := time.Date(2010, 11, 15, 3, 0, 0, 0, time.UTC)

	repoOneId := stubs.GetRandomId64()
	repoTwoId := stubs.GetRandomId64()
	orgOneId := stubs.GetRandomId64()
	orgTwoId := stubs.GetRandomId64()

	// We expect all of these items to be unique and included in the usage report because they have different orgs/repos
	// product/SKUs or usage dates.
	usage1 := stubs.CreateUsageWithOrgRepo("actions_windows", 32.0, customerId, usageDateOne, repoOneId, orgOneId)
	usage2 := stubs.CreateUsageWithOrgRepo("actions_linux", 32.0, customerId, usageDateOne, repoOneId, orgOneId)
	usage3 := stubs.CreateUsageWithOrgRepo("actions_storage", 32.0, customerId, usageDateOne, repoOneId, orgOneId)
	usage4 := stubs.CreateUsageWithOrgRepo("actions_macos", 32.0, customerId, usageDateOne, repoOneId, orgOneId)
	usage5 := stubs.CreateUsageWithOrgRepo("actions_linux", 32.0, customerId, usageDateTwo, repoTwoId, orgTwoId)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))
	client.RunYearlyJob(len(usages))

	usageReport := client.GetUsageReport(customerId, usageDateOne, proto.BillingPeriod_Yearly, false, 0)
	g.Expect(usageReport.ReportItems).Should(gomega.HaveLen(5))

	usageReport = client.GetUsageReport(customerId, usageDateOne, proto.BillingPeriod_Monthly, false, 0)
	g.Expect(usageReport.ReportItems).Should(gomega.HaveLen(5))

	// We expect these items should be sorted by usage date and then sku.
	billingItem := usageReport.ReportItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(32.0))
	g.Expect(billingItem.GrossAmount).Should(gomega.Equal(0.256))
	g.Expect(billingItem.DiscountAmount).Should(gomega.Equal(0.256))
	g.Expect(billingItem.NetAmount).Should(gomega.Equal(0.0))
	g.Expect(billingItem.PricePerUnit).Should(gomega.Equal(0.008))
	g.Expect(billingItem.Sku).Should(gomega.Equal(actionsLinuxPricing.FriendlyName))
	g.Expect(billingItem.Product).Should(gomega.Equal(actionsLinuxPricing.Product))
	g.Expect(billingItem.OrgID).Should(gomega.Equal(orgOneId))
	g.Expect(billingItem.RepoID).Should(gomega.Equal(repoOneId))
	g.Expect(billingItem.UsageDate).Should(gomega.Equal(usageDateOne.Unix()))
	g.Expect(billingItem.UnitTypeString).Should(gomega.Equal(actionsLinuxPricing.UnitType.String()))

	billingItem = usageReport.ReportItems[1]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(32.0))
	g.Expect(billingItem.GrossAmount).Should(gomega.Equal(2.56))
	g.Expect(billingItem.DiscountAmount).Should(gomega.Equal(2.56))
	g.Expect(billingItem.NetAmount).Should(gomega.Equal(0.0))
	g.Expect(billingItem.PricePerUnit).Should(gomega.Equal(0.08))
	g.Expect(billingItem.Sku).Should(gomega.Equal(actionsMacosPricing.FriendlyName))
	g.Expect(billingItem.Product).Should(gomega.Equal(actionsMacosPricing.Product))
	g.Expect(billingItem.OrgID).Should(gomega.Equal(orgOneId))
	g.Expect(billingItem.RepoID).Should(gomega.Equal(repoOneId))
	g.Expect(billingItem.UsageDate).Should(gomega.Equal(usageDateOne.Unix()))
	g.Expect(billingItem.UnitTypeString).Should(gomega.Equal(actionsMacosPricing.UnitType.String()))

	billingItem = usageReport.ReportItems[2]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(32.0))
	g.Expect(billingItem.GrossAmount).Should(gomega.Equal(0.00096))
	g.Expect(billingItem.DiscountAmount).Should(gomega.Equal(0.00096))
	g.Expect(billingItem.NetAmount).Should(gomega.Equal(0.0))
	g.Expect(billingItem.PricePerUnit).Should(gomega.Equal(0.00003))
	g.Expect(billingItem.Sku).Should(gomega.Equal(actionsStoragePricing.FriendlyName))
	g.Expect(billingItem.Product).Should(gomega.Equal(actionsStoragePricing.Product))
	g.Expect(billingItem.OrgID).Should(gomega.Equal(orgOneId))
	g.Expect(billingItem.RepoID).Should(gomega.Equal(repoOneId))
	g.Expect(billingItem.UsageDate).Should(gomega.Equal(usageDateOne.Unix()))
	g.Expect(billingItem.UnitTypeString).Should(gomega.Equal(actionsStoragePricing.UnitType.String()))

	billingItem = usageReport.ReportItems[3]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(32.0))
	g.Expect(billingItem.GrossAmount).Should(gomega.Equal(0.512))
	g.Expect(billingItem.DiscountAmount).Should(gomega.Equal(0.512))
	g.Expect(billingItem.NetAmount).Should(gomega.Equal(0.0))
	g.Expect(billingItem.PricePerUnit).Should(gomega.Equal(0.016))
	g.Expect(billingItem.Sku).Should(gomega.Equal(actionsWindowsPricing.FriendlyName))
	g.Expect(billingItem.Product).Should(gomega.Equal(actionsWindowsPricing.Product))
	g.Expect(billingItem.OrgID).Should(gomega.Equal(orgOneId))
	g.Expect(billingItem.RepoID).Should(gomega.Equal(repoOneId))
	g.Expect(billingItem.UsageDate).Should(gomega.Equal(usageDateOne.Unix()))
	g.Expect(billingItem.UnitTypeString).Should(gomega.Equal(actionsWindowsPricing.UnitType.String()))

	billingItem = usageReport.ReportItems[4]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(32.0))
	g.Expect(billingItem.GrossAmount).Should(gomega.Equal(0.256))
	g.Expect(billingItem.DiscountAmount).Should(gomega.Equal(0.256))
	g.Expect(billingItem.NetAmount).Should(gomega.Equal(0.0))
	g.Expect(billingItem.PricePerUnit).Should(gomega.Equal(0.008))
	g.Expect(billingItem.Sku).Should(gomega.Equal(actionsLinuxPricing.FriendlyName))
	g.Expect(billingItem.Product).Should(gomega.Equal(actionsLinuxPricing.Product))
	g.Expect(billingItem.OrgID).Should(gomega.Equal(orgTwoId))
	g.Expect(billingItem.RepoID).Should(gomega.Equal(repoTwoId))
	g.Expect(billingItem.UsageDate).Should(gomega.Equal(usageDateTwo.Unix()))
	g.Expect(billingItem.UnitTypeString).Should(gomega.Equal(actionsLinuxPricing.UnitType.String()))

	usageReport = client.GetUsageReport(customerId, usageDateOne, proto.BillingPeriod_Daily, false, 0)
	g.Expect(usageReport.ReportItems).Should(gomega.HaveLen(4))

	usageReport = client.GetUsageReport(customerId, usageDateTwo, proto.BillingPeriod_Daily, false, 0)
	g.Expect(usageReport.ReportItems).Should(gomega.HaveLen(1))

	billingItem = usageReport.ReportItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(32.0))
	g.Expect(billingItem.GrossAmount).Should(gomega.Equal(0.256))
	g.Expect(billingItem.DiscountAmount).Should(gomega.Equal(0.256))
	g.Expect(billingItem.NetAmount).Should(gomega.Equal(0.0))
	g.Expect(billingItem.PricePerUnit).Should(gomega.Equal(0.008))
	g.Expect(billingItem.Sku).Should(gomega.Equal(actionsLinuxPricing.FriendlyName))
	g.Expect(billingItem.Product).Should(gomega.Equal(actionsLinuxPricing.Product))
	g.Expect(billingItem.OrgID).Should(gomega.Equal(orgTwoId))
	g.Expect(billingItem.RepoID).Should(gomega.Equal(repoTwoId))
	g.Expect(billingItem.UsageDate).Should(gomega.Equal(usageDateTwo.Unix()))
	g.Expect(billingItem.UnitTypeString).Should(gomega.Equal(actionsLinuxPricing.UnitType.String()))

	usageReport = client.GetUsageReport(customerId, usageDateOne, proto.BillingPeriod_Hourly, false, 0)
	g.Expect(usageReport.ReportItems).Should(gomega.HaveLen(4))
}

func Test_UsageReport_Get_Usage_Report_For_Org(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	client.EnsureSpecificPricingExistsWithUnitType(0.008, "actions_linux", "actions", proto.UnitType_Minutes)
	client.EnsureSpecificPricingExistsWithUnitType(0.016, "actions_windows", "actions", proto.UnitType_Minutes)
	client.EnsureSpecificPricingExistsWithUnitType(0.00003, "actions_storage", "actions", proto.UnitType_Gigabytes)
	client.EnsureSpecificPricingExistsWithUnitType(0.08, "actions_macos", "actions", proto.UnitType_Minutes)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDateOne := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usageDateTwo := time.Date(2010, 11, 15, 3, 0, 0, 0, time.UTC)

	repoOneId := stubs.GetRandomId64()
	repoTwoId := stubs.GetRandomId64()
	orgOneId := stubs.GetRandomId64()
	orgTwoId := stubs.GetRandomId64()

	// We expect all of these items to be unique and included in the usage report because they have different orgs/repos
	// product/SKUs or usage dates.
	usage1 := stubs.CreateUsageWithOrgRepo("actions_windows", 32.0, customerId, usageDateOne, repoOneId, orgOneId)
	usage2 := stubs.CreateUsageWithOrgRepo("actions_linux", 32.0, customerId, usageDateOne, repoOneId, orgOneId)
	usage3 := stubs.CreateUsageWithOrgRepo("actions_storage", 32.0, customerId, usageDateOne, repoOneId, orgOneId)
	usage4 := stubs.CreateUsageWithOrgRepo("actions_macos", 32.0, customerId, usageDateOne, repoOneId, orgOneId)
	usage5 := stubs.CreateUsageWithOrgRepo("actions_linux", 32.0, customerId, usageDateTwo, repoTwoId, orgTwoId)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))
	client.RunYearlyJob(len(usages))

	usageReport := client.GetUsageReport(customerId, usageDateOne, proto.BillingPeriod_Yearly, false, 0)
	g.Expect(usageReport.ReportItems).Should(gomega.HaveLen(5))

	usageReport = client.GetUsageReport(customerId, usageDateOne, proto.BillingPeriod_Yearly, false, orgOneId)
	g.Expect(usageReport.ReportItems).Should(gomega.HaveLen(4))
	billingItem := usageReport.ReportItems[0]
	g.Expect(billingItem.OrgID).Should(gomega.Equal(orgOneId))

	usageReport = client.GetUsageReport(customerId, usageDateTwo, proto.BillingPeriod_Yearly, false, orgTwoId)
	g.Expect(usageReport.ReportItems).Should(gomega.HaveLen(1))
	billingItem = usageReport.ReportItems[0]
	g.Expect(billingItem.OrgID).Should(gomega.Equal(orgTwoId))
}

func Test_UsageReport_Get_Usage_Report_Cost_Centers(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	actionsLinuxPricing := client.EnsureSpecificPricingExistsWithUnitType(0.008, "actions_linux", "actions", proto.UnitType_Minutes)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Azure)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	// create cost center specific usage
	entity := &proto.EntityDetail{
		CustomerId: customerId,
		OwnerId:    stubs.GetRandomId64(),
		RepoId:     stubs.GetRandomId64(),
		ActorId:    stubs.GetRandomId64(),
	}
	costCenterName := "Test Cost Center"
	costCenter := stubs.CreateCostCenterWithAll(customerId, proto.CostCenterType_AzureSubscription, false, costCenterName, []*proto.Resource{})
	response, _ := client.CreateCostCenter(costCenter)
	costCenterKey := response.CostCenter.CostCenterKey
	resource := stubs.GetResource(entity, proto.ResourceType_Org)
	_, err := client.CostCenterAddResourceTo(costCenterKey, []*proto.Resource{resource})
	g.Expect(err).ToNot(gomega.HaveOccurred())

	quantity := 32.0

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsageFrom(actionsLinuxPricing, entity, usageDate, quantity)

	usages := []*hydroSchema.Usage{usage1}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))

	u := client.GetUsageReport(costCenterKey.Uuid, usageDate, proto.BillingPeriod_Daily, false, 0)

	billingItem := u.ReportItems[0]
	g.Expect(u.ReportItems).Should(gomega.HaveLen(1))
	g.Expect(costCenterKey.Uuid).ShouldNot(gomega.BeEmpty())
	g.Expect(billingItem.Quantity).Should(gomega.Equal(32.0))
	g.Expect(billingItem.GrossAmount).Should(gomega.Equal(0.256))
	g.Expect(billingItem.DiscountAmount).Should(gomega.Equal(0.256))
	g.Expect(billingItem.NetAmount).Should(gomega.Equal(0.0))
	g.Expect(billingItem.PricePerUnit).Should(gomega.Equal(0.008))
	g.Expect(billingItem.Sku).Should(gomega.Equal(actionsLinuxPricing.FriendlyName))
	g.Expect(billingItem.Product).Should(gomega.Equal(actionsLinuxPricing.Product))
	g.Expect(billingItem.OrgID).Should(gomega.Equal(usage1.Entity.OrganizationId))
	g.Expect(billingItem.RepoID).Should(gomega.Equal(usage1.Entity.RepoId))
	g.Expect(billingItem.UsageDate).Should(gomega.Equal(usageDate.Unix()))
	g.Expect(billingItem.UnitTypeString).Should(gomega.Equal(actionsLinuxPricing.UnitType.String()))
	g.Expect(billingItem.CostCenterName).Should(gomega.Equal(""))
}

func Test_UsageReport_Get_Usage_Report_Include_Cost_Centers(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	actionsLinuxPricing := client.EnsureSpecificPricingExistsWithUnitType(0.008, "actions_linux", "actions", proto.UnitType_Minutes)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Azure)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	// create cost center specific usage
	entity := &proto.EntityDetail{
		CustomerId: customerId,
		OwnerId:    stubs.GetRandomId64(),
		RepoId:     stubs.GetRandomId64(),
		ActorId:    stubs.GetRandomId64(),
	}
	costCenterName := "Test Cost Center"
	costCenter := stubs.CreateCostCenterWithAll(customerId, proto.CostCenterType_AzureSubscription, false, costCenterName, []*proto.Resource{})
	response, _ := client.CreateCostCenter(costCenter)
	costCenterKey := response.CostCenter.CostCenterKey
	resource := stubs.GetResource(entity, proto.ResourceType_Org)
	_, err := client.CostCenterAddResourceTo(costCenterKey, []*proto.Resource{resource})
	g.Expect(err).ToNot(gomega.HaveOccurred())

	quantity := 32.0

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsageFrom(actionsLinuxPricing, entity, usageDate, quantity)

	usages := []*hydroSchema.Usage{usage1}
	client.ProduceMeteredUsage(usages)

	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))

	u := client.GetUsageReport(customerId, usageDate, proto.BillingPeriod_Daily, true, 0)

	billingItem := u.ReportItems[0]
	g.Expect(u.ReportItems).Should(gomega.HaveLen(1))
	g.Expect(costCenterKey.Uuid).ShouldNot(gomega.BeEmpty())
	g.Expect(billingItem.Quantity).Should(gomega.Equal(32.0))
	g.Expect(billingItem.GrossAmount).Should(gomega.Equal(0.256))
	g.Expect(billingItem.DiscountAmount).Should(gomega.Equal(0.256))
	g.Expect(billingItem.NetAmount).Should(gomega.Equal(0.0))
	g.Expect(billingItem.PricePerUnit).Should(gomega.Equal(0.008))
	g.Expect(billingItem.Sku).Should(gomega.Equal(actionsLinuxPricing.FriendlyName))
	g.Expect(billingItem.Product).Should(gomega.Equal(actionsLinuxPricing.Product))
	g.Expect(billingItem.OrgID).Should(gomega.Equal(usage1.Entity.OrganizationId))
	g.Expect(billingItem.RepoID).Should(gomega.Equal(usage1.Entity.RepoId))
	g.Expect(billingItem.UsageDate).Should(gomega.Equal(usageDate.Unix()))
	g.Expect(billingItem.UnitTypeString).Should(gomega.Equal(actionsLinuxPricing.UnitType.String()))
	g.Expect(billingItem.CostCenterName).Should(gomega.Equal(costCenterName))
}
