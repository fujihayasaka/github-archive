//go:build integration
// +build integration

package integrationtests_test

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/lib/zuora"
	"github.com/onsi/gomega"

	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/google/uuid"
)

func Test_Daily_Emission_With_Invalid_Parameters(t *testing.T) {
	tests := []struct {
		name                 string
		zuoraAccountNumber   string
		billingTarget        proto.BillingTarget
		enabledProducts      []string
		product              string
		zuoraUsageIdentifier string
	}{
		{
			"emission_enabled_for_azure",
			stubs.GetRandomId64AsString(),
			proto.BillingTarget_Azure,
			[]string{"actions"},
			"actions",
			"GitHub Actions Usage",
		},
		{
			"emission_enabled_no_target",
			stubs.GetRandomId64AsString(),
			proto.BillingTarget_NoBillingTarget,
			[]string{"actions"},
			"actions",
			"GitHub Actions Usage",
		},
		{
			"emission_enabled_missing_account_number",
			"",
			proto.BillingTarget_Zuora,
			[]string{"actions"},
			"actions",
			"GitHub Actions Usage",
		},
		{
			"emission_enabled_no_usage_to_send",
			"2c92a00c6dfd2579016dff121ec702c4",
			proto.BillingTarget_Zuora,
			[]string{"actions"},
			"actions",
			"",
		},
	}

	for _, tt := range tests {
		name := tt.name
		billingTarget := tt.billingTarget
		enabledProducts := tt.enabledProducts
		product := tt.product
		zuoraUsageIdentifier := tt.zuoraUsageIdentifier
		zuoraAccountNumber := tt.zuoraAccountNumber

		t.Run(name, func(t *testing.T) {
			client, _ := integration.NewTestClient(t, integration.ClientOptions{})
			defer client.Close()
			client.StartZuoraServer([]func(rw http.ResponseWriter, r *http.Request){
				func(rw http.ResponseWriter, r *http.Request) {
					t.Errorf("unexpected call to Zuora API %s", r.RequestURI)
				},
			})

			customerProto := stubs.CreateCustomerWithTargetAndZuoraAccountNumber(billingTarget, zuoraAccountNumber)
			customerProto.EnabledProducts = enabledProducts

			_ = client.CreateCustomer(customerProto)

			client.EnsureProductExists(product, product, zuoraUsageIdentifier)
			pricing := client.EnsureSpecificPricingExists(1, "linux", product, "")

			// Create some usage
			usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
			usage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 1, customerProto.CustomerId, usageDate)
			usages := []*hydroSchema.Usage{usage}

			fmt.Printf("Created usage: %+v\n", usage)
			client.ProduceMeteredUsage(usages)
			client.RunUsageIngestion(len(usages))
			client.RunZuoraDailyRollupJob(len(usages))

			// Run emission dispatch job for the desired year, month, and day
			client.RunEmissionDispatch(usageDate)
			client.ValidateQueue(1, models.WorkerTypeRequestHandler)

			// Run the request handler to schedule emissions
			client.RunRequestHandler(0)
			client.ValidateQueue(1, models.WorkerTypeRequestHandler)
			client.ValidateQueue(0, models.WorkerTypeEmissionHandler)

			// Run the emission handler to Process Emission queue
			// Create Emission record and emit to Zuora
			client.RunDailyEmissions(1)
			client.ValidateQueue(0, models.WorkerTypeEmissionHandler)

		})
	}
}

func Test_Zuora_Daily_Emission_Errors(t *testing.T) {
	client, _ := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	client.ProduceBadMessageForQueue(models.WorkerTypeEmissionHandler)

	client.ValidateQueue(1, models.WorkerTypeEmissionHandler)

	// Process the Emission Handler queue
	// This should generate an error
	client.RunDailyEmissions(1)
	client.ValidateQueue(0, models.WorkerTypeEmissionHandler)
	client.ValidateDeadLetterQueue(1, models.WorkerTypeEmissionHandler)
}

func Test_Zuora_Daily_Emission_With_Valid_Customer(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	_ = client.CreateCustomer(customerProto)

	// Mock environment variables
	os.Setenv("DAILY_EMISSION_CUSTOMER_IDS", customerProto.CustomerId)
	os.Setenv("DAILY_EMISSION_ACTIVE_DATE", "2010-11-14")
	defer os.Unsetenv("DAILY_EMISSION_CUSTOMER_IDS")
	defer os.Unsetenv("DAILY_EMISSION_ACTIVE_DATE")

	zuoraCalled := false
	client.StartZuoraServer([]func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			gotBody, _ := io.ReadAll(r.Body)
			wantBody, _ := json.Marshal([]zuora.UploadUsageRecord{
				{
					CustomerId:      customerProto.ZuoraAccountNumber,
					UsageIdentifier: "GitHub Actions Usage",
					UsageDate:       zuora.ZuoraUsageDateTime{Time: time.Date(2010, 11, 14, 0, 0, 0, 0, time.UTC)},
					Amount:          0.016,
					CostCenter:      "",
				},
			})
			g.Expect(string(gotBody)).To(gomega.Equal(string(wantBody)))
			zuoraCalled = true
			rw.WriteHeader(200)
			_, _ = rw.Write([]byte(`{
				"success": true,
				"message": "Successfully uploaded 1 record"
			}`))
		},
	})

	client.EnsureProductExists("actions", "Actions", "GitHub Actions Usage")
	client.EnsureSpecificPricingExists(0.016, "actions_linux_4_core", "actions", "Actions")

	// Create some usage
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), "actions_linux_4_core", 1, customerProto.CustomerId, usageDate)
	usages := []*hydroSchema.Usage{usage}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunZuoraDailyRollupJob(len(usages))
	// Run emission dispatch job for the desired year, month, and day
	client.RunEmissionDispatch(usageDate)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	// Run the request handler to schedule emissions
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)

	// Run the emission handler to Process Emission queue
	// Create Emission record and emit to Zuora
	client.RunDailyEmissions(1)
	client.ValidateQueue(0, models.WorkerTypeEmissionHandler)

	// Display the value of zuoraCalled
	t.Logf("zuoraCalled: %v", zuoraCalled)
}
