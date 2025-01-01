//go:build integration
// +build integration

package integrationtests_test

import (
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	a "github.com/github/billing-platform/testing/assertions"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
)

func Test_Watermark_ProcessingWatermarkUsageThatsAlreadyBeenProcessed(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(1).Time
	then := january2021.WithDay(1).Time

	// Always use beginning of day to make quantity deterministic
	usage1Params := stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   quantity,
		UsageAt:    then,
		CustomerId: customerId,
		RepoId:     stubs.GetRandomId64(),
		ActorId:    stubs.GetRandomId64(),
	}
	usage1, err := usage1Params.ToUsage()
	g.Expect(err).Should(gomega.BeNil())

	usages := []*hydroSchema.Usage{usage1, usage1}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))

	events := client.GetUsageEventItems("", pricing.GetSku(), customerId, now, proto.BillingPeriod_Hourly)
	g.Expect(len(events.BillingItems)).Should(gomega.Equal(1))
}

func Test_Watermark_Watermark_Single_Usage(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(1).Time
	then := january2021.WithDay(1).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, then)
	usages := []*hydroSchema.Usage{usage1}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_Two_Usages_With_Different_SKUs(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing1 := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	pricing2 := client.EnsureSpecificPricingExistsWithAll(0.0008, "git_lfs_storage", "git_lfs", proto.PricingMeterType_PerHourUnitCharge, "Git LFS Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(1).Time
	then := january2021.WithDay(1).Time

	// Always use beginning of day to make quantity deterministic
	repoId := stubs.GetRandomId64()
	orgId := stubs.GetRandomId64()
	usage1 := stubs.CreateUsageWithOrgRepo(pricing1.Sku, quantity, customerId, then, repoId, orgId)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing2.Sku, quantity, customerId, then, repoId, orgId)
	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	g.Expect(len(u.BillingItems)).Should(gomega.Equal(2))

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * pricing1.Price))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing1.Price))
}

