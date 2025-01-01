//go:build integration
// +build integration

package integrationtests_test

import (
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
)

func Test_Subscription_whenASubscriptionIsAddedTheSystemRecordsIt(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create a high watermark product
	// the PricingMeterType_DailyUnitCharge meter type is what makes this a high watermark product
	price := 10.0
	pricing := client.EnsureSpecificPricingExistsWithAll(price, "sku-1", "product-1", proto.PricingMeterType_DailyUnitCharge, "SKU 1", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	actorID := stubs.GetRandomId64()

	// add 1 seat
	addOne := 1.0
	addUsageDate := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, addUsageDate)
	usage1.Entity.ActorId = actorID

	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	// get total for current month (should be 1)
	u := client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, addUsageDate)
	g.Expect(u.Quantity).To(gomega.Equal(1.0))

	// global total
	u = client.GetSubscribedItemsTotal(pricing.GetSku(), customerID)
	g.Expect(u.Quantity).To(gomega.Equal(1.0))
}

func Test_Subscription_whenASubscriptionIsAddedWithLicenseAPITheSystemRecordsIt(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create a high watermark product
	// the PricingMeterType_DailyUnitCharge meter type is what makes this a high watermark product
	price := 10.0
	pricing := client.EnsureSpecificPricingExistsWithAll(price, "sku-1", "product-1", proto.PricingMeterType_DailyUnitCharge, "SKU 1", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	actorID := stubs.GetRandomId64()

	// add 1 seat
	client.AddLicense("sku-1", customerID, actorID)
	client.RunUsageIngestion(1)

	today := time.Now().UTC()

	highWatermark := client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, today)

	proratedQuantity := nano.NewFromFloat(float64(client.RemainingDaysInMonth(today))).Div(nano.NewFromFloat(float64(client.DaysInMonth(today))))
	decimalProratedQuantity := nano.ToDecimalAmount(proratedQuantity.Int64())
	g.Expect(highWatermark.Quantity).To(gomega.Equal(decimalProratedQuantity))

	// global total
	watermark := client.GetSubscribedItemsTotal(pricing.GetSku(), customerID)
	g.Expect(watermark.Quantity).To(gomega.Equal(1.0))

	client.RunDailyJob(1)

	// check usage is recorded in rollups
	usage := client.GetUsageLineItems("", pricing.GetSku(), customerID, today, proto.BillingPeriod_Daily)
	g.Expect(usage.BillingItems).ShouldNot(gomega.BeEmpty(), "expected usage to be recorded")
	g.Expect(usage.BillingItems[0].Quantity).To(gomega.Equal(decimalProratedQuantity))
	g.Expect(usage.BillingItems[0].FullQuantity).To(gomega.Equal(1.0))

	billedAmount := nano.NewFromFloat(price).Mul(nano.NewFromFloat(highWatermark.Quantity))
	g.Expect(usage.BillingItems[0].BilledAmount).To(gomega.Equal(nano.ToDecimalAmount(billedAmount.Int64())))
}

