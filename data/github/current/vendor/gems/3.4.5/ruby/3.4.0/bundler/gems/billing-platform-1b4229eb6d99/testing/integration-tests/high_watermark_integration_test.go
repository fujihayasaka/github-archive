//go:build integration
// +build integration

package integrationtests_test

import (
	"fmt"
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	a "github.com/github/billing-platform/testing/assertions"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/integration-tests/helpers"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
)

func Test_HighWatermark_Disabled(t *testing.T) {
	client, _ := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{"actions"}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(19.0, "copilot_for_business", "copilot", proto.PricingMeterType_DailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)
	quantity := 1.0

	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)

	// Create usage with date of yesterday as this is what the job looks for when attempting emission to Azure
	usageDateThen := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour(), 0, 0, 0, time.UTC)

	// add 1 seat
	usage1 := stubs.CreateUsage(stubs.GetRandomId64AsString(), pricing.GetSku(), quantity, customerId, usageDateThen)

	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	// High watermark items are not included in the Azure emission rollup
	client.ValidateQueue(0, models.WorkerTypeCustomerAzureEmissionDailyRollup)

	// Perform azure daily rollup and regular daily rollup (to ensure discount totals are created for day)
	client.RunAzureDailyRollupJob(len(usages))
	client.RunDailyJob(len(usages))

	// Send an azure emission request message to the request-handler queue to trigger azure emission
	client.ScheduleAzureEmissionWithTime(yesterday)

	// Ensure our request made it to the queue but no azure emissions are queued yet
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Fan out the usage line items to the azure emission queue
	client.RunRequestHandler(1)

	// Ensure there are no items in the azure emission handler queue
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)
}

func Test_HighWatermark_Full_Month_Usage(t *testing.T) {
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

	quantity := 1.0
	usageDate := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC) // first day of the month
	usage1, err := (&stubs.CreateUsageParams{
		SKU:            pricing.GetSku(),
		Quantity:       quantity,
		CustomerId:     customerID,
		UsageAt:        usageDate,
		OrganizationId: stubs.GetRandomId64(),
		ActorId:        stubs.GetRandomId64(),
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", pricing.GetSku(), customerID, usageDate, proto.BillingPeriod_Daily)
	fmt.Printf("usage line items: %+v\n", u)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(quantity, quantity, price, price)))
}

func Test_HighWatermark_Prorated_Usage(t *testing.T) {
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

	quantity := 1.0
	usageDate := time.Date(2010, 11, 16, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerID, usageDate)
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", pricing.GetSku(), customerID, usageDate, proto.BillingPeriod_Daily)
	expectedFullQuantity := 1.0             // Display the full seat to customers
	expectedQuantity := 0.5                 // Prorated for half the month
	expectedBilledAmount := 5.0             // Prorated for half the month
	expectedAppliedCostPerQuantity := price // 10.0 price
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(expectedQuantity, expectedFullQuantity, expectedBilledAmount, expectedAppliedCostPerQuantity)))

	// after the daily job, get usage from daily bucket from final total
	ut := client.GetUsageTotalTest("", "", customerID, usageDate, proto.BillingPeriod_Daily)
	g.Expect(ut.Quantity).Should(gomega.Equal(0.5), "usage quantity from daily bucket")
	g.Expect(ut.BillableAmount).Should(gomega.Equal(5.0), "usage billed amount from daily bucket")

	client.RunMonthlyJob(len(usages))
	// after the monthly job, get usage from monthly bucket from running total
	ut = client.GetUsageTotalTest("", "", customerID, usageDate, proto.BillingPeriod_Monthly)
	g.Expect(ut.Quantity).Should(gomega.Equal(0.5), "usage quantity from monthly bucket")
	g.Expect(ut.BillableAmount).Should(gomega.Equal(5.0), "usage billed amount from monthly bucket")

	client.RunYearlyJob(len(usages))
	// after the yearly job, get usage from monthly bucket from running total
	ut = client.GetUsageTotalTest("", "", customerID, usageDate, proto.BillingPeriod_Yearly)
	g.Expect(ut.Quantity).Should(gomega.Equal(0.5), "usage quantity from yearly bucket")
	g.Expect(ut.BillableAmount).Should(gomega.Equal(5.0), "usage billed amount from yearly bucket")
}

