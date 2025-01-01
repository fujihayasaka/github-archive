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

func Test_AzureEmissionDispatcher_Admin_Trigger_Azure_Emission_Errors(t *testing.T) {
	tests := []struct {
		name       string
		date       time.Time
		customerId string
		success    bool
	}{
		{"now", time.Now().UTC(), "", true},
		{"yesterday", time.Now().UTC().AddDate(0, 0, -1), "", true},
		{"date_in_future", time.Now().UTC().AddDate(0, 0, 2), "", false},
		{"invalid_customer_id", time.Now().UTC(), "bad-id", false},
	}

	for _, tt := range tests {
		name := tt.name
		date := tt.date
		customerId := tt.customerId
		success := tt.success

		t.Run(name, func(t *testing.T) {
			client, g := integration.NewTestClient(t, integration.ClientOptions{})
			defer client.Close()

			if customerId == "" {
				customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Azure)
				customerId = customerProto.CustomerId
				_ = client.CreateCustomer(customerProto)
			}

			err := client.AdminTriggerAzureEmission(date, customerId)

			if success {
				g.Expect(err).ShouldNot(gomega.HaveOccurred())
			} else {
				g.Expect(err).Should(gomega.HaveOccurred())
			}
		})
	}
}

func Test_AzureEmissionDispatcher_Admin_Trigger_Azure_Emission_For_Date(t *testing.T) {
	client, _ := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProto)

	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)
	twoDaysAgo := now.AddDate(0, 0, -2)

	pricing := client.EnsureSpecificPricingExists(0.08, "actions_linux", "actions", "Actions")
	quantity := 1.0
	usageDateYesterday := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour(), 0, 0, 0, time.UTC)
	usageDateTwoDaysAgo := time.Date(twoDaysAgo.Year(), twoDaysAgo.Month(), twoDaysAgo.Day(), twoDaysAgo.Hour(), 0, 0, 0, time.UTC)
	usageYesterday := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerProto.CustomerId, usageDateYesterday)
	usageTwoDaysAgo := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerProto.CustomerId, usageDateTwoDaysAgo)
	usages := []*hydroSchema.Usage{usageYesterday, usageTwoDaysAgo}

	// ingest and roll up azure usages
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunAzureDailyRollupJob(len(usages))

	_ = client.AdminTriggerAzureEmission(twoDaysAgo, "")
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	// Fan out the usage line items and ensure we only add usage to the emission queue
	// We would only expect 1 item in the azure emission queue as the other item is from a different date.
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeAzureEmission)
}

func Test_AzureEmissionDispatcher_Admin_Trigger_Azure_Emission_For_Date_And_Customer(t *testing.T) {
	client, _ := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProtoOne := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProtoOne)

	customerProtoTwo := stubs.CreateEnabledCustomerWithTargetAndAzureAccountId(proto.BillingTarget_Azure, uuid.NewString())
	_ = client.CreateCustomer(customerProtoTwo)

	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)

	pricing := client.EnsureSpecificPricingExists(0.08, "actions_linux", "actions", "Actions")
	quantity := 1.0
	usageDate := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour(), 0, 0, 0, time.UTC)
	usageCustomerOne := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerProtoOne.CustomerId, usageDate)
	usageCustomerTwo := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerProtoTwo.CustomerId, usageDate)
	usages := []*hydroSchema.Usage{usageCustomerOne, usageCustomerTwo}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunAzureDailyRollupJob(len(usages))

	_ = client.AdminTriggerAzureEmission(yesterday, customerProtoOne.CustomerId)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	// Fan out the usage line items and ensure we only add usage to the emission queue
	// We would only expect 1 item in the azure emission queue as the other item is from a different customer.
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeAzureEmission)
}