func Test_Subscription_whenASubscriptionIsRemovedWithLicenseAPITheSystemRecordsIt(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create a high watermark product
	// the PricingMeterType_DailyUnitCharge meter type is what makes this a high watermark product
	price := 10.0
	pricing := client.EnsureSpecificPricingExistsWithAll(price, "sku-1", "product-1", proto.PricingMeterType_DailyUnitCharge, "SKU 1", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	actorID := stubs.GetRandomId64()

	// add and remove 1 seat
	client.AddLicense("sku-1", customerID, actorID)
	client.RunUsageIngestion(1)
	client.RemoveLicense("sku-1", customerID, actorID)
	client.RunUsageIngestion(1)
	today := time.Now().UTC()

	highWatermark := client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, today)
	proratedQuantity := nano.NewFromFloat(float64(client.RemainingDaysInMonth(today))).Div(nano.NewFromFloat(float64(client.DaysInMonth(today))))
	decimalProratedQuantity := nano.ToDecimalAmount(proratedQuantity.Int64())
	g.Expect(highWatermark.Quantity).To(gomega.Equal(decimalProratedQuantity))

	// get total for next month (should be 0)
	highWatermarkNextMonth := client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, today.AddDate(0, 1, 0))
	g.Expect(highWatermarkNextMonth.Quantity).To(gomega.Equal(0.0))

	// global total should be 0 as it goes up and down with adds and removes
	watermark := client.GetSubscribedItemsTotal(pricing.GetSku(), customerID)
	g.Expect(watermark.Quantity).To(gomega.Equal(0.0))

	client.RunDailyJob(1)

	// check usage from the addition is recorded in rollups
	usage := client.GetUsageLineItems("", pricing.GetSku(), customerID, today, proto.BillingPeriod_Daily)
	g.Expect(usage.BillingItems).ShouldNot(gomega.BeEmpty(), "expected usage to be recorded")
	g.Expect(usage.BillingItems[0].Quantity).To(gomega.Equal(decimalProratedQuantity))
	g.Expect(usage.BillingItems[0].FullQuantity).To(gomega.Equal(1.0))

	billedAmount := nano.NewFromFloat(price).Mul(nano.NewFromFloat(highWatermark.Quantity))
	g.Expect(usage.BillingItems[0].BilledAmount).To(gomega.Equal(nano.ToDecimalAmount(billedAmount.Int64())))
}

func Test_Subscription_WhenAddAndRemove_CurrentMonthCountIs1_NextMonthIs0(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create a high watermark product
	// the PricingMeterType_DailyUnitCharge meter type is what makes this a high watermark product
	price := 10.0
	pricing := client.EnsureSpecificPricingExistsWithAll(price, "sku-1", "product-1", proto.PricingMeterType_DailyUnitCharge, "SKU 1", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	actorID := stubs.GetRandomId64()

	// add 1 seat
	addOne := 1.0
	addUsageDate := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC)
	addUsage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, addUsageDate)
	addUsage.Entity.ActorId = actorID

	// remove 1 seat
	removeUsageDate := time.Date(2010, 11, 1, 4, 0, 0, 0, time.UTC)
	removeOne := -1.0
	removeUsage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), removeOne, customerID, removeUsageDate)
	removeUsage.Entity.ActorId = actorID

	client.ProduceMeteredUsage([]*hydroSchema.Usage{addUsage})
	client.RunUsageIngestion(1)

	client.ProduceMeteredUsage([]*hydroSchema.Usage{removeUsage})
	client.RunUsageIngestion(1)

	// get total for current month (should be 1)
	u := client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, addUsageDate)
	g.Expect(u.Quantity).To(gomega.Equal(1.0))

	// get total for next month (should be 0)
	u = client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, addUsageDate.AddDate(0, 1, 0))
	g.Expect(u.Quantity).To(gomega.Equal(0.0))

	// global total
	u = client.GetSubscribedItemsTotal(pricing.GetSku(), customerID)
	g.Expect(u.Quantity).To(gomega.Equal(0.0))
}