func Test_HighWatermark_Multiple_Add_Usage(t *testing.T) {
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

	quantity := 1.0

	usageDate1 := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerID, usageDate1)
	usageDate2 := time.Date(2010, 11, 1, 4, 0, 0, 0, time.UTC)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity+1, customerID, usageDate2)
	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.ValidateQueue(2, models.WorkerTypeCustomerDailyRollup)
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", pricing.GetSku(), customerID, usageDate1, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty())
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(quantity, quantity, price, price)))

	u = client.GetUsageLineItems("", pricing.GetSku(), customerID, usageDate2, proto.BillingPeriod_Daily)
	expectedQuantity := 2.0
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty())
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(expectedQuantity, expectedQuantity, price*expectedQuantity, price)))
}

func Test_HighWatermark_Multiple_Add_And_Remove_Usage(t *testing.T) {
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
	orgID := stubs.GetRandomId64()

	// add 1 seat
	addOne := 1.0
	addUsageDate := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC)
	usage1, err := (&stubs.CreateUsageParams{
		SKU:            pricing.GetSku(),
		Quantity:       addOne,
		CustomerId:     customerID,
		UsageAt:        addUsageDate,
		OrganizationId: orgID,
		ActorId:        actorID,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())
	// remove 1 seat
	removeUsageDate := time.Date(2010, 11, 2, 4, 0, 0, 0, time.UTC)
	removeOne := -1.0
	usage2, err := (&stubs.CreateUsageParams{
		SKU:            pricing.GetSku(),
		Quantity:       removeOne,
		CustomerId:     customerID,
		UsageAt:        removeUsageDate,
		OrganizationId: orgID,
		ActorId:        actorID,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())

	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))

	u := client.GetUsageLineItems("", pricing.GetSku(), customerID, addUsageDate, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(addOne, addOne, price, price)))

	u = client.GetUsageLineItems("", pricing.GetSku(), customerID, removeUsageDate, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).Should(gomega.BeEmpty(), "a line item should not be created for high watermark remove events")
}

func Test_HighWatermark_Multiple_Skus(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing1 := client.EnsureSpecificPricingExistsWithAll(19.0, "copilot_for_business", "copilot", proto.PricingMeterType_DailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)
	pricing2 := client.EnsureSpecificPricingExistsWithAll(21.0, "ghec_seats", "ghec", proto.PricingMeterType_DailyUnitCharge, "GHEC seats", proto.UnitType_UserMonths)

	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(1).Time
	then := january2021.WithDay(1).Time

	actorId := stubs.GetRandomId64()
	orgId := stubs.GetRandomId64()

	// add 1 seat
	usage1, err := (&stubs.CreateUsageParams{
		SKU:            pricing1.Sku,
		Quantity:       quantity,
		CustomerId:     customerId,
		UsageAt:        then,
		OrganizationId: orgId,
		ActorId:        actorId,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())

	// add 1 seat
	usage2, err := (&stubs.CreateUsageParams{
		SKU:            pricing2.Sku,
		Quantity:       quantity,
		CustomerId:     customerId,
		UsageAt:        then,
		OrganizationId: orgId,
		ActorId:        actorId,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())

	// this series of usages should result in 1 seat in each high watermark partition
	// and 1 seats in each regular watermark

	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should be created")

	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(1.0, 1.0, 19.0, pricing1.Price)))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchingOnAmounts(1.0, 1.0, 21.0, pricing2.Price)))
}

func matchingOnAmounts(quantity, fullQuantity, billedAmount, appliedCostPerQuantity float64) func(*proto.BillingItem) bool {
	return func(item *proto.BillingItem) bool {
		mismatch := false

		if item.Quantity != quantity {
			fmt.Printf("Mismatch in Quantity: expected %v, got %v\n", quantity, item.Quantity)
			mismatch = true
		}
		if item.FullQuantity != fullQuantity {
			fmt.Printf("Mismatch in FullQuantity: expected %v, got %v\n", fullQuantity, item.FullQuantity)
			mismatch = true
		}
		if item.BilledAmount != billedAmount {
			fmt.Printf("Mismatch in BilledAmount: expected %v, got %v\n", billedAmount, item.BilledAmount)
			mismatch = true
		}
		if item.AppliedCostPerQuantity != appliedCostPerQuantity {
			fmt.Printf("Mismatch in AppliedCostPerQuantity: expected %v, got %v\n", appliedCostPerQuantity, item.AppliedCostPerQuantity)
			mismatch = true
		}

		return !mismatch
	}
}

