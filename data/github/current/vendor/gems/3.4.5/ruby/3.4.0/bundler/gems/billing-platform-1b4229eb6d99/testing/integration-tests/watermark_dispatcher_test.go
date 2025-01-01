//go:build integration
// +build integration

package integrationtests_test

import (
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
)

func Test_WatermarkDispatcher_TriggerWatermarkWorkflowErrors(t *testing.T) {
	currentTime := models.NewUsageTimeFromTime(time.Now().UTC())

	previousHour := currentTime.WithHour(currentTime.Hour() - 1)
	previousDay := currentTime.WithDay(currentTime.Day() - 1)
	previousMonth := currentTime.WithMonth(currentTime.Month() - 1)
	previousYear := currentTime.WithYear(int64(currentTime.Year() - 1))
	if currentTime.Month() == time.January {
		previousMonth = currentTime.WithMonth(12).WithYear(int64(currentTime.Year() - 1))
	}

	futureHour := currentTime.WithHour(currentTime.Hour() + 1)
	futureDay := currentTime.WithDay(currentTime.Day() + 1)
	futureMonth := currentTime.WithMonth(currentTime.Month() + 1)
	if currentTime.Month() == time.December {
		futureMonth = currentTime.WithMonth(1).WithYear(int64(currentTime.Year() + 1))
	}
	futureYear := currentTime.WithYear(int64(currentTime.Year() + 1))

	tests := []struct {
		name    string
		payload *proto.TriggerWatermarkWorkflowRequest
		success bool
	}{
		{
			"now",
			&proto.TriggerWatermarkWorkflowRequest{
				Year:       int64(currentTime.Year()),
				Month:      int64(currentTime.Month()),
				Day:        int64(currentTime.Day()),
				Hour:       int64(currentTime.Hour()),
				CustomerId: "",
				Sku:        "",
			},
			true,
		},
		{
			"future_hour",
			&proto.TriggerWatermarkWorkflowRequest{
				Year:       int64(futureHour.Year()),
				Month:      int64(futureHour.Month()),
				Day:        int64(futureHour.Day()),
				Hour:       int64(futureHour.Hour()),
				CustomerId: "",
				Sku:        "",
			},
			false,
		},
		{
			"past_hour",
			&proto.TriggerWatermarkWorkflowRequest{
				Year:       int64(previousHour.Year()),
				Month:      int64(previousHour.Month()),
				Day:        int64(previousHour.Day()),
				Hour:       int64(previousHour.Hour()),
				CustomerId: "",
				Sku:        "",
			},
			true,
		},
		{
			"previous_day",
			&proto.TriggerWatermarkWorkflowRequest{
				Year:       int64(previousDay.Year()),
				Month:      int64(previousDay.Month()),
				Day:        int64(previousDay.Day()),
				Hour:       int64(previousDay.Hour()),
				CustomerId: "",
				Sku:        "",
			},
			true,
		},
		{
			"future_day",
			&proto.TriggerWatermarkWorkflowRequest{
				Year:       int64(futureDay.Year()),
				Month:      int64(futureDay.Month()),
				Day:        int64(futureDay.Day()),
				Hour:       int64(futureDay.Hour()),
				CustomerId: "",
				Sku:        "",
			},
			false,
		},
		{
			"previous_month",
			&proto.TriggerWatermarkWorkflowRequest{
				Year:       int64(previousMonth.Year()),
				Month:      int64(previousMonth.Month()),
				Day:        int64(previousMonth.Day()),
				Hour:       int64(previousMonth.Hour()),
				CustomerId: "",
				Sku:        "",
			},
			true,
		},
		{
			"future_month",
			&proto.TriggerWatermarkWorkflowRequest{
				Year:       int64(futureMonth.Year()),
				Month:      int64(futureMonth.Month()),
				Day:        int64(futureMonth.Day()),
				Hour:       int64(futureMonth.Hour()),
				CustomerId: "",
				Sku:        "",
			},
			false,
		},
		{
			"previous_year",
			&proto.TriggerWatermarkWorkflowRequest{
				Year:       int64(previousYear.Year()),
				Month:      int64(previousYear.Month()),
				Day:        int64(previousYear.Day()),
				Hour:       int64(previousYear.Hour()),
				CustomerId: "",
				Sku:        "",
			},
			true,
		},
		{
			"future_year",
			&proto.TriggerWatermarkWorkflowRequest{
				Year:       int64(futureYear.Year()),
				Month:      int64(futureYear.Month()),
				Day:        int64(futureYear.Day()),
				Hour:       int64(futureYear.Hour()),
				CustomerId: "",
				Sku:        "",
			},
			false,
		},
		{
			"day_does_not_exist",
			&proto.TriggerWatermarkWorkflowRequest{
				Year:       int64(2023),
				Month:      int64(2),
				Day:        int64(31),
				Hour:       int64(1),
				CustomerId: "",
				Sku:        "",
			},
			false,
		},
		{
			"zero_day",
			&proto.TriggerWatermarkWorkflowRequest{
				Year:       int64(2023),
				Month:      int64(2),
				Day:        int64(0),
				Hour:       int64(0),
				CustomerId: "",
				Sku:        "",
			},
			false,
		},
		{
			"invalid_customer_id",
			&proto.TriggerWatermarkWorkflowRequest{
				Year:       int64(currentTime.Year()),
				Month:      int64(currentTime.Month()),
				Day:        int64(currentTime.Day()),
				Hour:       int64(currentTime.Hour()),
				CustomerId: "bad-id",
				Sku:        "",
			},
			false,
		},
	}

	for _, tt := range tests {
		tt := tt
		name := tt.name
		payload := tt.payload
		success := tt.success

		t.Run(name, func(t *testing.T) {
			client, g := integration.NewTestClient(t, integration.ClientOptions{})
			defer client.Close()

			if payload.CustomerId == "" {
				customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Azure)
				payload.CustomerId = customerProto.CustomerId
				_ = client.CreateCustomer(customerProto)
			}

			err := client.AdminTriggerWatermarkWorkflow(payload)

			if success {
				g.Expect(err).ShouldNot(gomega.HaveOccurred())
			} else {
				g.Expect(err).Should(gomega.HaveOccurred())
			}
		})
	}
}