func Test_Subscription_WhenAddAndRemoveReAdd_CurrentMonthCountIs1_NextMonthIs1(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create a high watermark product
	// the PricingMeterType_DailyUnitCharge meter type is what makes this a high watermark product
	price := 10.0
	pricing := client.EnsureSpecificPricingExistsWithAll(price, "sku-1", "product-1", proto.PricingMeterType_DailyUnitCharge, "SKU 1", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	actorID := stubs.GetRandomId64()

	// add 1 seat
	addOne := 1.0
	addUsageDate := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC)
	addUsage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, addUsageDate)
	addUsage.Entity.ActorId = actorID

	// remove 1 seat
	removeUsageDate := time.Date(2010, 11, 1, 4, 0, 0, 0, time.UTC)
	removeOne := -1.0
	removeUsage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), removeOne, customerID, removeUsageDate)
	removeUsage.Entity.ActorId = actorID

	client.ProduceMeteredUsage([]*hydroSchema.Usage{addUsage})
	client.RunUsageIngestionWithTimeTravel(1, addUsageDate)

	client.ProduceMeteredUsage([]*hydroSchema.Usage{removeUsage})
	client.RunUsageIngestionWithTimeTravel(1, removeUsageDate)

	// get total for current month (should be 1)
	u := client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, addUsageDate)
	g.Expect(u.Quantity).To(gomega.Equal(1.0))

	// get total for next month (should be 0)
	u = client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, addUsageDate.AddDate(0, 1, 0))
	g.Expect(u.Quantity).To(gomega.Equal(0.0))

	// if we re add the original usage, the monthly total should stay the same, the global total should be 1 also
	newAddDate := addUsageDate.AddDate(0, 0, 3)
	addAgain := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, newAddDate)
	addAgain.Entity.ActorId = actorID

	client.ProduceMeteredUsage([]*hydroSchema.Usage{addAgain})
	client.RunUsageIngestionWithTimeTravel(1, newAddDate)

	// get total for current month (should be 1)
	u = client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, newAddDate)
	g.Expect(u.Quantity).To(gomega.Equal(float64(1.0)), "monthly total should be 1 after readd")

	// get total for next month (should be 0)
	u = client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, newAddDate.AddDate(0, 1, 0))
	g.Expect(u.Quantity).To(gomega.Equal(0.0))
}

func Test_Subscription_WhenAddAndRemove_InCurrentMonth_AndReAddInNextMonth_CurrentMonthCountIs1_NextMonthIs1(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create a high watermark product
	// the PricingMeterType_DailyUnitCharge meter type is what makes this a high watermark product
	price := 10.0
	pricing := client.EnsureSpecificPricingExistsWithAll(price, "sku-1", "product-1", proto.PricingMeterType_DailyUnitCharge, "SKU 1", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	actorID := stubs.GetRandomId64()

	// add 1 seat
	addOne := 1.0
	addUsageDateInNovember := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC)
	addUsage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, addUsageDateInNovember)
	addUsage.Entity.ActorId = actorID

	// remove 1 seat
	removeUsageDate := time.Date(2010, 11, 1, 4, 0, 0, 0, time.UTC)
	removeOne := -1.0
	removeUsage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), removeOne, customerID, removeUsageDate)
	removeUsage.Entity.ActorId = actorID

	client.ProduceMeteredUsage([]*hydroSchema.Usage{addUsage})
	client.RunUsageIngestionWithTimeTravel(1, addUsageDateInNovember)

	client.ProduceMeteredUsage([]*hydroSchema.Usage{removeUsage})
	client.RunUsageIngestionWithTimeTravel(1, removeUsageDate)

	// get total for november, should be 1
	u := client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, addUsageDateInNovember)
	g.Expect(u.Quantity).To(gomega.Equal(1.0))

	// get total for December should be 0
	u = client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, addUsageDateInNovember.AddDate(0, 1, 0))
	g.Expect(u.Quantity).To(gomega.Equal(0.0))

	// get global total 0
	u = client.GetSubscribedItemsTotal(pricing.GetSku(), customerID)
	g.Expect(u.Quantity).To(gomega.Equal(0.0))

	// if we re add the original usage, the monthly total should stay the same, the global total should be 1 also
	newAddDateInJan := addUsageDateInNovember.AddDate(0, 2, 0)
	addAgain := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, newAddDateInJan)
	addAgain.Entity.ActorId = actorID

	client.ProduceMeteredUsage([]*hydroSchema.Usage{addAgain})
	client.RunUsageIngestionWithTimeTravel(1, newAddDateInJan)

	// get total for jan, should be 1
	u = client.GetSubscribedItemsMonthlyTotal(pricing.GetSku(), customerID, newAddDateInJan)
	g.Expect(u.Quantity).To(gomega.Equal(1.0), "global total should be 1 after readd")

	// get global total 0
	u = client.GetSubscribedItemsTotal(pricing.GetSku(), customerID)
	g.Expect(u.Quantity).To(gomega.Equal(1.0))
}

