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
)

// reference azure blob storage pricing https://learn.microsoft.com/en-us/azure/storage/common/storage-plan-manage-costs
// github current actions storage pricing https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions

// 	GitHub calculates your storage usage for each month based on hourly usage per GB during that month. For example, if you use 3 GB of storage for 10 days of March and 12 GB for 21 days of March, your storage usage would be:

// 	3 GB x 10 days x (24 hours per day) = 720 GB-Hours
// 	12 GB x 21 days x (24 hours per day) = 6,048 GB-Hours
// 	720 GB-Hours + 6,048 GB-Hours = 6,768 total GB-Hours
// 	6,768 GB-Hours / (744 hours per month) = 9.0967 GB-Months
// 	At the end of the month, GitHub rounds your storage to the nearest MB. Therefore, your storage usage for March would be 9.097 GB.

type testUsage struct {
	quantity float64
	usageAt  *models.UsageTime
}

type testData struct {
	testCase        string
	usages          []testUsage
	skuPrice        float64
	hourlyQuantity  float64
	dailyQuantity   float64
	monthlyQuantity float64
	usageDate       *models.UsageTime
}

func Test_PerUnitHourlyMeter_Watermark_GetUsageTotal(t *testing.T) {
	t.Parallel()

	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	january1st2021 := january2021.WithDay(1)
	february1st2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.February).WithDay(1)

	tests := []testData{
		{
			testCase: "1 entry beginning of month",
			usages: []testUsage{{
				quantity: 1,
				usageAt:  january1st2021,
			}},
			skuPrice:        1,
			hourlyQuantity:  1,
			dailyQuantity:   24,
			monthlyQuantity: 744,
			usageDate:       january1st2021,
		},
		{
			testCase: "1 entry beginning of month double quantity",
			usages: []testUsage{{
				quantity: 2,
				usageAt:  january1st2021,
			}},
			skuPrice:        1,
			hourlyQuantity:  2,
			dailyQuantity:   48,
			monthlyQuantity: 1488,
			usageDate:       january1st2021,
		},
		{
			testCase: "1 entry middle of month",
			usages: []testUsage{{
				quantity: 1,
				usageAt:  january2021.WithDay(16).WithHour(12),
			}},
			skuPrice:        1,
			hourlyQuantity:  1,
			dailyQuantity:   12,
			monthlyQuantity: 372,
			usageDate:       january2021.WithDay(16).WithHour(12),
		},
		{
			testCase: "1 entry middle of hour",
			usages: []testUsage{{
				quantity: 1,
				usageAt:  january1st2021.WithMinute(30),
			}},
			skuPrice:        1,
			hourlyQuantity:  0.5,
			dailyQuantity:   23.5,
			monthlyQuantity: 743.5,
			usageDate:       january1st2021.WithMinute(30),
		},

		{
			testCase: "1 entry middle of hour requesting next hour",
			usages: []testUsage{{
				quantity: 1,
				usageAt:  january1st2021.WithMinute(30),
			}},
			skuPrice:        1,
			hourlyQuantity:  1.0,
			dailyQuantity:   23.5,
			monthlyQuantity: 743.5,
			usageDate:       january1st2021.WithHour(2),
		},
		{
			testCase: "1 entry middle of day requesting next day",
			usages: []testUsage{{
				quantity: 1,
				usageAt:  january1st2021.WithHour(12),
			}},
			skuPrice:        1,
			hourlyQuantity:  1.0,
			dailyQuantity:   24.0,
			monthlyQuantity: 732.0,
			usageDate:       january2021.WithDay(2),
		},
		{
			testCase: "requesting monthly when events are in previous month",
			usages: []testUsage{{
				quantity: 1,
				usageAt:  january1st2021.WithHour(12),
			}},
			skuPrice:        1,
			hourlyQuantity:  1.0,
			dailyQuantity:   24.0,
			monthlyQuantity: 672.0,
			usageDate:       february1st2021,
		},
		{
			testCase: "2 entry beginning of month",
			usages: []testUsage{
				{
					quantity: 3,
					usageAt:  january1st2021,
				},
				{
					quantity: 2,
					usageAt:  january1st2021.WithHour(12),
				},
			},
			skuPrice:        1,
			hourlyQuantity:  5,
			dailyQuantity:   96,   // 3 * 24 + 2 * 12
			monthlyQuantity: 3696, // (3 * 24 * 31) + (12 * 2) + (2 * 24 * 30)
			usageDate:       january1st2021.WithHour(12),
		},
		{
			testCase: "2 entry beginning of month with separate day",
			usages: []testUsage{
				{
					quantity: 3,
					usageAt:  january1st2021,
				},
				{
					quantity: 2,
					usageAt:  january2021.WithDay(2),
				},
			},
			skuPrice:        1,
			hourlyQuantity:  3,
			dailyQuantity:   72,   // 3 * 24
			monthlyQuantity: 3672, // (3 * 24 * 31) + (2 * 24 * 30)
			usageDate:       january1st2021.WithHour(1),
		},
		{
			testCase: "2 entry beginning of month same hour",
			usages: []testUsage{
				{
					quantity: 3,
					usageAt:  january1st2021.WithMinute(6),
				},
				{
					quantity: 4,
					usageAt:  january1st2021.WithMinute(54),
				},
			},
			skuPrice:        1,
			hourlyQuantity:  3.1, // 3 * 54/60 + 4 * 6/60
			dailyQuantity:   164.1,
			monthlyQuantity: 5204.1,
			usageDate:       january1st2021,
		},
		{
			testCase: "1 add entry and 1 remove entry",
			usages: []testUsage{
				{
					quantity: 3,
					usageAt:  january1st2021,
				},
				{
					quantity: -2,
					usageAt:  january1st2021.WithMinute(30),
				},
			},
			skuPrice:        1,
			hourlyQuantity:  2,   // (3 * 1) - (-2 * 0.5)
			dailyQuantity:   25,  // 2 + 1 * 23
			monthlyQuantity: 745, // 25 + 1 * 24 * 30
			usageDate:       january1st2021,
		},
		{
			testCase: "requesting monthly halfway through the month",
			usages: []testUsage{
				{
					quantity: 3,
					usageAt:  january1st2021,
				},
				{
					quantity: -3,
					usageAt:  january2021.WithDay(2),
				},
				{
					quantity: 1,
					usageAt:  january2021.WithDay(3),
				},
				{
					quantity: 5,
					usageAt:  january2021.WithDay(20),
				},
			},
			skuPrice:        1,
			hourlyQuantity:  1,
			dailyQuantity:   24,
			monthlyQuantity: 2208, // (3 * 24) + (1 * 24 * 29) + (5 * 24 * 12)
			usageDate:       january2021.WithDay(16),
		},
	}

	for _, tc := range tests {
		tc := tc
		t.Run(tc.testCase, func(t *testing.T) {
			testPerUnitRollups(t, tc)
		})
	}
}