func Test_HighWatermark_Rollover_AllAddSeats(t *testing.T) {

	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(19, "copilot_for_business", "copilot", models.PricingMeterDailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usage1, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC),
		ActorId:    401,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())
	usage2, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 1, 4, 0, 0, 0, time.UTC),
		ActorId:    402,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())
	usage3, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 1, 5, 0, 0, 0, time.UTC),
		ActorId:    403,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())
	helpers.IngestUsage([]*hydroSchema.Usage{usage1, usage2, usage3}, client)

	// 3 billing items for the month
	u := client.GetUsageLineItems("", pricing.GetSku(), customerID, usage1.UsageAt.AsTime(), proto.BillingPeriod_Monthly)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchAmounts(3.0, 57.0, pricing.GetPrice())))

	// 3 total subscription items on customer
	TotalsubscriptionItems := client.GetSubscribedItemsTotal(pricing.GetSku(), customerID)
	g.Expect(TotalsubscriptionItems.Quantity).To(gomega.Equal(3.0))

	// 3 subscription items on customer for each actor
	subscriptionItemsResponse := client.GetSubscribedItems(pricing.GetSku(), customerID)
	g.Expect(len(subscriptionItemsResponse.SubscribedItems)).To(gomega.Equal(3))

	// run the rollover job at 5 minutes past midnight of next month
	rollOverDate := time.Date(2010, 12, 1, 0, 5, 0, 0, time.UTC)
	throttleTime := 3 * time.Second
	client.ScheduleHighWatermarkRolloverJobs(rollOverDate, customerID, pricing.GetSku(), throttleTime)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeHighWatermarkRolloverHandler)
	client.RunHighWatermarkRolloverHandler(1)
	// verify we rollover all 3 seats
	client.ValidateQueue(3, models.WorkerTypeUsageIngestion)

	// run ingestion after rollover job run
	client.RunUsageIngestionWithTimeTravel(3, rollOverDate)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	afterRollOver := rollOverDate.Add(time.Minute * 2)
	client.RunUsageIngestionWithTimeTravel(3, afterRollOver)
	client.ValidateQueue(3, models.WorkerTypeCustomerDailyRollup)
	client.ValidateQueue(3, models.WorkerTypeCustomerMonthlyRollup)
	client.RunDailyJobWithTimeTravel(3, rollOverDate.Add(time.Minute*2))
	client.RunMonthlyJobWithTimeTravel(3, rollOverDate.Add(time.Minute*2))

	// 1 line item in the next monthly aggregation with 3 seats
	u = client.GetUsageLineItems("", pricing.GetSku(), customerID, afterRollOver, proto.BillingPeriod_Monthly)
	g.Expect(len(u.BillingItems)).To(gomega.Equal(1))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchAmounts(3.0, 57.0, pricing.GetPrice())))
}

