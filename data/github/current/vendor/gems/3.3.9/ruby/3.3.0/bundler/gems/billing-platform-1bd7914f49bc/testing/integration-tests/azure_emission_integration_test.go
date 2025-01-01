//go:build integration
// +build integration

package integrationtests_test

import (
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
)

func Test_AzureEmission_Messages_With_Invalid_Parameters_Are_Not_Emitted(t *testing.T) {
	tests := []struct {
		name             string
		azureAccountId   string
		billingTarget    proto.BillingTarget
		expectedCount    int64
		expectedDLQCount int64
		enabledProducts  []string
	}{
		{"zuora", uuid.NewString(), proto.BillingTarget_Zuora, 0, 0, []string{}},
		{"azure_no_emit_flag_off", uuid.NewString(), proto.BillingTarget_Azure, 0, 0, []string{}},
		{"azure_no_emit_empty_accountId", "", proto.BillingTarget_Azure, 1, 1, []string{"actions"}},
		{"noTarget", uuid.NewString(), proto.BillingTarget_NoBillingTarget, 0, 0, []string{}},
	}

	for _, tt := range tests {
		name := tt.name
		azureAccountId := tt.azureAccountId
		billingTarget := tt.billingTarget
		expectedCount := tt.expectedCount
		expectedDLQCount := tt.expectedDLQCount
		enabledProducts := tt.enabledProducts

		t.Run(name, func(t *testing.T) {
			client, g := integration.NewTestClient(t, integration.ClientOptions{})
			defer client.Close()

			pricing := client.EnsureSpecificPricingExists(0.08, "actions_linux", "actions", "Actions")
			quantity := 100.121220

			// create customer that the azure emission scheduler will find and emit usage for
			customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(billingTarget, azureAccountId)
			customerProto.EnabledProducts = enabledProducts
			_ = client.CreateCustomer(customerProto)

			// Create usage with date of yesterday as this is what the job looks for when attempting emission to Azure
			now := time.Now().UTC()
			yesterday := now.AddDate(0, 0, -1)

			usageDate := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour(), 0, 0, 0, time.UTC)
			usage := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerProto.CustomerId, usageDate)
			usages := []*hydroSchema.Usage{usage}

			client.ProduceMeteredUsage(usages)
			client.RunUsageIngestion(len(usages))
			client.ValidateQueue(expectedCount, models.WorkerTypeCustomerAzureEmissionDailyRollup)
			client.RunAzureDailyRollupJob(len(usages))

			client.ValidateQueue(0, models.WorkerTypeAzureEmission)

			// Send an azure emission request message to the request-handler queue to trigger azure emission
			client.ScheduleAzureEmissionWithTime(yesterday)

			// Ensure our request made it to the queue but no azure emissions are queued yet
			client.ValidateQueue(1, models.WorkerTypeRequestHandler)
			client.ValidateQueue(0, models.WorkerTypeAzureEmission)

			// Fan out the usage line items to the azure emission queue
			client.RunRequestHandler(1)

			client.ValidateQueue(expectedCount, models.WorkerTypeAzureEmission)

			// Process the Azure emission queue
			client.RunAzureEmission(len(usages))
			client.ValidateQueue(0, models.WorkerTypeAzureEmission)

			// There should be no items in the dead letter queue
			client.ValidateDeadLetterQueue(expectedDLQCount, models.WorkerTypeAzureEmission)

			eventId := models.GenerateAzureEventId(azureAccountId, customerProto.CustomerId, pricing.AzureMeterId, *models.NewUsageTimeFromTime(usageDate))
			azureUsages, _ := client.GetUsageEntitiesFromAzureStorage(eventId)

			g.Expect(azureUsages).Should(gomega.HaveLen(0))
		})
	}
}

func Test_AzureEmission_Messages_On_Disabled_Skus_Are_Not_Emitted(t *testing.T) {
	client, _ := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// Make sure the test is honoring the hardcoded sku
	v2Pricing := engines.AllProductSkuV2()["codespaces_compute_d4"]
	quantity := 100.121220

	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProto)

	// Create usage with date of yesterday as this is what the job looks for when attempting emission to Azure
	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)

	usageDate := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour(), 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), v2Pricing.Sku, quantity, customerProto.CustomerId, usageDate)
	usages := []*hydroSchema.Usage{usage}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	// No messages in the azure emission queue since the sku is disabled
	client.ValidateQueue(0, models.WorkerTypeCustomerAzureEmissionDailyRollup)
}

func Test_AzureEmission_Messages_On_Free_Skus_Are_Not_Emitted(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureFreePricingExists("actions_linux", "actions", "Actions")
	quantity := 100.121220

	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProto)

	// Create usage with date of yesterday as this is what the job looks for when attempting emission to Azure
	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)

	usageDate := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour(), 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerProto.CustomerId, usageDate)
	usages := []*hydroSchema.Usage{usage}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.ValidateQueue(1, models.WorkerTypeCustomerAzureEmissionDailyRollup)
	client.RunAzureDailyRollupJob(len(usages))

	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Send an azure emission request message to the request-handler queue to trigger azure emission
	client.ScheduleAzureEmissionWithTime(yesterday)

	// Ensure our request made it to the queue but no azure emissions are queued yet
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Fan out the usage line items to the azure emission queue
	client.RunRequestHandler(1)

	client.ValidateQueue(1, models.WorkerTypeAzureEmission)

	// Process the Azure emission queue

	client.RunAzureEmission(len(usages))
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// There should be no items in the dead letter queue
	client.ValidateDeadLetterQueue(0, models.WorkerTypeAzureEmission)

	eventId := models.GenerateAzureEventId(customerProto.AzureAccountId, customerProto.CustomerId, pricing.AzureMeterId, *models.NewUsageTimeFromTime(usageDate))
	azureUsages, _ := client.GetUsageEntitiesFromAzureStorage(eventId)

	g.Expect(azureUsages).Should(gomega.HaveLen(0))
}