func Test_Subscription_GetSubscribedItems_ReturnsListOfItems(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create a high watermark product
	// the PricingMeterType_DailyUnitCharge meter type is what makes this a high watermark product
	price := 10.0
	pricing := client.EnsureSpecificPricingExistsWithAll(price, "sku-1", "product-1", proto.PricingMeterType_DailyUnitCharge, "SKU 1", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	addOne := 1.0
	addUsageDateInNovember := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC)
	addUsage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, addUsageDateInNovember)
	addUsage.Entity.ActorId = stubs.GetRandomId64()

	addUsage2 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, addUsageDateInNovember)
	addUsage2.Entity.ActorId = stubs.GetRandomId64()

	addUsage3 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, addUsageDateInNovember)
	addUsage3.Entity.ActorId = stubs.GetRandomId64()

	client.ProduceMeteredUsage([]*hydroSchema.Usage{addUsage, addUsage2, addUsage3})
	client.RunUsageIngestionWithTimeTravel(3, addUsageDateInNovember)

	// get subscribed items
	u := client.GetSubscribedItems(pricing.GetSku(), customerID)
	g.Expect(len(u.SubscribedItems)).To(gomega.Equal(3))
}

func Test_Subscription_GetActiveSubscribedItems_ReturnsListOfItems(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create a high watermark product
	// the PricingMeterType_DailyUnitCharge meter type is what makes this a high watermark product
	price := 10.0
	pricing := client.EnsureSpecificPricingExistsWithAll(price, "sku-1", "product-1", proto.PricingMeterType_DailyUnitCharge, "SKU 1", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)
	actorIDs := []int64{stubs.GetRandomId64(), stubs.GetRandomId64(), stubs.GetRandomId64()}

	addOne := 1.0
	addUsageDateInNovember := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC)
	addUsage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, addUsageDateInNovember)
	addUsage.Entity.ActorId = actorIDs[0]

	addUsage2 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, addUsageDateInNovember)
	addUsage2.Entity.ActorId = actorIDs[1]

	addUsage3 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, addUsageDateInNovember)
	addUsage3.Entity.ActorId = actorIDs[2]

	client.ProduceMeteredUsage([]*hydroSchema.Usage{addUsage, addUsage2, addUsage3})
	client.RunUsageIngestionWithTimeTravel(3, addUsageDateInNovember)

	// get subscribed items
	u := client.GetActiveSubscribedItems(pricing.GetSku(), customerID)
	g.Expect(len(u.SubscribedItems)).To(gomega.Equal(3))
	subscribed := []int64{}
	for _, item := range u.SubscribedItems {
		subscribed = append(subscribed, item.SubscriptionId)
	}

	g.Expect(subscribed).To(gomega.ContainElement(actorIDs[0]))
	g.Expect(subscribed).To(gomega.ContainElement(actorIDs[1]))
	g.Expect(subscribed).To(gomega.ContainElement(actorIDs[2]))

	removeOne := -1.0
	removeUsageDateInNovember := time.Date(2010, 11, 1, 4, 0, 0, 0, time.UTC)
	removeUsage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), removeOne, customerID, removeUsageDateInNovember)
	removeUsage.Entity.ActorId = actorIDs[2]

	client.ProduceMeteredUsage([]*hydroSchema.Usage{removeUsage})
	client.RunUsageIngestionWithTimeTravel(1, removeUsageDateInNovember)

	u = client.GetActiveSubscribedItems(pricing.GetSku(), customerID)
	active := []int64{}
	for _, item := range u.SubscribedItems {
		active = append(active, item.SubscriptionId)
	}
	g.Expect(len(u.SubscribedItems)).To(gomega.Equal(2))
	g.Expect(active).ToNot(gomega.ContainElement(actorIDs[2]))
	g.Expect(active).To(gomega.ContainElement(actorIDs[1]))
	g.Expect(active).To(gomega.ContainElement(actorIDs[0]))
}