func Test_HighWatermark_Rollover_WithRemovedSeats(t *testing.T) {

	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(19, "copilot_for_business", "copilot", models.PricingMeterDailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usage1, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC),
		ActorId:    401,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())

	usage2, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 1, 4, 0, 0, 0, time.UTC),
		ActorId:    402,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())
	helpers.IngestUsage([]*hydroSchema.Usage{usage1, usage2}, client)

	// have to do the ingestion as one after another since aqueduct does not guarantee ordering
	usage3, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   -1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 1, 5, 0, 0, 0, time.UTC),
		ActorId:    401,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())
	helpers.IngestUsage([]*hydroSchema.Usage{usage3}, client)

	// 2 billing items for the month
	u := client.GetUsageLineItems("", pricing.GetSku(), customerID, usage1.UsageAt.AsTime(), proto.BillingPeriod_Monthly)
	fmt.Printf("\nUsage line items: %+v\n", u)
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchAmounts(2.0, 38.0, pricing.GetPrice())))

	// 1 actual/total subscription items on customer
	TotalsubscriptionItems := client.GetSubscribedItemsTotal(pricing.GetSku(), customerID)
	g.Expect(TotalsubscriptionItems.Quantity).To(gomega.Equal(1.0))

	// 2 subscription items on customer for each actor
	subscriptionItemsResponse := client.GetSubscribedItems(pricing.GetSku(), customerID)
	g.Expect(len(subscriptionItemsResponse.SubscribedItems)).To(gomega.Equal(2))

	// run the rollover workflow at 5 minutes past midnight of next month
	rollOverDate := time.Date(2010, 12, 1, 0, 5, 0, 0, time.UTC)
	throttleTime := 3 * time.Second
	client.ScheduleHighWatermarkRolloverJobs(rollOverDate, customerID, pricing.GetSku(), throttleTime)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeHighWatermarkRolloverHandler)
	client.RunHighWatermarkRolloverHandler(1)
	// verify we rollover 1 seats skipping the removed seat
	client.ValidateQueue(1, models.WorkerTypeUsageIngestion)

	client.RunUsageIngestionWithTimeTravel(1, rollOverDate)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	afterRollOver := rollOverDate.Add(time.Minute * 2)
	client.RunUsageIngestionWithTimeTravel(3, afterRollOver)
	client.ValidateQueue(1, models.WorkerTypeCustomerDailyRollup)
	client.ValidateQueue(1, models.WorkerTypeCustomerMonthlyRollup)
	client.RunDailyJobWithTimeTravel(1, afterRollOver)
	client.RunMonthlyJobWithTimeTravel(1, afterRollOver)

	u = client.GetUsageLineItems("", pricing.GetSku(), customerID, afterRollOver, proto.BillingPeriod_Monthly)
	g.Expect(len(u.BillingItems)).To(gomega.Equal(1))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchAmounts(1.0, 19.0, pricing.GetPrice())))
}

func Test_HighWatermark_Rollover_NoSubscriptions(t *testing.T) {

	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(19, "copilot_for_business", "copilot", models.PricingMeterDailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)
	usage1, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC),
		ActorId:    401,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())
	usage2, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   -1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 1, 5, 0, 0, 0, time.UTC),
		ActorId:    401,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())
	helpers.IngestUsage([]*hydroSchema.Usage{usage1}, client)
	helpers.IngestUsage([]*hydroSchema.Usage{usage2}, client)

	// run the rollover workflow at 5 minutes past midnight of next month
	rollOverDate := time.Date(2010, 12, 1, 0, 5, 0, 0, time.UTC)
	throttleTime := 3 * time.Second
	client.ScheduleHighWatermarkRolloverJobs(rollOverDate, customerID, pricing.GetSku(), throttleTime)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeHighWatermarkRolloverHandler)
	client.RunHighWatermarkRolloverHandler(1)

	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	client.RunUsageIngestionWithTimeTravel(1, rollOverDate)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	afterRollOver := rollOverDate.Add(time.Minute * 2)
	client.RunUsageIngestionWithTimeTravel(3, afterRollOver)
	client.RunDailyJobWithTimeTravel(1, afterRollOver)
	client.RunMonthlyJobWithTimeTravel(1, afterRollOver)

	u := client.GetUsageLineItems("", pricing.GetSku(), customerID, afterRollOver, proto.BillingPeriod_Monthly)
	g.Expect(len(u.BillingItems)).To(gomega.Equal(0))
}