func Test_AzureEmission_Messages_On_Skus_Without_Azure_Meter_Are_Not_Emitted(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAzureMeterID(0.08, "actions_linux", "actions", "")

	quantity := 100.121220

	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProto)

	// Create usage with date of yesterday as this is what the job looks for when attempting emission to Azure
	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)

	usageDate := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour(), 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerProto.CustomerId, usageDate)
	usages := []*hydroSchema.Usage{usage}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.ValidateQueue(1, models.WorkerTypeCustomerAzureEmissionDailyRollup)
	client.RunAzureDailyRollupJob(len(usages))

	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Send an azure emission request message to the request-handler queue to trigger azure emission
	client.ScheduleAzureEmissionWithTime(yesterday)

	// Ensure our request made it to the queue but no azure emissions are queued yet
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Fan out the usage line items to the azure emission queue
	client.RunRequestHandler(1)

	client.ValidateQueue(1, models.WorkerTypeAzureEmission)

	// Process the Azure emission queue

	client.RunAzureEmission(len(usages))
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// There should be no items in the dead letter queue
	client.ValidateDeadLetterQueue(0, models.WorkerTypeAzureEmission)

	eventId := models.GenerateAzureEventId(customerProto.AzureAccountId, customerProto.CustomerId, pricing.AzureMeterId, *models.NewUsageTimeFromTime(usageDate))
	azureUsages, _ := client.GetUsageEntitiesFromAzureStorage(eventId)

	g.Expect(azureUsages).Should(gomega.HaveLen(0))
}

func Test_AzureEmission_Messages_With_Zero_Quantities_Are_Not_Emitted(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(0.08, "actions_linux", "actions", "Actions")
	quantity := 100.121220

	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProto)

	// Create usage with date of yesterday as this is what the job looks for when attempting emission to Azure
	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)
	nextYear := now.AddDate(1, 0, 0)
	// Apply 100% discount to SKU usage
	discount := stubs.CreatePercentageDiscount(
		customerProto.CustomerId,
		[]*proto.DiscountTarget{
			{
				Id:   pricing.Sku,
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		100.0,
		yesterday.Unix(),
		nextYear.Unix(),
	)
	_, err := client.CreateDiscount(discount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create discount failed")

	usageDate := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour(), 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerProto.CustomerId, usageDate)
	usages := []*hydroSchema.Usage{usage}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.ValidateQueue(1, models.WorkerTypeCustomerAzureEmissionDailyRollup)
	client.RunAzureDailyRollupJob(len(usages))
	client.RunDailyJob(len(usages))

	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Send an azure emission request message to the request-handler queue to trigger azure emission
	client.ScheduleAzureEmissionWithTime(yesterday)

	// Ensure our request made it to the queue but no azure emissions are queued yet
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Fan out the usage line items to the azure emission queue
	client.RunRequestHandler(1)

	client.ValidateQueue(1, models.WorkerTypeAzureEmission)

	// Process the Azure emission queue

	client.RunAzureEmission(len(usages))
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// There should be no items in the dead letter queue
	client.ValidateDeadLetterQueue(0, models.WorkerTypeAzureEmission)

	eventId := models.GenerateAzureEventId(customerProto.AzureAccountId, customerProto.CustomerId, pricing.AzureMeterId, *models.NewUsageTimeFromTime(usageDate))
	azureUsages, _ := client.GetUsageEntitiesFromAzureStorage(eventId)

	g.Expect(azureUsages).Should(gomega.HaveLen(0))

	azureEmission := client.GetAzureEmission(customerProto.CustomerId, pricing.Sku, usageDate)
	g.Expect(azureEmission.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(azureEmission.AzureEmission.MeterId).Should(gomega.Equal(pricing.AzureMeterId))
	g.Expect(azureEmission.AzureEmission.SubscriptionId).Should(gomega.Equal(customerProto.AzureAccountId))
	g.Expect(azureEmission.AzureEmission.Quantity).Should(gomega.Equal(0.0))
	g.Expect(azureEmission.AzureEmission.GrossQuantity).Should(gomega.Equal(quantity))
	g.Expect(azureEmission.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Ignored))
}

func Test_AzureEmission_We_Emit_To_Azure_Commerce_Table(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the azure emission scheduler will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProto)

	pricing1 := client.EnsureSpecificPricingExists(20.0, "actions_linux_4_core", "actions", "Actions")
	pricing2 := client.EnsureSpecificPricingExists(30.0, "actions_linux_8_core", "actions", "Actions")
	quantity := 1.0
	discountUnit := 0.1

	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)
	nextYear := now.AddDate(1, 0, 0)
	yesterdayHourLater := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour()+1, 0, 0, 0, time.UTC)

	// Apply 10% discount to actions_linux SKU usage
	discount := stubs.CreatePercentageDiscount(
		customerProto.CustomerId,
		[]*proto.DiscountTarget{
			{
				Id:   pricing1.Sku,
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		10.0,
		yesterday.Unix(),
		nextYear.Unix(),
	)
	_, err := client.CreateDiscount(discount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create discount failed")

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, quantity, customerProto.CustomerId, yesterday)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, quantity, customerProto.CustomerId, yesterdayHourLater)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing2.Sku, quantity, customerProto.CustomerId, yesterdayHourLater)
	usages := []*hydroSchema.Usage{usage1, usage2, usage3}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.ValidateQueue(3, models.WorkerTypeCustomerAzureEmissionDailyRollup)

	// Perform azure daily rollup and regular daily rollup (to ensure discount totals are created for day)
	client.RunAzureDailyRollupJob(len(usages))
	client.RunDailyJob(len(usages))

	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Send an azure emission request message to the request-handler queue to trigger azure emission
	client.ScheduleAzureEmissionWithTime(yesterday)

	// Ensure our request made it to the queue but no azure emissions are queued yet
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Fan out the usage line items to the azure emission queue
	client.RunRequestHandler(1)

	// We expect 2 usages in the emission queue instead of 3 due to the rollup
	client.ValidateQueue(2, models.WorkerTypeAzureEmission)

	// Process the Azure emission queue
	client.RunAzureEmission(len(usages))
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// There should be no items in the dead letter queue
	client.ValidateDeadLetterQueue(0, models.WorkerTypeAzureEmission)

	client.ValidateAzureEmission(customerProto.CustomerId, customerProto.AzureAccountId, pricing1.AzureMeterId, yesterday, quantity*2-quantity*2*discountUnit) // Sku1, different hours, but same day
	client.ValidateAzureEmission(customerProto.CustomerId, customerProto.AzureAccountId, pricing2.AzureMeterId, yesterdayHourLater, quantity)                  // Sku2

	// Verify that the Azure Emission record is persisted
	azureEmission1 := client.GetAzureEmission(customerProto.CustomerId, pricing1.Sku, yesterday)
	g.Expect(azureEmission1.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(azureEmission1.AzureEmission.MeterId).Should(gomega.Equal(pricing1.AzureMeterId))
	g.Expect(azureEmission1.AzureEmission.SubscriptionId).Should(gomega.Equal(customerProto.AzureAccountId))
	g.Expect(azureEmission1.AzureEmission.Quantity).Should(gomega.Equal(quantity*2 - quantity*2*discountUnit))
	g.Expect(azureEmission1.AzureEmission.GrossQuantity).Should(gomega.Equal(quantity * 2))
	g.Expect(azureEmission1.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))

	azureEmission2 := client.GetAzureEmission(customerProto.CustomerId, pricing2.Sku, yesterdayHourLater)
	g.Expect(azureEmission2.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(azureEmission2.AzureEmission.MeterId).Should(gomega.Equal(pricing2.AzureMeterId))
	g.Expect(azureEmission2.AzureEmission.SubscriptionId).Should(gomega.Equal(customerProto.AzureAccountId))
	g.Expect(azureEmission2.AzureEmission.Quantity).Should(gomega.Equal(quantity))
	g.Expect(azureEmission2.AzureEmission.GrossQuantity).Should(gomega.Equal(quantity))
	g.Expect(azureEmission2.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))

	// run the azure emission again to ensure that the azure emission is not duplicated.
	client.ScheduleAzureEmissionWithTime(yesterday)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.ValidateQueue(2, models.WorkerTypeAzureEmission)
	client.RunAzureEmission(len(usages))
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)
	client.ValidateDeadLetterQueue(0, models.WorkerTypeAzureEmission)
}