func Test_Watermark_Watermark_With_Multiple_Usage_Across_Days(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(3).WithHour(1).Time
	then := january2021.WithDay(1).Time
	thenNextDay := january2021.WithDay(2).Time

	// Always use beginning of day to make quantity deterministic
	usageDate := time.Date(then.Year(), then.Month(), then.Day(), 0, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity, customerId, thenNextDay, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity * 2))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * 2 * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_With_Multiple_Usage_Across_Months(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	endOfJanuary2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January).WithDay(31).WithHour(23)
	startOfFebruary2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.February).WithDay(1).WithHour(0)

	// Always use beginning of day to make quantity deterministic
	usageDate := time.Date(endOfJanuary2021.Year(), endOfJanuary2021.Month(), endOfJanuary2021.Day(), 0, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity, customerId, startOfFebruary2021.Time, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProcessWatermarkUsage(startOfFebruary2021.Time, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, startOfFebruary2021.Time, proto.BillingPeriod_Daily)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(1), "line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(2.0))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(2.0 * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_Persist_Usage_Across_Months_No_New_Events(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	endOfJanuary2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January).WithDay(31).WithHour(23)
	startOfFebruary2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.February).WithDay(1).WithHour(0)

	// Always use beginning of day to make quantity deterministic
	usageDate := time.Date(endOfJanuary2021.Year(), endOfJanuary2021.Month(), endOfJanuary2021.Day(), 0, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)
	usages := []*hydroSchema.Usage{usage1}

	client.ProcessWatermarkUsage(startOfFebruary2021.Time, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, startOfFebruary2021.Time, proto.BillingPeriod_Daily)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(1), "line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(1.0))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(1.0 * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_With_Multiple_Usage_Across_Years(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	endOf2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.December).WithDay(31).WithHour(23)
	startOf2022 := models.NewUsageTime().WithYear(2022).WithMonth(time.January).WithDay(1).WithHour(0)

	// Always use beginning of day to make quantity deterministic
	usageDate := time.Date(endOf2021.Year(), endOf2021.Month(), endOf2021.Day(), 0, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, usageDate)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), quantity, customerId, startOf2022.Time, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProcessWatermarkUsage(startOf2022.Time, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, startOf2022.Time, proto.BillingPeriod_Daily)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(1), "line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(2.0))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(2.0 * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_With_2_Different_Customers(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto1 := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto1.CustomerId
	_ = client.CreateCustomer(customerProto1)

	customerProto2 := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId2 := customerProto2.CustomerId
	_ = client.CreateCustomer(customerProto2)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(1).Time
	then := january2021.WithDay(1).Time

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, then)

	// different customer
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId2, then)
	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	u2 := client.GetUsageLineItems("", "", customerId2, now, proto.BillingPeriod_Daily)
	g.Expect(u2.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should not be created yet")

	billingItem := u.BillingItems[0]
	billingItem2 := u2.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity))
	g.Expect(billingItem2.Quantity).Should(gomega.Equal(quantity))

	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * pricing.GetPrice()))
	g.Expect(billingItem2.BilledAmount).Should(gomega.Equal(quantity * pricing.GetPrice()))

	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
	g.Expect(billingItem2.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_Half_Hour_Usage(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(1).Time
	then := january2021.WithDay(1).WithMinute(30).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, then)
	usages := []*hydroSchema.Usage{usage1}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	billingItem := u.BillingItems[0]

	// 30 min / 60 min = 0.5 which equals a daily quantity of 23.5 hours
	// 23.5 / 24  * 1 GiB usage = 0.979166666 GiB-Hours
	g.Expect(billingItem.Quantity).Should(gomega.Equal(0.979166666))
	g.Expect(billingItem.BilledAmount).Should(gomega.BeNumerically("~", 0.979166666*pricing.GetPrice(), 0.0001))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_Different_Org(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(2).Time
	then := january2021.WithDay(1).Time
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 49, customerId, then)
	newEntity := &hydroSchemaEntities.EntityDetail{
		CustomerId:     usage1.Entity.CustomerId,
		RepoId:         usage1.Entity.RepoId,
		ActorId:        usage1.Entity.ActorId,
		OrganizationId: stubs.GetRandomId64(),
	}
	usage2 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.GetSku(), 55, then, newEntity)

	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})

	// Fetch the line item for partial hour of usage
	u := client.GetUsageLineItemsGroupBy("", "", customerId, now, proto.BillingPeriod_Hourly, proto.UsageGroupBy_GroupByOrgRepoProductSku)
	client.RunDailyJob(len(usages))
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")
	g.Expect(u.BillingItems).Should(gomega.HaveLen(2))
	matchingOnAmounts := func(quantity float64, billedAmount float64, appliedCostPerQuantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Quantity == quantity && item.BilledAmount == billedAmount && item.AppliedCostPerQuantity == appliedCostPerQuantity
		}
	}
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(49, 0.392, 0.008)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(55, 0.44, 0.008)))
}

func Test_Watermark_Watermark_Same_Repo(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(2).Time
	then := january2021.WithDay(1).Time
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 49, customerId, then)
	entity := usage1.Entity
	usage2 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.GetSku(), 50, then, entity)
	usage3 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing.GetSku(), 55, then, entity)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3}
	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})

	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")
	g.Expect(u.BillingItems).Should(gomega.HaveLen(1))
	g.Expect(u.BillingItems[0].Quantity).Should(gomega.Equal(154.0))
	g.Expect(u.BillingItems[0].BilledAmount).Should(gomega.Equal(154 * pricing.GetPrice()))
	g.Expect(u.BillingItems[0].AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_Different_Repo(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(1).Time
	then := january2021.WithDay(1).Time

	// Always use beginning of day to make quantity deterministic
	usageDate := time.Date(then.Year(), then.Month(), then.Day(), 0, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 49, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 30, customerId, usageDate)

	// usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4}
	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})

	// Fetch the line item for partial hour of usage
	u := client.GetUsageLineItemsGroupBy("", "", customerId, now, proto.BillingPeriod_Hourly, proto.UsageGroupBy_GroupByOrgRepoProductSku)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")
	g.Expect(u.BillingItems).Should(gomega.HaveLen(2))
	matchingOnAmounts := func(quantity float64, billedAmount float64, appliedCostPerQuantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Quantity == quantity && item.BilledAmount == billedAmount && item.AppliedCostPerQuantity == appliedCostPerQuantity
		}
	}
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity, 49.0*pricing.GetPrice(), pricing.GetPrice())))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage2.Quantity, 30.0*pricing.GetPrice(), pricing.GetPrice())))
}