func Test_HighWatermark_Rollover_NoDuplicateChargeAfter(t *testing.T) {

	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(19, "copilot_for_business", "copilot", models.PricingMeterDailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usage1, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC),
		ActorId:    401,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())

	helpers.IngestUsage([]*hydroSchema.Usage{usage1}, client)

	// run the rollover workflow at 5 minutes past midnight of next month
	rollOverDate := time.Date(2010, 12, 1, 0, 5, 0, 0, time.UTC)
	throttleTime := 3 * time.Second
	client.ScheduleHighWatermarkRolloverJobs(rollOverDate, customerID, pricing.GetSku(), throttleTime)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeHighWatermarkRolloverHandler)
	client.RunHighWatermarkRolloverHandler(1)
	// verify we rollover 1 seats skipping the removed seat
	client.ValidateQueue(1, models.WorkerTypeUsageIngestion)

	client.RunUsageIngestionWithTimeTravel(1, rollOverDate)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	afterRollOver := rollOverDate.Add(time.Minute * 2)
	client.RunUsageIngestionWithTimeTravel(1, afterRollOver)
	client.ValidateQueue(1, models.WorkerTypeCustomerDailyRollup)
	client.ValidateQueue(1, models.WorkerTypeCustomerMonthlyRollup)
	client.RunDailyJobWithTimeTravel(1, afterRollOver)
	client.RunMonthlyJobWithTimeTravel(1, afterRollOver)

	u := client.GetUsageLineItems("", pricing.GetSku(), customerID, afterRollOver, proto.BillingPeriod_Monthly)
	g.Expect(len(u.BillingItems)).To(gomega.Equal(1))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchAmounts(1.0, 19.0, pricing.GetPrice())))

	usage2, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    afterRollOver,
		ActorId:    401,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())
	helpers.IngestUsage([]*hydroSchema.Usage{usage2}, client)

	u = client.GetUsageLineItems("", pricing.GetSku(), customerID, afterRollOver, proto.BillingPeriod_Monthly)
	g.Expect(len(u.BillingItems)).To(gomega.Equal(1))

	g.Expect(u.BillingItems).Should(a.IncludeItem(matchAmounts(1.0, 19.0, pricing.GetPrice())))
}

func Test_HighWatermark_Rollover_NoDuplicateChargeBefore(t *testing.T) {

	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(19, "copilot_for_business", "copilot", models.PricingMeterDailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usage1, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC),
		ActorId:    401,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())

	helpers.IngestUsage([]*hydroSchema.Usage{usage1}, client)

	rollOverDate := time.Date(2010, 12, 1, 0, 5, 0, 0, time.UTC)
	beforeRollOverDate := rollOverDate.Add(time.Minute * -3)
	afterRollOver := rollOverDate.Add(time.Minute * 2)

	usage2, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    beforeRollOverDate,
		ActorId:    401,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())
	helpers.IngestUsage([]*hydroSchema.Usage{usage2}, client)

	u := client.GetUsageLineItems("", pricing.GetSku(), customerID, beforeRollOverDate, proto.BillingPeriod_Monthly)
	g.Expect(len(u.BillingItems)).To(gomega.Equal(1))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchAmounts(1.0, 19.0, pricing.GetPrice())))

	// run the rollover workflow at 5 minutes past midnight of next month
	throttleTime := 3 * time.Second
	client.ScheduleHighWatermarkRolloverJobs(rollOverDate, customerID, pricing.GetSku(), throttleTime)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeHighWatermarkRolloverHandler)
	client.RunHighWatermarkRolloverHandler(1)
	// verify we rollover 1 seats skipping the removed seat
	client.ValidateQueue(1, models.WorkerTypeUsageIngestion)

	client.RunUsageIngestionWithTimeTravel(1, rollOverDate)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	client.RunUsageIngestionWithTimeTravel(1, afterRollOver)
	client.ValidateQueue(0, models.WorkerTypeCustomerDailyRollup)
	client.ValidateQueue(0, models.WorkerTypeCustomerMonthlyRollup)
	client.RunDailyJobWithTimeTravel(1, afterRollOver)
	client.RunMonthlyJobWithTimeTravel(1, afterRollOver)

	u = client.GetUsageLineItems("", pricing.GetSku(), customerID, beforeRollOverDate, proto.BillingPeriod_Monthly)
	g.Expect(len(u.BillingItems)).To(gomega.Equal(1))
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchAmounts(1.0, 19.0, pricing.GetPrice())))
}