func Test_AzureEmission_We_Emit_To_Azure_Commerce_Table_With_Watermark_Above_Plan_Discount(t *testing.T) {
	t.Skip(`Skipping until we can fix the issue of floats not being equal on L465.
					Expected
						<float64>: 1666.6666666660003
					to equal
						<float64>: 1666.666666666`)
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the azure emission scheduler will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProto)

	client.EnsureProductExists("actions", "Actions", "GitHub Actions Usage")
	pricing1 := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)

	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)
	twoDaysAgo := now.AddDate(0, 0, -2)
	nextYear := now.AddDate(1, 0, 0)

	// Create watermark event with date of 'two days ago' so that we can run the watermark job 'yesterday'
	// A usage date of 'yesterday' is what the Azure emission needs to find the usage
	usageDateTwoDaysAgo := time.Date(twoDaysAgo.Year(), twoDaysAgo.Month(), twoDaysAgo.Day(), twoDaysAgo.Hour(), 0, 0, 0, time.UTC)

	daysInMonth := float64(time.Date(usageDateTwoDaysAgo.Year(), usageDateTwoDaysAgo.Month()+1, 0, 0, 0, 0, 0, time.UTC).Day())

	discountAmount := 12.5
	// discountQuantity = $12.50 / 0.0008 = 15625
	convertedDiscountQuantity := nano.NewFromFloat(15625.0 / daysInMonth)
	convertedDiscountQuantityFloat := nano.ToDecimalAmount[int64](convertedDiscountQuantity.Int64())

	quantity := 50000.0

	discount := stubs.CreateDollarDiscount(
		customerProto.CustomerId,
		[]*proto.DiscountTarget{
			{
				Id:   pricing1.Sku,
				Type: proto.DiscountTargetType_EnterpriseDiscount,
			},
		},
		discountAmount,
		twoDaysAgo.Unix(),
		nextYear.Unix(),
	)

	_, err := client.CreateDiscount(discount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create discount failed")

	quantityGiBMonth := nano.NewFromFloat(quantity / daysInMonth)
	quantityGiBMonthFloat := nano.ToDecimalAmount[int64](quantityGiBMonth.Int64())

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, quantity, customerProto.CustomerId, usageDateTwoDaysAgo)
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestionWithTimeTravel(len(usages), usageDateTwoDaysAgo)

	// Send an watermark jobs request message to the request-handler queue
	client.ScheduleWatermarkJobs(yesterday, pricing1.Sku)

	// Ensure our request made it to the queue
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeWatermarkHandler)
	client.RunWatermarkHandler(1)
	client.ValidateQueue(1, models.WorkerTypeUsageIngestion)
	client.RunUsageIngestionWithTimeTravel(1, yesterday)
	client.RunDailyJobWithTimeTravel(len(usages), yesterday)

	u := client.GetUsageLineItems("", "", customerProto.CustomerId, yesterday, proto.BillingPeriod_Hourly)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should not be created yet")

	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Send an azure emission request message to the request-handler queue to trigger azure emission
	client.ScheduleAzureEmissionWithTime(yesterday)

	client.ValidateQueue(1, models.WorkerTypeCustomerAzureEmissionDailyRollup)

	// Perform azure daily rollup and regular daily rollup (to ensure discount totals are created for day)
	client.RunAzureDailyRollupJob(len(usages))
	client.RunDailyJob(len(usages))

	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Ensure our request made it to the queue but no azure emissions are queued yet
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Fan out the usage line items to the azure emission queue
	client.RunRequestHandler(1)

	// We expect 1 usages in the emission queue
	client.ValidateQueue(1, models.WorkerTypeAzureEmission)

	// Process the Azure emission queue
	client.RunAzureEmission(len(usages))
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// There should be no items in the dead letter queue
	client.ValidateDeadLetterQueue(0, models.WorkerTypeAzureEmission)

	client.ValidateAzureEmission(customerProto.CustomerId, customerProto.AzureAccountId, pricing1.AzureMeterId, yesterday, quantityGiBMonthFloat)

	allDiscountsResponse, err := client.GetAllDiscounts(customerProto.CustomerId)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "get all discounts")
	g.Expect(len(allDiscountsResponse.Discounts)).Should(gomega.Equal(1))

	// Verify that the Azure Emission record is persisted
	azureEmission1 := client.GetAzureEmission(customerProto.CustomerId, pricing1.Sku, yesterday)
	g.Expect(azureEmission1.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(azureEmission1.AzureEmission.MeterId).Should(gomega.Equal(pricing1.AzureMeterId))
	g.Expect(azureEmission1.AzureEmission.SubscriptionId).Should(gomega.Equal(customerProto.AzureAccountId))

	// the discount should be applied to the usage quantity
	g.Expect(azureEmission1.AzureEmission.Quantity).Should(gomega.Equal(quantityGiBMonthFloat - convertedDiscountQuantityFloat))
	g.Expect(azureEmission1.AzureEmission.GrossQuantity).Should(gomega.Equal(quantityGiBMonthFloat))
	g.Expect(azureEmission1.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))
}