func Test_Watermark_Watermark_Different_Repo_Multiple_Usages(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)

	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(3).WithHour(1).Time
	then := january2021.WithDay(1).Time

	// Always use beginning of day to make quantity deterministic
	usageDate := time.Date(then.Year(), then.Month(), then.Day(), 0, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 49, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 30, customerId, usageDate)
	usage3 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), 30, customerId, usageDate, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usage4 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), 30, customerId, usageDate, usage2.Entity.RepoId, usage2.Entity.OrganizationId)

	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})

	// Fetch the line item for partial hour of usage
	u := client.GetUsageLineItemsGroupBy("", "", customerId, now, proto.BillingPeriod_Hourly, proto.UsageGroupBy_GroupByOrgRepoProductSku)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")
	g.Expect(u.BillingItems).Should(gomega.HaveLen(2))
	matchingOnAmounts := func(quantity float64, billedAmount float64, appliedCostPerQuantity float64) func(*proto.BillingItem) bool {
		return func(item *proto.BillingItem) bool {
			return item.Quantity == quantity && item.BilledAmount == billedAmount && item.AppliedCostPerQuantity == appliedCostPerQuantity
		}
	}
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage1.Quantity+usage3.Quantity, 79.0*pricing.GetPrice(), pricing.GetPrice())))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(usage2.Quantity+usage4.Quantity, 60.0*pricing.GetPrice(), pricing.GetPrice())))
}

func Test_Watermark_Watermark_Half_Hour_Usage_Fetched_Next_Day(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(2).WithHour(1).Time
	then := january2021.WithDay(1).WithMinute(30).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, then)
	usages := []*hydroSchema.Usage{usage1}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_Half_Hour_Usage_Fetched_Next_Day_Hour_Zero(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(2).WithHour(0).Time
	then := january2021.WithDay(1).WithHour(12).WithMinute(30).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, then)
	usages := []*hydroSchema.Usage{usage1}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	// Fetch the line item for partial hour of usage
	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	billingItem := u.BillingItems[0]
	// 0.5 GiB-Hours for the half hour and 11 GiB-Hours for remaining time left in the day
	// 0.958333333 GiB-Hours * 12 hours = 11.5 GiB-Hours
	g.Expect(billingItem.Quantity).Should(gomega.Equal(0.958333333))
	g.Expect(billingItem.BilledAmount).Should(gomega.BeNumerically("~", 0.958333333*pricing.GetPrice(), 0.0001))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_Skips_Negative_Line_Items(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := -1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(1).Time
	then := january2021.WithDay(1).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, then)
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.ScheduleWatermarkJobs(now, pricing.GetSku())
	client.RunRequestHandler(1)
	client.RunWatermarkHandler(1)
	client.RunUsageIngestion(1)

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Hourly)
	g.Expect(u.BillingItems).Should(gomega.BeEmpty(), "a line item should not be created")
}

func Test_Watermark_Watermark_Puts_Failed_Runs_Into_DLQ(t *testing.T) {
	client, _ := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	client.ProduceBadMessageForQueue(models.WorkerTypeWatermarkHandler)

	client.ValidateQueue(1, models.WorkerTypeWatermarkHandler)

	client.RunWatermarkHandler(1)
	client.ValidateQueue(0, models.WorkerTypeWatermarkHandler)
	client.ValidateDeadLetterQueue(1, models.WorkerTypeWatermarkHandler)
}