func Test_PerUnitHourlyMeter_Watermark_GetUsageTotal_ActiveTypeTruncation(t *testing.T) {
	t.Parallel()

	january1st2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January).WithDay(1)
	january16th2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January).WithDay(16)
	february1st2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.February).WithDay(1)

	// The tests will run for the three primary activeTypes: hourly, daily, and monthly. The activeType in combination with the usageDate
	// will determine how we truncate the usageDate when looking for usage. For example:
	//
	// Given a usage date of 2021-01-02 1:00:00
	// Billing period hourly will respect the hour of the usage date
	// Billing period daily will respect the day of the usage date and will discard the hour
	// Billing period monthly will only respect the month of the usage date and discard the day
	tests := []testData{
		{
			testCase: "requesting a hour that has no usage",
			usages: []testUsage{{
				quantity: 1,
				usageAt:  january16th2021.WithHour(12),
			}},
			skuPrice:        1,
			hourlyQuantity:  0,   // Hourly activetype does not truncate usageDate and there was 0 usage at the requested hour
			dailyQuantity:   12,  // Daily activeType will truncate usageDate to the day so we return usage
			monthlyQuantity: 372, // Monthly activeType will truncate usageDate to the month so we return usage
			usageDate:       january16th2021.WithHour(11),
		},
		{
			testCase: "requesting a day that has no usage",
			usages: []testUsage{{
				quantity: 1,
				usageAt:  january16th2021.WithHour(12),
			}},
			skuPrice:        1,
			hourlyQuantity:  0,
			dailyQuantity:   0,
			monthlyQuantity: 372,
			usageDate:       january1st2021,
		},
		{
			testCase: "requesting a month that has no usage",
			usages: []testUsage{{
				quantity: 1,
				usageAt:  february1st2021,
			}},
			skuPrice:        1,
			hourlyQuantity:  0, // Hourly activetype does not truncate usageDate and there was 0 usage at that requested hour
			dailyQuantity:   0, // Daily activeType will truncate usageDate to the day and there was 0 usage on the requested day
			monthlyQuantity: 0, // Monthly activeType will truncate usageDate to the month so we return usage
			usageDate:       january1st2021,
		},
		{
			testCase: "requesting a specific hour of usage when multiple hours of usage exist",
			usages: []testUsage{
				{
					quantity: 1,
					usageAt:  january1st2021.WithHour(1),
				},
				{
					quantity: 1,
					usageAt:  january1st2021.WithHour(12),
				},
				{
					quantity: 1,
					usageAt:  january1st2021.WithHour(23),
				},
			},
			skuPrice:        1,
			hourlyQuantity:  2,
			dailyQuantity:   36,   // (1 * 23) + (1 * 12) + 1
			monthlyQuantity: 2196, // first_day (36) + rest_of_days (3 * 24 * 30)
			usageDate:       january1st2021.WithHour(12),
		},
	}

	for _, tc := range tests {
		tc := tc
		t.Run(tc.testCase, func(t *testing.T) {
			testPerUnitRollups(t, tc)
		})
	}
}