func Test_AzureEmission_We_Emit_To_Azure_Commerce_Table_With_Watermark_Below_Plan_Discount(t *testing.T) {
	t.Skip(`Skipping until we can fix this flaky test.
					Expected
						<float64>: 0.520833333
					to equal
						<float64>: 0.504032258`)

	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the azure emission scheduler will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProto)

	client.EnsureProductExists("actions", "Actions", "GitHub Actions Usage")
	pricing1 := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)

	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)
	twoDaysAgo := now.AddDate(0, 0, -2)
	nextYear := now.AddDate(1, 0, 0)

	// Create watermark event with date of 'two days ago' so that we can run the watermark job 'yesterday'
	// A usage date of 'yesterday' is what the Azure emission needs to find the usage
	usageDateTwoDaysAgo := time.Date(twoDaysAgo.Year(), twoDaysAgo.Month(), twoDaysAgo.Day(), twoDaysAgo.Hour(), 0, 0, 0, time.UTC)

	daysInMonth := float64(time.Date(usageDateTwoDaysAgo.Year(), usageDateTwoDaysAgo.Month()+1, 0, 0, 0, 0, 0, time.UTC).Day())
	hoursInDay := float64(24)

	discountAmount := 12.5
	quantity := 375.0

	discount := stubs.CreateDollarDiscount(
		customerProto.CustomerId,
		[]*proto.DiscountTarget{
			{
				Id:   pricing1.Sku,
				Type: proto.DiscountTargetType_EnterpriseDiscount,
			},
		},
		discountAmount,
		twoDaysAgo.Unix(),
		nextYear.Unix(),
	)

	_, err := client.CreateDiscount(discount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create discount failed")

	quantityGiBMonth := nano.NewFromFloat(quantity / hoursInDay / daysInMonth)
	quantityGiBMonthFloat := nano.ToDecimalAmount[int64](quantityGiBMonth.Int64())

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, quantity, customerProto.CustomerId, usageDateTwoDaysAgo)
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestionWithTimeTravel(len(usages), usageDateTwoDaysAgo)

	// Send an watermark jobs request message to the request-handler queue
	client.ScheduleWatermarkJobs(yesterday, pricing1.Sku)

	// Ensure our request made it to the queue
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeWatermarkHandler)
	client.RunWatermarkHandler(1)
	client.ValidateQueue(1, models.WorkerTypeUsageIngestion)
	client.RunUsageIngestionWithTimeTravel(1, yesterday)
	client.RunDailyJobWithTimeTravel(len(usages), yesterday)

	u := client.GetUsageLineItems("", "", customerProto.CustomerId, yesterday, proto.BillingPeriod_Hourly)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should not be created yet")

	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Send an azure emission request message to the request-handler queue to trigger azure emission
	client.ScheduleAzureEmissionWithTime(yesterday)

	client.ValidateQueue(1, models.WorkerTypeCustomerAzureEmissionDailyRollup)

	// Perform azure daily rollup and regular daily rollup (to ensure discount totals are created for day)
	client.RunAzureDailyRollupJob(len(usages))
	client.RunDailyJob(len(usages))

	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Ensure our request made it to the queue but no azure emissions are queued yet
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Fan out the usage line items to the azure emission queue
	client.RunRequestHandler(1)

	// We expect 1 usages in the emission queue
	client.ValidateQueue(1, models.WorkerTypeAzureEmission)

	// Process the Azure emission queue
	client.RunAzureEmission(len(usages))
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// There should be no items in the dead letter queue
	client.ValidateDeadLetterQueue(0, models.WorkerTypeAzureEmission)

	client.ValidateAzureEmission(customerProto.CustomerId, customerProto.AzureAccountId, pricing1.AzureMeterId, yesterday, quantityGiBMonthFloat)

	allDiscountsResponse, err := client.GetAllDiscounts(customerProto.CustomerId)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "get all discounts")
	g.Expect(len(allDiscountsResponse.Discounts)).Should(gomega.Equal(1))

	// Verify that the Azure Emission record is persisted
	azureEmission1 := client.GetAzureEmission(customerProto.CustomerId, pricing1.Sku, yesterday)
	g.Expect(azureEmission1.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(azureEmission1.AzureEmission.MeterId).Should(gomega.Equal(pricing1.AzureMeterId))
	g.Expect(azureEmission1.AzureEmission.SubscriptionId).Should(gomega.Equal(customerProto.AzureAccountId))
	g.Expect(azureEmission1.AzureEmission.GrossQuantity).Should(gomega.Equal(quantityGiBMonthFloat))
	g.Expect(azureEmission1.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Ignored))

	// the discount should be applied to the usage quantity
	g.Expect(azureEmission1.AzureEmission.Quantity).Should(gomega.Equal(0.0))
}