func Test_Watermark_Watermark_Processes_Cost_Center(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	_ = client.CreateCustomer(customerProto)

	// create cost center specific usage
	entity := stubs.CreateEntity()
	customerId := customerProto.CustomerId
	entity.CustomerId = customerId
	costCenter := stubs.CreateAzureCostCenterWithCustomerId(entity.CustomerId)
	response, _ := client.CreateCostCenter(costCenter)
	costCenterKey := response.CostCenter.CostCenterKey
	resource := stubs.GetResource(entity, proto.ResourceType_Org)
	_, err := client.CostCenterAddResourceTo(costCenterKey, []*proto.Resource{resource})
	g.Expect(err).ToNot(gomega.HaveOccurred())
	costCenterResponse := client.FindCostCenterFor(entity, "")
	c := costCenterResponse.CostCenterKey
	g.Expect(c).ShouldNot(gomega.BeNil())

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(1).Time
	then := january2021.WithDay(1).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsageFrom(pricing, entity, then, quantity)
	usages := []*hydroSchema.Usage{usage1}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	// The watermark event should always rollup to the actual Customer while the line item will be
	// assigned to a cost center as we generate hourly line items.
	u := client.GetUsageEventItems("", pricing.GetSku(), customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "an event is expected for the Customer")

	// Verifies that the generated line item gets assigned to a cost center
	u = client.GetUsageLineItems("", "", costCenterKey.Uuid, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created for the Cost Center")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
	g.Expect(billingItem.UsageEntityId).Should(gomega.Equal(costCenterKey.Uuid))
}

func Test_Watermark_Watermark_With_Add_And_Remove_Same_Hour(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(1).Time
	then := january2021.WithDay(1).WithHour(0).Time
	thenLater := january2021.WithDay(1).WithHour(0).WithMinute(30).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 10, customerId, then)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), -10, customerId, thenLater, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	billingItem := u.BillingItems[0]
	// ((10 GiB * 0.5 hour consumed) / 24 hours in a day) = 0.208333333 GiB-Hours
	g.Expect(billingItem.Quantity).Should(gomega.Equal(0.208333333))

	// Check that tomorrow doesn't generate a line item given the usage is 0 moving forward
	now = january2021.WithDay(2).WithHour(1).Time
	client.ScheduleWatermarkJobs(now, pricing.GetSku())
	client.RunRequestHandler(1)
	client.RunWatermarkHandler(1)

	u = client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).Should(gomega.BeEmpty(), "a line item should not be created")
}

func Test_Watermark_Watermark_With_Add_And_Remove(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(3).WithHour(2).Time
	then := january2021.WithDay(1).Time
	thenNextDay := january2021.WithDay(2).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 10, customerId, then)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), -5, customerId, thenNextDay, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(5.0))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(5 * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_WatermarkRollups_With_Add_And_Remove_Fractional_Usage(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(20).Time
	then := january2021.WithDay(1).WithHour(0).Time
	thenNextDay := january2021.WithDay(1).WithHour(12).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 10, customerId, then)
	usage2 := stubs.CreateUsageWithOrgRepo(pricing.GetSku(), -4, customerId, thenNextDay, usage1.Entity.RepoId, usage1.Entity.OrganizationId)
	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	// Validate full day of usage
	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	billingItem := u.BillingItems[0]
	// We start with 10 GiB of usage and then receive -4 GiB at 12:00. This means
	// that we will have 6 GiB of usage at 13:00
	g.Expect(billingItem.Quantity).Should(gomega.Equal(6.0))
	g.Expect(billingItem.BilledAmount).Should(gomega.BeNumerically("~", 6*pricing.GetPrice(), 0.0001))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_Midday_Usage(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 10.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(20).Time
	then := january2021.WithDay(1).WithHour(12).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, then)
	usages := []*hydroSchema.Usage{usage1}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	billingItem := u.BillingItems[0]

	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_Midday_Usage_Half_Hour(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(20).Time
	then := january2021.WithDay(1).WithHour(12).WithMinute(30).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, then)
	usages := []*hydroSchema.Usage{usage1}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	billingItem := u.BillingItems[0]
	// 0.5 GiB-Hours for the half hour and 11 GiB-Hours for remaining time left in the day
	// 0.958333333 GiB-Hours * 12 hours = 11.5 GiB-Hours
	g.Expect(billingItem.Quantity).Should(gomega.Equal(0.958333333))
	g.Expect(billingItem.BilledAmount).Should(gomega.BeNumerically("~", 0.958333333*pricing.GetPrice(), 0.0001))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}

func Test_Watermark_Watermark_Omits_Future_Hours_Usage(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January).WithDay(1)
	runTime := january2021.WithHour(5).Time

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, january2021.WithHour(1).Time)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, january2021.WithHour(5).Time)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, january2021.WithHour(10).Time)
	usage4 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, january2021.WithHour(11).Time)
	usage5 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, january2021.WithHour(12).Time)
	usages := []*hydroSchema.Usage{usage1, usage2, usage3, usage4, usage5}

	expectedLineItems := 2
	client.ProcessWatermarkUsage(runTime, usages, integration.ProcessWatermarkUsageOpts{ExpectedLineItems: expectedLineItems})
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, runTime, proto.BillingPeriod_Daily)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(1), "one line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity * float64(expectedLineItems)))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * float64(expectedLineItems) * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
}