func Test_Subscription_WhenSubscriptionIsAdded_ProperlyBilled_AtstartOfMonth(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create a high watermark product
	// the PricingMeterType_DailyUnitCharge meter type is what makes this a high watermark product
	price := 10.0
	pricing := client.EnsureSpecificPricingExistsWithAll(price, "sku-1", "product-1", proto.PricingMeterType_DailyUnitCharge, "SKU 1", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	addOne := 1.0
	addUsageDateInNovember := time.Date(2010, 11, 1, 1, 0, 0, 0, time.UTC)
	addUsage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, addUsageDateInNovember)
	addUsage.Entity.ActorId = stubs.GetRandomId64()

	client.ProduceMeteredUsage([]*hydroSchema.Usage{addUsage})
	client.RunUsageIngestionWithTimeTravel(1, addUsageDateInNovember)
	client.RunDailyJobWithTimeTravel(1, addUsageDateInNovember)
	client.RunMonthlyJobWithTimeTravel(1, addUsageDateInNovember)

	// get subscribed items
	u := client.GetSubscribedItems(pricing.GetSku(), customerID)
	g.Expect(len(u.SubscribedItems)).To(gomega.Equal(1))

	x := client.GetUsageTotalTest("", pricing.GetSku(), customerID, addUsageDateInNovember, proto.BillingPeriod_Daily)
	g.Expect(float64(x.Quantity)).Should(gomega.Equal(1.0), "usage daily for usage date")
	g.Expect(float64(x.BillableAmount)).Should(gomega.Equal(10.0))

	x = client.GetUsageTotalTest("", pricing.GetSku(), customerID, addUsageDateInNovember, proto.BillingPeriod_Monthly)
	g.Expect(float64(x.Quantity)).Should(gomega.Equal(1.0), "usage daily for usage date")
	g.Expect(float64(x.BillableAmount)).Should(gomega.Equal(10.0))
}

func Test_Subscription_WhenSubscriptionIsAdded_ProperlyBilled_AtMiddleOfMonth(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create a high watermark product
	// the PricingMeterType_DailyUnitCharge meter type is what makes this a high watermark product
	price := 10.0
	pricing := client.EnsureSpecificPricingExistsWithAll(price, "sku-1", "product-1", proto.PricingMeterType_DailyUnitCharge, "SKU 1", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	addOne := 1.0
	addUsageDateInNovember := time.Date(2010, 11, 16, 0, 0, 0, 0, time.UTC)
	addUsage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), addOne, customerID, addUsageDateInNovember)
	addUsage.Entity.ActorId = stubs.GetRandomId64()

	client.ProduceMeteredUsage([]*hydroSchema.Usage{addUsage})
	client.RunUsageIngestionWithTimeTravel(1, addUsageDateInNovember)
	client.RunDailyJobWithTimeTravel(1, addUsageDateInNovember)
	client.RunMonthlyJobWithTimeTravel(1, addUsageDateInNovember)

	// get subscribed items
	u := client.GetSubscribedItems(pricing.GetSku(), customerID)
	g.Expect(len(u.SubscribedItems)).To(gomega.Equal(1))

	x := client.GetUsageTotalTest("", pricing.GetSku(), customerID, addUsageDateInNovember, proto.BillingPeriod_Daily)
	g.Expect(float64(x.Quantity)).Should(gomega.Equal(0.5), "prorated usage quantity")
	g.Expect(float64(x.BillableAmount)).Should(gomega.Equal(5.0), "cost for half the month")

	x = client.GetUsageTotalTest("", pricing.GetSku(), customerID, addUsageDateInNovember, proto.BillingPeriod_Monthly)
	g.Expect(float64(x.Quantity)).Should(gomega.Equal(0.5), "prorated usage quantity")
	g.Expect(float64(x.BillableAmount)).Should(gomega.Equal(5.0), "cost for half the month")
}