func Test_AzureEmission_We_Emit_To_Azure_Commerce_Table_For_Cost_Center(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the azure emission scheduler will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProto)

	// create cost center specific usage
	entity := stubs.CreateEntity()
	entity.CustomerId = customerProto.CustomerId
	costCenter := stubs.CreateAzureCostCenterWithCustomerIdAndTargetId(entity.CustomerId)
	response, _ := client.CreateCostCenter(costCenter)
	// Adjusted to access CostCenterKey correctly
	costCenterKey := response.CostCenter.CostCenterKey
	resource := stubs.GetResource(entity, proto.ResourceType_Org)
	_, err := client.CostCenterAddResourceTo(costCenterKey, []*proto.Resource{resource})
	g.Expect(err).ToNot(gomega.HaveOccurred())
	costCenterResponse := client.FindCostCenterFor(entity, "")
	c := costCenterResponse.CostCenterKey
	g.Expect(c).ShouldNot(gomega.BeNil())

	pricing1 := client.EnsureSpecificPricingExists(20.0, "actions_linux_4_core", "actions", "Actions")
	pricing2 := client.EnsureSpecificPricingExists(30.0, "actions_linux_8_core", "actions", "Actions")
	quantity := 1.0
	discountUnit := 0.1

	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)
	nextYear := now.AddDate(1, 0, 0)
	// Apply 10% discount to actions_linux SKU usage
	discount := stubs.CreatePercentageDiscount(
		costCenterKey.Uuid,
		[]*proto.DiscountTarget{
			{
				Id:   pricing1.Sku,
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		10.0,
		yesterday.Unix(),
		nextYear.Unix(),
	)
	_, err = client.CreateDiscount(discount)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create discount failed")

	// Create usage with date of yesterday as this is what the job looks for when attempting emission to Azure
	usageDateThen := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour(), 0, 0, 0, time.UTC)
	usageDateThenHourLater := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour()+1, 0, 0, 0, time.UTC)

	usage1 := stubs.CreateUsageFrom(pricing1, entity, usageDateThen, quantity)
	usage2 := stubs.CreateUsageFrom(pricing1, entity, usageDateThenHourLater, quantity)
	usage3 := stubs.CreateUsageFrom(pricing2, entity, usageDateThenHourLater, quantity)
	usages := []*hydroSchema.Usage{usage1, usage2, usage3}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.ValidateQueue(3, models.WorkerTypeCustomerAzureEmissionDailyRollup)

	// Perform azure daily rollup and regular daily rollup (to ensure discount totals are created for day)
	client.RunAzureDailyRollupJob(len(usages))
	client.RunDailyJob(len(usages))

	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Send an azure emission request message to the request-handler queue to trigger azure emission
	client.ScheduleAzureEmissionWithTime(yesterday)

	// Ensure our request made it to the queue but no azure emissions are queued yet
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Fan out the usage line items to the azure emission queue
	client.RunRequestHandler(1)

	// We expect 2 usages in the emission queue instead of 3 due to the rollup
	client.ValidateQueue(2, models.WorkerTypeAzureEmission)

	// Process the Azure emission queue
	client.RunAzureEmission(len(usages))
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// There should be no items in the dead letter queue
	client.ValidateDeadLetterQueue(0, models.WorkerTypeAzureEmission)

	client.ValidateAzureEmission(costCenterKey.Uuid, costCenterKey.TargetId, pricing1.AzureMeterId, usageDateThen, quantity*2-quantity*2*discountUnit) // Sku1, different hours, but same day
	client.ValidateAzureEmission(costCenterKey.Uuid, costCenterKey.TargetId, pricing2.AzureMeterId, usageDateThenHourLater, quantity)                  // Sku2

	// Verify that the Azure Emission record is persisted
	azureEmission1 := client.GetAzureEmission(costCenterKey.Uuid, pricing1.Sku, usageDateThen)
	g.Expect(azureEmission1.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(azureEmission1.AzureEmission.MeterId).Should(gomega.Equal(pricing1.AzureMeterId))
	g.Expect(azureEmission1.AzureEmission.SubscriptionId).Should(gomega.Equal(costCenterKey.TargetId))
	g.Expect(azureEmission1.AzureEmission.Quantity).Should(gomega.Equal(quantity*2 - quantity*2*discountUnit))
	g.Expect(azureEmission1.AzureEmission.GrossQuantity).Should(gomega.Equal(quantity * 2))
	g.Expect(azureEmission1.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))

	azureEmission2 := client.GetAzureEmission(costCenterKey.Uuid, pricing2.Sku, usageDateThenHourLater)
	g.Expect(azureEmission2.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(azureEmission2.AzureEmission.MeterId).Should(gomega.Equal(pricing2.AzureMeterId))
	g.Expect(azureEmission2.AzureEmission.SubscriptionId).Should(gomega.Equal(costCenterKey.TargetId))
	g.Expect(azureEmission2.AzureEmission.Quantity).Should(gomega.Equal(quantity))
	g.Expect(azureEmission2.AzureEmission.GrossQuantity).Should(gomega.Equal(quantity))
	g.Expect(azureEmission2.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))
}