func Test_HighWatermark_Rollover_NoDuplicateChargeCurrentMonth(t *testing.T) {

	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(19, "copilot_for_business", "copilot", models.PricingMeterDailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usage1, err := (&stubs.CreateUsageParams{
		SKU:        pricing.GetSku(),
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 19, 3, 0, 0, 0, time.UTC),
		ActorId:    401,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())

	helpers.IngestUsage([]*hydroSchema.Usage{usage1}, client)

	rollOverDate := time.Date(2010, 11, 1, 0, 5, 0, 0, time.UTC)
	afterRollOver := rollOverDate.Add(time.Minute * 2)

	// run the rollover workflow at 5 minutes past midnight of next month
	throttleTime := 3 * time.Second
	client.ScheduleHighWatermarkRolloverJobs(rollOverDate, customerID, pricing.GetSku(), throttleTime)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeHighWatermarkRolloverHandler)
	client.RunHighWatermarkRolloverHandler(1)

	client.ValidateQueue(1, models.WorkerTypeUsageIngestion)

	client.RunUsageIngestionWithTimeTravel(1, rollOverDate)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	client.RunUsageIngestionWithTimeTravel(1, afterRollOver)
	client.ValidateQueue(0, models.WorkerTypeCustomerDailyRollup)
	client.ValidateQueue(0, models.WorkerTypeCustomerMonthlyRollup)
	client.RunDailyJobWithTimeTravel(1, afterRollOver)
	client.RunMonthlyJobWithTimeTravel(1, afterRollOver)

	u := client.GetUsageLineItems("", pricing.GetSku(), customerID, afterRollOver, proto.BillingPeriod_Monthly)
	g.Expect(len(u.BillingItems)).To(gomega.Equal(1))
	expectedQuantity := (1.0 * 12.0 / 30.0)
	expectedBilledAmount := 7.6 // (1 * 12 / 30) * 19, we get 7.6000000000000005 due to floating point math so I'm rounding here
	g.Expect(u.BillingItems).Should(a.IncludeItem(matchAmounts(expectedQuantity, expectedBilledAmount, pricing.GetPrice())))
}