func Test_WatermarkDispatcher_TriggerWatermarkWorkflowForSpecificCustomer(t *testing.T) {
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
	later := january2021.WithDay(1).WithHour(5).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId, now)
	usages := []*hydroSchema.Usage{usage1}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})

	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	_ = client.AdminTriggerWatermarkWorkflow(&proto.TriggerWatermarkWorkflowRequest{
		Year:       int64(later.Year()),
		Month:      int64(later.Month()),
		Day:        int64(later.Day()),
		Hour:       int64(later.Hour()),
		CustomerId: customerId,
		Sku:        pricing.GetSku(),
	})
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	client.RunRequestHandler(1)

	// A message made it back to usage ingestion
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(1, models.WorkerTypeWatermarkHandler)

	client.RunWatermarkHandler(1)

	client.ValidateQueue(0, models.WorkerTypeWatermarkHandler)
	client.ValidateQueue(1, models.WorkerTypeUsageIngestion)

	// Run usage ingestion so we can see if the message gets processed
	client.RunUsageIngestion(1)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)
	client.RunDailyJob(1)

	u := client.GetUsageLineItemsGroupBy("", "", customerId, later, proto.BillingPeriod_Hourly, proto.UsageGroupBy_GroupByOrgRepoProductSku)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(1), "a line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))

	// validate the emitted time is for the job run hour triggered by the admin API
	usageAt := models.NewUsageTimeFromUnixMilli(billingItem.UsageAt)

	g.Expect(usageAt.Year()).Should(gomega.Equal(later.Year()))
	g.Expect(usageAt.Month()).Should(gomega.Equal(later.Month()))
	g.Expect(usageAt.Day()).Should(gomega.Equal(later.Day()))
	g.Expect(usageAt.Hour()).Should(gomega.Equal(later.Hour()))
}

func Test_WatermarkDispatcher_TriggerWatermarkWorkflowForAllCustomers(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId1 := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	customerProto = stubs.CreateEnabledCustomerWithTargetAndZuoraAccountNumber(proto.BillingTarget_Zuora, stubs.GetRandomId64AsString())
	customerId2 := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)
	quantity := 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(1).Time
	later := january2021.WithDay(1).WithHour(5).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId1, now)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerId2, now)
	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProcessWatermarkUsage(now, usages, integration.ProcessWatermarkUsageOpts{})

	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	_ = client.AdminTriggerWatermarkWorkflow(&proto.TriggerWatermarkWorkflowRequest{
		Year:       int64(later.Year()),
		Month:      int64(later.Month()),
		Day:        int64(later.Day()),
		Hour:       int64(later.Hour()),
		CustomerId: "",
		Sku:        pricing.GetSku(),
	})
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	client.RunRequestHandler(1)

	// A message made it back to usage ingestion
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(2, models.WorkerTypeWatermarkHandler)

	client.RunWatermarkHandler(2)

	client.ValidateQueue(0, models.WorkerTypeWatermarkHandler)
	client.ValidateQueue(2, models.WorkerTypeUsageIngestion)

	// Run usage ingestion so we can see if the message gets processed
	client.RunUsageIngestion(2)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	// usage for first customer

	u := client.GetUsageLineItemsGroupBy("", "", customerId1, later, proto.BillingPeriod_Hourly, proto.UsageGroupBy_GroupByOrgRepoProductSku)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(1), "a line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))

	// validate the emitted time is for the job run hour triggered by the admin API
	usageAt := models.NewUsageTimeFromUnixMilli(billingItem.UsageAt)

	g.Expect(usageAt.Year()).Should(gomega.Equal(later.Year()))
	g.Expect(usageAt.Month()).Should(gomega.Equal(later.Month()))
	g.Expect(usageAt.Day()).Should(gomega.Equal(later.Day()))
	g.Expect(usageAt.Hour()).Should(gomega.Equal(later.Hour()))

	// usage for second customer

	u = client.GetUsageLineItemsGroupBy("", "", customerId2, later, proto.BillingPeriod_Hourly, proto.UsageGroupBy_GroupByOrgRepoProductSku)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(1), "a line item should be created")

	billingItem = u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(quantity))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(quantity * pricing.GetPrice()))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))

	// validate the emitted time is for the job run hour triggered by the admin API
	usageAt = models.NewUsageTimeFromUnixMilli(billingItem.UsageAt)

	g.Expect(usageAt.Year()).Should(gomega.Equal(later.Year()))
	g.Expect(usageAt.Month()).Should(gomega.Equal(later.Month()))
	g.Expect(usageAt.Day()).Should(gomega.Equal(later.Day()))
	g.Expect(usageAt.Hour()).Should(gomega.Equal(later.Hour()))
}