func Test_AzureEmission_We_Emit_To_Azure_Commerce_Table_For_Cost_Center_And_Customer_With_Different_Subscriptions(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the azure emission scheduler will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProto)

	// create cost center specific usage with target ID
	entityTargetId := stubs.CreateEntity()
	entityTargetId.CustomerId = customerProto.CustomerId
	costCenter := stubs.CreateAzureCostCenterWithCustomerIdAndTargetId(entityTargetId.CustomerId)
	response, _ := client.CreateCostCenter(costCenter)
	costCenterKey := response.CostCenter.CostCenterKey
	resource := stubs.GetResource(entityTargetId, proto.ResourceType_Org)
	_, err := client.CostCenterAddResourceTo(costCenterKey, []*proto.Resource{resource})
	g.Expect(err).ToNot(gomega.HaveOccurred())
	costCenterResponse := client.FindCostCenterFor(entityTargetId, "")
	g.Expect(costCenterResponse.CostCenterKey).ShouldNot(gomega.BeNil())

	// create cost center specific usage without target ID, this is a valid case and the cost center
	// should be billed using the parent enterprise subscription
	entityWithoutTargetId := stubs.CreateEntity()
	entityWithoutTargetId.CustomerId = customerProto.CustomerId
	costCenterNoTargetId := stubs.CreateAzureCostCenterWithCustomerId(entityWithoutTargetId.CustomerId)
	costCenterNoTargetId.CostCenterKey.TargetId = ""
	responseNoTargetId, _ := client.CreateCostCenter(costCenterNoTargetId)
	costCenterKeyNoTargetId := responseNoTargetId.CostCenter.CostCenterKey
	resource = stubs.GetResource(entityWithoutTargetId, proto.ResourceType_Org)
	_, err = client.CostCenterAddResourceTo(costCenterKeyNoTargetId, []*proto.Resource{resource})
	g.Expect(err).ToNot(gomega.HaveOccurred())
	costCenterResponseNoTargetId := client.FindCostCenterFor(entityWithoutTargetId, "")
	g.Expect(costCenterResponseNoTargetId.CostCenterKey).ShouldNot(gomega.BeNil())

	pricing := client.EnsureSpecificPricingExists(20.0, "actions_linux_4_core", "actions", "Actions")
	quantity := 1.0

	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)

	// Create usage with date of yesterday as this is what the job looks for when attempting emission to Azure
	usageDateThen := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour(), 0, 0, 0, time.UTC)
	usageDateThenHourLater := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour()+1, 0, 0, 0, time.UTC)

	usageCostCenterWithTargetId := stubs.CreateUsageFrom(pricing, entityTargetId, usageDateThen, quantity)
	usageCostCenterWithoutTargetId := stubs.CreateUsageFrom(pricing, entityWithoutTargetId, usageDateThen, quantity)
	usageCustomer := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerProto.CustomerId, usageDateThenHourLater)
	usages := []*hydroSchema.Usage{usageCustomer, usageCostCenterWithTargetId, usageCostCenterWithoutTargetId}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.ValidateQueue(3, models.WorkerTypeCustomerAzureEmissionDailyRollup)

	// Perform azure daily rollup and regular daily rollup (to ensure discount totals are created for day)
	client.RunAzureDailyRollupJob(len(usages))
	client.RunDailyJob(len(usages))

	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Send an azure emission request message to the request-handler queue to trigger azure emission
	client.ScheduleAzureEmissionWithTime(yesterday)

	// Ensure our request made it to the queue but no azure emissions are queued yet
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Fan out the usage line items to the azure emission queue
	client.RunRequestHandler(1)

	// We expect 2 usages in the emission queue instead of 3 due to the rollup
	client.ValidateQueue(3, models.WorkerTypeAzureEmission)

	// Process the Azure emission queue
	client.RunAzureEmission(len(usages))
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// There should be no items in the dead letter queue
	client.ValidateDeadLetterQueue(0, models.WorkerTypeAzureEmission)

	client.ValidateAzureEmission(costCenterKey.Uuid, costCenterKey.TargetId, pricing.AzureMeterId, usageDateThen, quantity)
	client.ValidateAzureEmission(costCenterKeyNoTargetId.Uuid, customerProto.AzureAccountId, pricing.AzureMeterId, usageDateThen, quantity)
	client.ValidateAzureEmission(customerProto.CustomerId, customerProto.AzureAccountId, pricing.AzureMeterId, usageDateThenHourLater, quantity)

	// Verify that the Azure Emission record is persisted
	azureEmissionCostCenter := client.GetAzureEmission(costCenterKey.Uuid, pricing.Sku, usageDateThen)
	g.Expect(azureEmissionCostCenter.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(azureEmissionCostCenter.AzureEmission.MeterId).Should(gomega.Equal(pricing.AzureMeterId))
	g.Expect(azureEmissionCostCenter.AzureEmission.SubscriptionId).Should(gomega.Equal(costCenterKey.TargetId))
	g.Expect(azureEmissionCostCenter.AzureEmission.Quantity).Should(gomega.Equal(quantity))
	g.Expect(azureEmissionCostCenter.AzureEmission.GrossQuantity).Should(gomega.Equal(quantity))
	g.Expect(azureEmissionCostCenter.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))

	azureEmissionCostCenterNoTargetId := client.GetAzureEmission(costCenterKeyNoTargetId.Uuid, pricing.Sku, usageDateThen)
	g.Expect(azureEmissionCostCenterNoTargetId.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(azureEmissionCostCenterNoTargetId.AzureEmission.MeterId).Should(gomega.Equal(pricing.AzureMeterId))
	g.Expect(azureEmissionCostCenterNoTargetId.AzureEmission.SubscriptionId).Should(gomega.Equal(customerProto.AzureAccountId))
	g.Expect(azureEmissionCostCenterNoTargetId.AzureEmission.Quantity).Should(gomega.Equal(quantity))
	g.Expect(azureEmissionCostCenterNoTargetId.AzureEmission.GrossQuantity).Should(gomega.Equal(quantity))
	g.Expect(azureEmissionCostCenterNoTargetId.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))

	azureEmissionCustomer := client.GetAzureEmission(customerProto.CustomerId, pricing.Sku, usageDateThen)
	g.Expect(azureEmissionCustomer.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(azureEmissionCustomer.AzureEmission.MeterId).Should(gomega.Equal(pricing.AzureMeterId))
	g.Expect(azureEmissionCustomer.AzureEmission.SubscriptionId).Should(gomega.Equal(customerProto.AzureAccountId))
	g.Expect(azureEmissionCustomer.AzureEmission.Quantity).Should(gomega.Equal(quantity))
	g.Expect(azureEmissionCustomer.AzureEmission.GrossQuantity).Should(gomega.Equal(quantity))
	g.Expect(azureEmissionCustomer.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))

	// assert that the usage was sent to different subscription IDs
	g.Expect(azureEmissionCustomer.AzureEmission.SubscriptionId).ShouldNot(gomega.Equal(azureEmissionCostCenter.AzureEmission.SubscriptionId))
	g.Expect(azureEmissionCustomer.AzureEmission.AzurePartitionKey).ShouldNot(gomega.Equal(azureEmissionCostCenter.AzureEmission.AzurePartitionKey))
}