func Test_HighWatermark_Rollover_SingleActorWithMultipleSkus(t *testing.T) {

	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing1 := client.EnsureSpecificPricingExistsWithAll(10, "sku_1", "product_1", models.PricingMeterDailyUnitCharge, "Sku 1", proto.UnitType_UserMonths)
	pricing2 := client.EnsureSpecificPricingExistsWithAll(10, "sku_2", "product_2", models.PricingMeterDailyUnitCharge, "Sku 2", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerProto.EnabledProducts = []string{pricing1.Product, pricing2.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usage1, err := (&stubs.CreateUsageParams{
		SKU:        pricing1.Sku,
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC),
		ActorId:    401,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())
	usage2, err := (&stubs.CreateUsageParams{
		SKU:        pricing2.Sku,
		Quantity:   1,
		CustomerId: customerID,
		UsageAt:    time.Date(2010, 11, 1, 4, 0, 0, 0, time.UTC),
		ActorId:    401,
	}).ToUsage()
	g.Expect(err).ToNot(gomega.HaveOccurred())

	helpers.IngestUsage([]*hydroSchema.Usage{usage1, usage2}, client)

	// 2 billing items for the month
	u1 := client.GetUsageLineItems("", pricing1.Sku, customerID, usage1.UsageAt.AsTime(), proto.BillingPeriod_Monthly)
	g.Expect(u1.BillingItems).Should(a.IncludeItem(matchAmounts(1.0, 10.0, pricing1.Price)))

	u2 := client.GetUsageLineItems("", pricing2.Sku, customerID, usage2.UsageAt.AsTime(), proto.BillingPeriod_Monthly)
	g.Expect(u2.BillingItems).Should(a.IncludeItem(matchAmounts(1.0, 10.0, pricing2.Price)))

	// 1 subscription items on customer for sku_1
	totalSubscriptionItems1 := client.GetSubscribedItemsTotal(pricing1.Sku, customerID)
	g.Expect(totalSubscriptionItems1.Quantity).To(gomega.Equal(1.0))

	// 1 subscription items on customer for sku_2
	totalSubscriptionItems2 := client.GetSubscribedItemsTotal(pricing2.Sku, customerID)
	g.Expect(totalSubscriptionItems2.Quantity).To(gomega.Equal(1.0))

	// run the rollover job at 5 minutes past midnight of next month for the first sku
	rollOverDate := time.Date(2010, 12, 1, 0, 5, 0, 0, time.UTC)
	throttleTime := 3 * time.Second
	client.ScheduleHighWatermarkRolloverJobs(rollOverDate, customerID, pricing1.Sku, throttleTime)
	client.ScheduleHighWatermarkRolloverJobs(rollOverDate, customerID, pricing2.Sku, throttleTime)
	client.ValidateQueue(2, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(2)
	client.ValidateQueue(2, models.WorkerTypeHighWatermarkRolloverHandler)
	client.RunHighWatermarkRolloverHandler(2)

	// verify we rollover all 3 seats
	client.ValidateQueue(2, models.WorkerTypeUsageIngestion)

	// run ingestion after rollover job run
	client.RunUsageIngestionWithTimeTravel(2, rollOverDate)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	afterRollOver := rollOverDate.Add(time.Minute * 2)
	client.RunUsageIngestionWithTimeTravel(2, afterRollOver)
	client.ValidateQueue(2, models.WorkerTypeCustomerDailyRollup)
	client.ValidateQueue(2, models.WorkerTypeCustomerMonthlyRollup)
	client.RunDailyJobWithTimeTravel(2, rollOverDate.Add(time.Minute*2))
	client.RunMonthlyJobWithTimeTravel(2, rollOverDate.Add(time.Minute*2))

	// 2 line items in the next monthly aggregation with 1 seats
	u1 = client.GetUsageLineItems("", pricing1.Sku, customerID, afterRollOver, proto.BillingPeriod_Monthly)
	g.Expect(len(u1.BillingItems)).To(gomega.Equal(1))
	g.Expect(u1.BillingItems).Should(a.IncludeItem(matchAmounts(1.0, 10.0, pricing1.Price)))

	u2 = client.GetUsageLineItems("", pricing2.Sku, customerID, afterRollOver, proto.BillingPeriod_Monthly)
	g.Expect(len(u2.BillingItems)).To(gomega.Equal(1))
	g.Expect(u2.BillingItems).Should(a.IncludeItem(matchAmounts(1.0, 10.0, pricing2.Price)))
}

func Test_HighWatermark_Admin_Trigger_High_Watermark_Rollover_For_Date(t *testing.T) {
	client, _ := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	price := 10.0
	client.EnsureProductExists("sku-1", "product-1", "Test Product Usage")
	pricing := client.EnsureSpecificPricingExistsWithAll(price, "sku-1", "product-1", proto.PricingMeterType_DailyUnitCharge, "SKU 1", proto.UnitType_UserMonths)

	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	customerProto.EnabledProducts = []string{pricing.Product}

	_ = client.CreateCustomer(customerProto)

	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)

	quantity := 1.0
	usageDateYesterday := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour(), 0, 0, 0, time.UTC)
	usageYesterday := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerProto.CustomerId, usageDateYesterday)
	usages := []*hydroSchema.Usage{usageYesterday}

	// ingest high watermark events
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))

	// dry run should not emit any new events
	_ = client.AdminTriggerHighWatermarkRollover(&proto.TriggerHighWatermarkRolloverRequest{
		CustomerId: customerProto.CustomerId,
		Sku:        pricing.GetSku(),
		Year:       int64(usageDateYesterday.Year()),
		Month:      int64(usageDateYesterday.Month()),
		DryRun:     true,
	})

	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeHighWatermarkRolloverHandler)
	client.RunHighWatermarkRolloverHandler(1)

	// verify we do nothing
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	_ = client.AdminTriggerHighWatermarkRollover(&proto.TriggerHighWatermarkRolloverRequest{
		CustomerId: customerProto.CustomerId,
		Sku:        pricing.GetSku(),
		Year:       int64(usageDateYesterday.Year()),
		Month:      int64(usageDateYesterday.Month()),
		DryRun:     false,
	})

	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)

	client.ValidateQueue(1, models.WorkerTypeHighWatermarkRolloverHandler)
	client.RunHighWatermarkRolloverHandler(1)

	// verify we emit 1 new event to the usage ingestion handler
	client.ValidateQueue(1, models.WorkerTypeUsageIngestion)
}

func matchAmounts(quantity float64, billedAmount float64, appliedCostPerQuantity float64) func(*proto.BillingItem) bool {
	return func(item *proto.BillingItem) bool {
		return item.Quantity == quantity && item.BilledAmount == billedAmount && item.AppliedCostPerQuantity == appliedCostPerQuantity
	}
}