func testPerUnitRollups(t *testing.T, tc testData) {
	client, _ := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerId := stubs.GetRandomId64AsString()
	pricing := client.EnsureSpecificPricingExistsWithAll(tc.skuPrice, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "name", proto.UnitType_GigabyteHours)

	usages := make([]*hydroSchema.Usage, len(tc.usages))
	for i, u := range tc.usages {
		usages[i] = stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), u.quantity, customerId, u.usageAt.Time)
	}

	usageDate := tc.usageDate.Time
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestionWithTimeTravel(len(usages), usageDate)

	_ = client.GetUsageTotal("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Hourly)

	// 	g.Expect(u.Quantity).Should(gomega.Equal(tc.hourlyQuantity), "usage quantity from hourly bucket from final total")
	// 	g.Expect(u.BillableAmount).Should(gomega.Equal(u.Quantity*tc.skuPrice), "usage billed amount from hourly bucket from final total")

	// 	u = client.GetUsageTotal("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Daily)
	// 	g.Expect(float64(u.Quantity)).Should(gomega.Equal(tc.dailyQuantity), "usage quantity from daily bucket from final total")
	// 	g.Expect(u.BillableAmount).Should(gomega.Equal(u.Quantity*tc.skuPrice), "usage billed amount from daily bucket from final total")

	// u = client.GetUsageTotal("", pricing.GetSku(), customerId, usageDate, proto.BillingPeriod_Monthly)
	// g.Expect(float64(u.Quantity)).Should(gomega.Equal(tc.monthlyQuantity), "usage quantity from monthly bucket from running total")
	// g.Expect(u.BillableAmount).Should(gomega.Equal(u.Quantity*tc.skuPrice), "usage billed amount from monthly bucket from final total")
}