func Test_AzureEmission_Emission_Of_High_Watermark_Usage(t *testing.T) {
	t.Skip(`Skipping until we can fix the issue of the floats not matching up.
						Expected
							<float64>: 0.096774192
						to equal
							<float64>: 0.09677419200000001`)
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(19.0, "copilot_for_business", "copilot", proto.PricingMeterType_DailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)
	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 1.0
	today := time.Now().UTC()

	// add 3 seats individually
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerID, today)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerID, today)
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerID, today)
	usages := []*hydroSchema.Usage{usage1, usage2, usage3}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.ProcessAzureEmission(today, len(usages), 1)
	hourLater := today.Add(time.Hour)
	client.ValidateAzureEmission(customerProto.CustomerId, customerProto.AzureAccountId, pricing.AzureMeterId, hourLater, quantity)

	azureEmission := client.GetAzureEmission(customerProto.CustomerId, pricing.Sku, today)
	expectedDailyQuantity := 3.0 * client.DailyHighWatermarkForMonth(today)
	g.Expect(azureEmission.AzureEmission.Quantity).To(gomega.Equal(expectedDailyQuantity))
	g.Expect(azureEmission.AzureEmission.GrossQuantity).Should(gomega.Equal(azureEmission.AzureEmission.Quantity))
	g.Expect(azureEmission.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))
}

func Test_AzureEmission_Emission_Of_Multiple_High_Watermark_Skus(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing1 := client.EnsureSpecificPricingExistsWithAll(19.0, "copilot_for_business", "copilot", proto.PricingMeterType_DailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)
	pricing2 := client.EnsureSpecificPricingExistsWithAll(21.0, "ghec_seats", "ghec", proto.PricingMeterType_DailyUnitCharge, "GHEC seats", proto.UnitType_UserMonths)

	quantity := 1.0

	today := time.Now().UTC()

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, quantity, customerID, today)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing2.Sku, quantity, customerID, today)

	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.ProcessAzureEmission(today, len(usages), 2)
	hourLater := today.Add(time.Hour)
	client.ValidateAzureEmission(customerID, customerProto.AzureAccountId, pricing1.AzureMeterId, hourLater, quantity)
	client.ValidateAzureEmission(customerID, customerProto.AzureAccountId, pricing2.AzureMeterId, hourLater, quantity)

	expectedDailyQuantity := client.DailyHighWatermarkForMonth(today)

	azureEmission1 := client.GetAzureEmission(customerID, pricing1.Sku, today)
	g.Expect(azureEmission1.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(azureEmission1.AzureEmission.MeterId).Should(gomega.Equal(pricing1.AzureMeterId))
	g.Expect(azureEmission1.AzureEmission.SubscriptionId).Should(gomega.Equal(customerProto.AzureAccountId))
	g.Expect(azureEmission1.AzureEmission.Quantity).To(gomega.Equal(expectedDailyQuantity))
	g.Expect(azureEmission1.AzureEmission.GrossQuantity).Should(gomega.Equal(azureEmission1.AzureEmission.Quantity))
	g.Expect(azureEmission1.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))

	azureEmission2 := client.GetAzureEmission(customerID, pricing2.Sku, today)
	g.Expect(azureEmission2.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(azureEmission2.AzureEmission.MeterId).Should(gomega.Equal(pricing2.AzureMeterId))
	g.Expect(azureEmission2.AzureEmission.SubscriptionId).Should(gomega.Equal(customerProto.AzureAccountId))
	g.Expect(azureEmission2.AzureEmission.Quantity).To(gomega.Equal(expectedDailyQuantity))
	g.Expect(azureEmission2.AzureEmission.GrossQuantity).Should(gomega.Equal(azureEmission2.AzureEmission.Quantity))
	g.Expect(azureEmission2.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))
}

func Test_AzureEmission_Emission_Of_Offboarded_High_Watermark_And_Non_High_Watermark_Products(t *testing.T) {
	t.Skip(`Skipping until we can fix the issue of the queue having the wrong amount of items in it.
						Expected
							<int64>: 1
						to equal
							<int64>: 2`)
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	hwmPricing := client.EnsureSpecificPricingExistsWithAll(19.0, "copilot_for_business", "copilot", proto.PricingMeterType_DailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)
	regularPricing := client.EnsureSpecificPricingExists(30.0, "actions_linux_8_core", "actions", "Actions")

	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	// Customer is onboarded to Copilot and Actions
	customerProto.EnabledProducts = []string{hwmPricing.Product, regularPricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 1.0
	today := time.Now().UTC()
	hwmUsage := stubs.CreateUsage(uuid.NewString(), hwmPricing.Sku, quantity, customerID, today)
	regularUsage := stubs.CreateUsage(uuid.NewString(), regularPricing.Sku, quantity, customerID, today)
	usages := []*hydroSchema.Usage{hwmUsage, regularUsage}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	// Offboard customer from Copilot and Actions
	customerProto.EnabledProducts = []string{}
	_ = client.PatchCustomer(customerProto)

	hwmUsage = stubs.CreateUsage(uuid.NewString(), hwmPricing.Sku, quantity, customerID, today)
	regularUsage = stubs.CreateUsage(uuid.NewString(), regularPricing.Sku, quantity, customerID, today)
	usages2 := []*hydroSchema.Usage{hwmUsage, regularUsage}

	client.ProduceMeteredUsage(usages2)
	client.RunUsageIngestion(len(usages2))

	// The largest possible queue depth is 31
	// 1 usage per day * 31 days for Copilot + 1 usage (for Actions)
	queueDepth := 31
	client.RunAzureDailyRollupJob(queueDepth)
	client.RunDailyJob(queueDepth)
	client.ScheduleAzureEmissionWithTime(today)

	// Ensure our request made it to the queue but no azure emissions are queued yet
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// Fan out the usage line items to the azure emission queue
	client.RunRequestHandler(2)
	client.ValidateQueue(2, models.WorkerTypeAzureEmission)

	// Process the Azure emission queue
	client.RunAzureEmission(queueDepth)
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)

	// High watermark product should not be emitted once customer is offboarded from it
	hwmAzureEmission := client.GetAzureEmission(customerProto.CustomerId, hwmPricing.Sku, today)
	g.Expect(hwmAzureEmission.AzureEmission.AzurePartitionKey).Should(gomega.Equal(""))
	g.Expect(hwmAzureEmission.AzureEmission.MeterId).Should(gomega.Equal(""))
	g.Expect(hwmAzureEmission.AzureEmission.SubscriptionId).Should(gomega.Equal(""))
	g.Expect(hwmAzureEmission.AzureEmission.Quantity).Should(gomega.Equal(0.0))
	g.Expect(hwmAzureEmission.AzureEmission.GrossQuantity).Should(gomega.Equal(0.0))
	g.Expect(hwmAzureEmission.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_New))

	// Other products should be emitted even as the customer is offboarded
	// But only the quantity before the customer was offboarded
	regularAzureEmission := client.GetAzureEmission(customerProto.CustomerId, regularPricing.Sku, today)
	g.Expect(regularAzureEmission.AzureEmission.AzurePartitionKey).ShouldNot(gomega.BeNil())
	g.Expect(regularAzureEmission.AzureEmission.MeterId).Should(gomega.Equal(regularPricing.AzureMeterId))
	g.Expect(regularAzureEmission.AzureEmission.SubscriptionId).Should(gomega.Equal(customerProto.AzureAccountId))
	g.Expect(regularAzureEmission.AzureEmission.Quantity).Should(gomega.Equal(quantity))
	g.Expect(regularAzureEmission.AzureEmission.GrossQuantity).Should(gomega.Equal(quantity))
	g.Expect(regularAzureEmission.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))
}

func Test_AzureEmission_Emission_Of_High_Watermark_With_Dollar_Discount(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(19.0, "copilot_for_business", "copilot", proto.PricingMeterType_DailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 1.0
	discountAmount := 1.0
	today := time.Now().UTC()
	firstOfTheMonth := time.Date(today.Year(), today.Month(), 1, 0, 0, 0, 0, time.UTC)
	tomorrow := today.AddDate(0, 0, 1)
	createDiscountResponse, err := client.CreateDiscount(
		stubs.DollarDiscountForSku(customerID, pricing.Sku, discountAmount, firstOfTheMonth.Unix(), tomorrow.Unix()),
	)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create discount")
	g.Expect(createDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerID, firstOfTheMonth)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerID, firstOfTheMonth)
	usages := []*hydroSchema.Usage{usage1, usage2}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.ProcessAzureEmission(firstOfTheMonth, len(usages), 1)

	hourLater := firstOfTheMonth.Add(time.Hour)
	client.ValidateAzureEmission(customerID, customerProto.AzureAccountId, pricing.AzureMeterId, hourLater, quantity)

	expectedDailyQuantity := 2.0 * client.DailyHighWatermarkForMonth(firstOfTheMonth)

	// $1 / $19 price = 0.0526315789 discount in seats
	// 0.052631578 seats / number of days remaining in month = daily discount
	dailyDiscount := 0.052631578 / float64(client.DaysInMonth(firstOfTheMonth))
	expectedDailyQuantityWithDiscount := expectedDailyQuantity - dailyDiscount

	azureEmission := client.GetAzureEmission(customerProto.CustomerId, pricing.Sku, firstOfTheMonth)
	g.Expect(client.EnforceFloatPrecision(azureEmission.AzureEmission.Quantity, 8)).To(gomega.Equal(client.EnforceFloatPrecision(expectedDailyQuantityWithDiscount, 8)))
	g.Expect(azureEmission.AzureEmission.GrossQuantity).To(gomega.Equal(expectedDailyQuantity))
	g.Expect(azureEmission.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))
}

func Test_AzureEmission_Emission_Of_High_Watermark_With_Percentage_Discount(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExistsWithAll(19.0, "copilot_for_business", "copilot", proto.PricingMeterType_DailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	customerProto.EnabledProducts = []string{pricing.Product}
	customerID := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	quantity := 1.0
	discountAmount := 50.0
	today := time.Now().UTC()
	tomorrow := today.AddDate(0, 0, 1)

	createDiscountResponse, err := client.CreateDiscount(
		stubs.PercentageDiscountForSkuWithDates(customerID, pricing.Sku, discountAmount, today.Unix(), tomorrow.Unix()),
	)
	g.Expect(err).ShouldNot(gomega.HaveOccurred(), "create discount")
	g.Expect(createDiscountResponse.Uuid).ShouldNot(gomega.BeNil())

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.Sku, quantity, customerID, today)
	usages := []*hydroSchema.Usage{usage1}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.ProcessAzureEmission(today, len(usages), 1)
	hourLater := today.Add(time.Hour)
	client.ValidateAzureEmission(customerID, customerProto.AzureAccountId, pricing.AzureMeterId, hourLater, quantity)

	expectedDailyQuantity := 1.0 * client.DailyHighWatermarkForMonth(today)
	expectedDailyQuantityWithDiscount := expectedDailyQuantity * (discountAmount / 100)

	azureEmission := client.GetAzureEmission(customerProto.CustomerId, pricing.Sku, today)
	g.Expect(azureEmission.AzureEmission.GrossQuantity).To(gomega.Equal(expectedDailyQuantity))
	g.Expect(client.EnforceFloatPrecision(azureEmission.AzureEmission.Quantity, 8)).To(gomega.Equal(client.EnforceFloatPrecision(expectedDailyQuantityWithDiscount, 8)))
	g.Expect(azureEmission.AzureEmission.Status).Should(gomega.Equal(proto.AzureEmissionStatus_Completed))
}
