//go:build integration
// +build integration

package integrationtests_test

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/lib/zuora"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
)

func Test_Zuora_Emission_With_Invalid_Parameters(t *testing.T) {
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
			client.ProduceMeteredUsage(usages)
			client.RunUsageIngestion(len(usages))
			client.RunDailyJob(len(usages))
			client.RunMonthlyJob(len(usages))

			// Schedule invoice generation for the desired year and month
			// This puts a new request with an invoice partition detail into the request handler queue
			client.ScheduleInvoiceGeneration(2010, 11)
			client.ValidateQueue(1, models.WorkerTypeRequestHandler)

			// Run the request handler
			// This populates the Invoice Generation queue with invoices matching the invoice partition detail
			client.RunRequestHandler(1)
			client.ValidateQueue(0, models.WorkerTypeRequestHandler)
			client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

			// Process the Invoice Generation queue
			// This emits usage to Zuora
			client.RunInvoiceGeneration(1)
			client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)
		})
	}
}

func Test_Zuora_Emission_With_Disabled_Sku(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	_ = client.CreateCustomer(customerProto)

	zuoraCalled := false
	client.StartZuoraServer([]func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			responseBody, _ := io.ReadAll(r.Body)
			var gotBody []zuora.UploadUsageRecord
			_ = json.Unmarshal(responseBody, &gotBody)
			wantBody := []zuora.UploadUsageRecord{
				{
					CustomerId:      customerProto.ZuoraAccountNumber,
					UsageIdentifier: "GitHub Actions Usage",
					UsageDate:       zuora.ZuoraUsageDateTime{Time: time.Date(2023, 5, 31, 0, 0, 0, 0, time.UTC)},
					Amount:          0.016,
					CostCenter:      "",
				},
			}

			for _, r := range gotBody {
				g.Expect([]string{"GitHub Actions Usage"}).To(gomega.ContainElement(r.UsageIdentifier))
				g.Expect([]string{"GitHub Codespaces Usage"}).NotTo(gomega.ContainElement(r.UsageIdentifier)) // Codespaces usage should not be present

				g.Expect(r.CustomerId).To(gomega.Equal(wantBody[0].CustomerId))
				g.Expect(r.UsageDate.Unix()).To(gomega.Equal(wantBody[0].UsageDate.Unix()))
				g.Expect(r.Amount).To(gomega.Equal(wantBody[0].Amount))
				g.Expect(r.CostCenter).To(gomega.Equal(wantBody[0].CostCenter))
			}
			g.Expect(gotBody).To(gomega.HaveLen(len(wantBody)))
			zuoraCalled = true
			rw.WriteHeader(200)
			_, _ = rw.Write([]byte(`{
				"success": true,
				"message": "Successfully uploaded 2 records"
			}`))
		},
	})

	client.EnsureProductExists("actions", "Actions", "GitHub Actions Usage")
	client.EnsureProductExists("codespaces", "Codespaces", "GitHub Codespaces Usage")

	// Enabled SKU
	pricing1 := client.EnsureSpecificPricingExistsWithEffectiveAt(
		0.016,
		"actions_linux_4_core",
		"actions",
		proto.PricingMeterType_Default,
		time.Date(2022, 5, 1, 0, 0, 0, 0, time.UTC).Unix(),
	)

	// Disabled SKU
	nextYear := time.Now().AddDate(1, 0, 0).Year()
	pricing2 := client.EnsureSpecificPricingExistsWithEffectiveAt(
		0.36,
		"codespaces_compute_d4",
		"codespaces",
		proto.PricingMeterType_Default,
		time.Date(nextYear, 5, 1, 0, 0, 0, 0, time.UTC).Unix(),
	)

	// Create some usage
	usageDate := time.Date(2023, 5, 10, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerProto.CustomerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing2.Sku, 1, customerProto.CustomerId, usageDate)
	usages := []*hydroSchema.Usage{usage1, usage2}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// Schedule invoice generation for the desired year and month
	// This puts a new request with an invoice partition detail into the request handler queue
	client.ScheduleInvoiceGeneration(2023, 5)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	ipd := &models.InvoicePartitionDetail{
		CustomerId: customerProto.CustomerId,
		Period:     models.InvoiceMonthly,
		Year:       2023,
		Month:      5,
	}
	activeInvoice, _ := db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice.ProcessedAt).To(gomega.BeNil())

	submittedInvoice, _ := db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).To(gomega.BeNil())

	// Run the request handler
	// This populates the Invoice Generation queue with invoices matching the invoice partition detail
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	// Process the Invoice Generation queue
	// This emits usage to Zuora
	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)

	activeInvoice, _ = db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice).To(gomega.BeNil())

	g.Expect(zuoraCalled).To(gomega.BeTrue())

	submittedInvoice, _ = db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).NotTo(gomega.BeNil())
	g.Expect(submittedInvoice.SubmittedAt).NotTo(gomega.BeNil())

	invoice, _ := db.NewQuerier[*models.Invoice](client.DB).ReadItem(context.Background(), client.Logger, models.NewInvoiceKey(ipd), nil)
	g.Expect(invoice.State).To(gomega.Equal(models.Submitted))

	// Run invoice generation again. The second time should not have any active invoices to process
	client.ScheduleInvoiceGeneration(2023, 5)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)
}

func Test_Zuora_Emission_With_Valid_Customer(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	_ = client.CreateCustomer(customerProto)

	zuoraCalled := false
	client.StartZuoraServer([]func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			gotBody, _ := io.ReadAll(r.Body)
			wantBody, _ := json.Marshal([]zuora.UploadUsageRecord{
				{
					CustomerId:      customerProto.ZuoraAccountNumber,
					UsageIdentifier: "GitHub Actions Usage",
					UsageDate:       zuora.ZuoraUsageDateTime{Time: time.Date(2010, 11, 30, 0, 0, 0, 0, time.UTC)},
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
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// Schedule invoice generation for the desired year and month
	// This puts a new request with an invoice partition detail into the request handler queue
	_ = client.AdminTriggerInvoiceGeneration(usageDate, customerProto.CustomerId)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	ipd := &models.InvoicePartitionDetail{
		CustomerId: customerProto.CustomerId,
		Period:     models.InvoiceMonthly,
		Year:       2010,
		Month:      11,
	}
	activeInvoice, _ := db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice.ProcessedAt).To(gomega.BeNil())

	submittedInvoice, _ := db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).To(gomega.BeNil())

	// Run the request handler
	// This populates the Invoice Generation queue with invoices matching the invoice partition detail
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	// Process the Invoice Generation queue
	// This emits usage to Zuora
	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)

	activeInvoice, _ = db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice).To(gomega.BeNil())

	g.Expect(zuoraCalled).To(gomega.BeTrue())

	submittedInvoice, _ = db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).NotTo(gomega.BeNil())
	g.Expect(submittedInvoice.SubmittedAt).NotTo(gomega.BeNil())

	invoice, _ := db.NewQuerier[*models.Invoice](client.DB).ReadItem(context.Background(), client.Logger, models.NewInvoiceKey(ipd), nil)
	g.Expect(invoice.State).To(gomega.Equal(models.Submitted))

	// Run invoice generation again. The second time should not have any active invoices to process
	client.ScheduleInvoiceGeneration(2010, 11)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)
}

func Test_Zuora_Emission_With_Cost_Center_Customer(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// Create the enterprise customer first
	enterpriseCustomerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	enterpriseCustomerId, _ := strconv.ParseInt(enterpriseCustomerProto.CustomerId, 10, 64)
	_ = client.CreateCustomer(enterpriseCustomerProto)

	// Create the Cost Center and proxy customer
	resourceId := stubs.GetRandomId64()
	costCenterProto := stubs.CreateZuoraCostCenterWithCustomerAndResources(enterpriseCustomerProto.CustomerId, []*proto.Resource{
		{
			Id:   fmt.Sprint(resourceId),
			Type: proto.ResourceType_Repo,
		},
	})
	costCenterResp, _ := client.CreateCostCenter(costCenterProto)
	costCenterCustomerId := costCenterResp.CostCenter.CostCenterKey.Uuid

	zuoraCalled := false
	client.StartZuoraServer([]func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			gotBody, _ := io.ReadAll(r.Body)
			wantBody, _ := json.Marshal([]zuora.UploadUsageRecord{
				{
					CustomerId:      enterpriseCustomerProto.ZuoraAccountNumber,
					UsageIdentifier: "GitHub Actions Usage",
					UsageDate:       zuora.ZuoraUsageDateTime{Time: time.Date(2010, 11, 30, 0, 0, 0, 0, time.UTC)},
					Amount:          0.016,
					CostCenter:      costCenterProto.Name,
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
	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     enterpriseCustomerId,
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         resourceId,
		ActorId:        stubs.GetRandomId64(),
	}

	usage := stubs.CreateUsageWithEntity(uuid.NewString(), "actions_linux_4_core", 1, usageDate, entity)
	usages := []*hydroSchema.Usage{usage}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// Schedule invoice generation for the desired year and month
	// This puts a new request with an invoice partition detail into the request handler queue
	client.ScheduleInvoiceGeneration(2010, 11)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	ipd := &models.InvoicePartitionDetail{
		CustomerId: costCenterCustomerId,
		Period:     models.InvoiceMonthly,
		Year:       2010,
		Month:      11,
	}
	activeInvoice, _ := db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice.ProcessedAt).To(gomega.BeNil())

	submittedInvoice, _ := db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).To(gomega.BeNil())

	// Run the request handler
	// This populates the Invoice Generation queue with invoices matching the invoice partition detail
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	// Process the Invoice Generation queue
	// This emits usage to Zuora
	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)

	activeInvoice, _ = db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice).To(gomega.BeNil())

	g.Expect(zuoraCalled).To(gomega.BeTrue())

	submittedInvoice, _ = db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).NotTo(gomega.BeNil())
	g.Expect(submittedInvoice.SubmittedAt).NotTo(gomega.BeNil())

	invoice, _ := db.NewQuerier[*models.Invoice](client.DB).ReadItem(context.Background(), client.Logger, models.NewInvoiceKey(ipd), nil)
	g.Expect(invoice.State).To(gomega.Equal(models.Submitted))

	// Run invoice generation again. The second time should not have any active invoices to process
	client.ScheduleInvoiceGeneration(2010, 11)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)
}

func Test_Zuora_Emission_Marks_Invoice_Rejected_After_Retries_Exhausted(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	_ = client.CreateCustomer(customerProto)

	zuoraCalled := false
	client.StartZuoraServer([]func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			rw.WriteHeader(429)
			_, _ = rw.Write([]byte(`{
				"success": false,
				"message": "too many requests"
			}`))
		},
		func(rw http.ResponseWriter, r *http.Request) {
			rw.WriteHeader(500)
			_, _ = rw.Write([]byte(`{
				"success": false,
				"message": "internal error"
			}`))
		},
		func(rw http.ResponseWriter, r *http.Request) {
			zuoraCalled = true
			rw.WriteHeader(429)
			_, _ = rw.Write([]byte(`{
				"success": false,
				"message": "too many requests"
			}`))
		},
	})

	client.EnsureProductExists("actions", "Actions", "GitHub Actions Usage")
	pricing := client.EnsureSpecificPricingExists(1, "linux", "actions", "")

	// Create some usage
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 1, customerProto.CustomerId, usageDate)
	usages := []*hydroSchema.Usage{usage}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// Schedule invoice generation for the desired year and month
	// This puts a new request with an invoice partition detail into the request handler queue
	client.ScheduleInvoiceGeneration(2010, 11)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	ipd := &models.InvoicePartitionDetail{
		CustomerId: customerProto.CustomerId,
		Period:     models.InvoiceMonthly,
		Year:       2010,
		Month:      11,
	}
	activeInvoice, _ := db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice.ProcessedAt).To(gomega.BeNil())

	submittedInvoice, _ := db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).To(gomega.BeNil())

	rejectedInvoice, _ := db.NewQuerier[*models.RejectedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Rejected), nil)
	g.Expect(rejectedInvoice).To(gomega.BeNil())

	// Run the request handler
	// This populates the Invoice Generation queue with invoices matching the invoice partition detail
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	// Process the Invoice Generation queue
	// This emits usage to Zuora
	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)

	activeInvoice, _ = db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice.ProcessedAt).ToNot(gomega.BeNil())

	g.Expect(zuoraCalled).To(gomega.BeTrue())

	submittedInvoice, _ = db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).To(gomega.BeNil())

	rejectedInvoice, _ = db.NewQuerier[*models.RejectedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Rejected), nil)
	g.Expect(rejectedInvoice.RejectedAt).NotTo(gomega.BeNil())
	g.Expect(rejectedInvoice.ErrorMessage).To(gomega.ContainSubstring("too many requests"))

	invoice, _ := db.NewQuerier[*models.Invoice](client.DB).ReadItem(context.Background(), client.Logger, models.NewInvoiceKey(ipd), nil)
	g.Expect(invoice.State).To(gomega.Equal(models.Rejected))
	client.ValidateDeadLetterQueue(1, models.WorkerTypeInvoiceGeneration)
}

func Test_Zuora_Emission_With_Watermark_Meter(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	_ = client.CreateCustomer(customerProto)

	zuoraCalled := false
	client.StartZuoraServer([]func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			gotBody, _ := io.ReadAll(r.Body)
			wantBody, _ := json.Marshal([]zuora.UploadUsageRecord{
				{
					CustomerId:      customerProto.ZuoraAccountNumber,
					UsageIdentifier: "GitHub Actions Usage",
					UsageDate:       zuora.ZuoraUsageDateTime{Time: time.Date(2021, 1, 31, 0, 0, 0, 0, time.UTC)},
					Amount:          0.0008,
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
	pricing := client.EnsureSpecificPricingExistsWithAll(0.0008, "actions_storage", "actions", proto.PricingMeterType_PerHourUnitCharge, "Actions Storage", proto.UnitType_GigabyteHours)

	// Create some usage
	skuDiscountsQuantity := 15_625.0 // $12.50 / 0.0008
	quantity := skuDiscountsQuantity + 1.0
	january2021 := models.NewUsageTime().WithYear(2021).WithMonth(time.January)
	now := january2021.WithDay(1).WithHour(1).Time
	then := january2021.WithDay(1).Time

	// Always use beginning of day to make quantity deterministic
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), quantity, customerProto.CustomerId, then)
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestionWithTimeTravel(len(usages), then)

	// Send an watermark jobs request message to the request-handler queue
	client.ScheduleWatermarkJobs(now, pricing.GetSku())

	// Ensure our request made it to the queue
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeWatermarkHandler)
	client.RunWatermarkHandler(1)
	client.ValidateQueue(1, models.WorkerTypeUsageIngestion)
	client.RunUsageIngestion(1)
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	u := client.GetUsageLineItems("", "", customerProto.CustomerId, now, proto.BillingPeriod_Daily)
	g.Expect(u.BillingItems).ShouldNot(gomega.BeEmpty(), "a line item should not be created yet")

	// Schedule invoice generation for the desired year and month
	// This puts a new request with an invoice partition detail into the request handler queue
	client.ScheduleInvoiceGeneration(2021, 1)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)

	ipd := &models.InvoicePartitionDetail{
		CustomerId: customerProto.CustomerId,
		Year:       2021,
		Month:      1,
	}
	activeInvoice, _ := db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice.ProcessedAt).To(gomega.BeNil())

	submittedInvoice, _ := db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).To(gomega.BeNil())

	// Run the request handler
	// This populates the Invoice Generation queue with invoices matching the invoice partition detail
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	// Process the Invoice Generation queue
	// This emits usage to Zuora
	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)

	activeInvoice, _ = db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice).To(gomega.BeNil())

	g.Expect(zuoraCalled).To(gomega.BeTrue())

	submittedInvoice, _ = db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).NotTo(gomega.BeNil())
	g.Expect(submittedInvoice.SubmittedAt).NotTo(gomega.BeNil())

	invoice, _ := db.NewQuerier[*models.Invoice](client.DB).ReadItem(context.Background(), client.Logger, models.NewInvoiceKey(ipd), nil)
	g.Expect(invoice.State).To(gomega.Equal(models.Submitted))

	// Run invoice generation again. The second time should not have any active invoices to process
	client.ScheduleInvoiceGeneration(2010, 11)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)
}

func Test_Zuora_Emission_Errors(t *testing.T) {
	client, _ := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	client.ProduceBadMessageForQueue(models.WorkerTypeInvoiceGeneration)

	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	// Process the Invoice Generation queue
	// This should generate an error
	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)
	client.ValidateDeadLetterQueue(1, models.WorkerTypeInvoiceGeneration)
}

func Test_Zuora_Emission_With_LateUsage_AfterEmission(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	_ = client.CreateCustomer(customerProto)

	zuoraCalledCount := 0
	client.StartZuoraServer([]func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			gotBody, _ := io.ReadAll(r.Body)
			wantBody, _ := json.Marshal([]zuora.UploadUsageRecord{
				{
					CustomerId:      customerProto.ZuoraAccountNumber,
					UsageIdentifier: "GitHub Actions Usage",
					UsageDate:       zuora.ZuoraUsageDateTime{Time: time.Date(2010, 11, 30, 0, 0, 0, 0, time.UTC)},
					Amount:          0.016,
					CostCenter:      "",
				},
			})
			g.Expect(string(gotBody)).To(gomega.Equal(string(wantBody)))
			zuoraCalledCount++
			rw.WriteHeader(200)
			_, _ = rw.Write([]byte(`{
				"success": true,
				"message": "Successfully uploaded 1 record"
			}`))
		},
		func(rw http.ResponseWriter, r *http.Request) {
			NetAmountAfter := 16.016
			NetAmountBefore := 0.016
			gotBody, _ := io.ReadAll(r.Body)
			wantBody, _ := json.Marshal([]zuora.UploadUsageRecord{
				{
					CustomerId:      customerProto.ZuoraAccountNumber,
					UsageIdentifier: "GitHub Actions Usage",
					UsageDate:       zuora.ZuoraUsageDateTime{Time: time.Date(2010, 11, 30, 0, 0, 0, 0, time.UTC)},
					Amount:          NetAmountAfter - NetAmountBefore,
					CostCenter:      "",
				},
			})
			g.Expect(string(gotBody)).To(gomega.Equal(string(wantBody)))
			zuoraCalledCount++
			rw.WriteHeader(200)
			_, _ = rw.Write([]byte(`{
					"success": true,
					"message": "Successfully uploaded 1 record"
				}`))
		},
	},
	)

	client.EnsureProductExists("actions", "Actions", "GitHub Actions Usage")
	client.EnsureSpecificPricingExists(0.016, "actions_linux_4_core", "actions", "Actions")

	// Create some usage
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), "actions_linux_4_core", 1, customerProto.CustomerId, usageDate)
	usages := []*hydroSchema.Usage{usage}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))
	ipd := &models.InvoicePartitionDetail{
		CustomerId: customerProto.CustomerId,
		Period:     models.InvoiceMonthly,
		Year:       2010,
		Month:      11,
	}
	// Schedule invoice generation for the desired year and month, generate invoice and emit to zuora
	client.ScheduleInvoiceGeneration(2010, 11)
	client.RunRequestHandler(1)
	client.RunInvoiceGeneration(1)

	activeInvoice, _ := db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice).To(gomega.BeNil())

	g.Expect(zuoraCalledCount).To(gomega.Equal(1))

	submittedInvoice, _ := db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).NotTo(gomega.BeNil())
	g.Expect(submittedInvoice.SubmittedAt).NotTo(gomega.BeNil())

	invoice, _ := db.NewQuerier[*models.Invoice](client.DB).ReadItem(context.Background(), client.Logger, models.NewInvoiceKey(ipd), nil)
	g.Expect(invoice.State).To(gomega.Equal(models.Submitted))

	// Create some late usage after invoice is emitted for current month
	usageDate = time.Date(2010, 11, 14, 10, 0, 0, 0, time.UTC)
	usage = stubs.CreateUsage(uuid.NewString(), "actions_linux_4_core", 1000, customerProto.CustomerId, usageDate)
	usages = []*hydroSchema.Usage{usage}
	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// Run invoice generation again. The second time should upsert the current active invoices to process it again
	client.ScheduleInvoiceGeneration(2010, 11)
	client.RunRequestHandler(1)
	client.RunInvoiceGeneration(1)

	activeInvoice, _ = db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice).To(gomega.BeNil())

	g.Expect(zuoraCalledCount).To(gomega.Equal(2))

	submittedInvoice, _ = db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	invoiceKey, _ := models.InvoicePartitionDetailFromInvoiceKey(submittedInvoice.Key)

	// submittedinvoice id to key to get invoice document
	invoice, _ = db.NewQuerier[*models.Invoice](client.DB).ReadItem(context.Background(), client.Logger, models.NewInvoiceKey(invoiceKey), nil)
	g.Expect(invoice.UsageTotal.Quantity).To(gomega.Equal(1001.0))
	g.Expect(submittedInvoice.SubmittedAt).NotTo(gomega.BeNil())
}

func Test_Zuora_Emission_Of_High_Watermark_Usage_Zuora_Full_Month(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"copilot"}
	_ = client.CreateCustomer(customerProto)

	zuoraCalled := false
	client.StartZuoraServer([]func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			gotBody, _ := io.ReadAll(r.Body)
			wantBody, _ := json.Marshal([]zuora.UploadUsageRecord{
				{
					CustomerId:      customerProto.ZuoraAccountNumber,
					UsageIdentifier: "GitHub Copilot Usage",
					UsageDate:       zuora.ZuoraUsageDateTime{Time: time.Date(2010, 11, 30, 0, 0, 0, 0, time.UTC)},
					Amount:          19.0,
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

	quantity := 1.0
	customerId := customerProto.CustomerId
	client.EnsureProductExists("copilot", "Copilot", "GitHub Copilot Usage")

	usageDateThen := time.Date(2010, 11, 1, 3, 0, 0, 0, time.UTC)
	copilotPricing := client.EnsureSpecificPricingExistsWithAll(19.0, "copilot_for_business", "copilot", proto.PricingMeterType_DailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)
	highWatermarkUsage := stubs.CreateUsage(uuid.NewString(), copilotPricing.GetSku(), quantity, customerId, usageDateThen)

	// Create some usage
	usages := []*hydroSchema.Usage{highWatermarkUsage}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))
	ipd := &models.InvoicePartitionDetail{
		CustomerId: customerProto.CustomerId,
		Period:     models.InvoiceMonthly,
		Year:       2010,
		Month:      11,
	}

	// Schedule invoice generation for the desired year and month
	// This puts a new request with an invoice partition detail into the request handler queue
	_ = client.AdminTriggerInvoiceGeneration(usageDateThen, customerProto.CustomerId)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.RunInvoiceGeneration(1)

	activeInvoice, _ := db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice).To(gomega.BeNil())

	g.Expect(zuoraCalled).To(gomega.BeTrue())

	submittedInvoice, _ := db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).NotTo(gomega.BeNil())
	g.Expect(submittedInvoice.SubmittedAt).NotTo(gomega.BeNil())

	invoice, _ := db.NewQuerier[*models.Invoice](client.DB).ReadItem(context.Background(), client.Logger, models.NewInvoiceKey(ipd), nil)
	g.Expect(invoice.State).To(gomega.Equal(models.Submitted))

	// Check usage matches
	g.Expect(invoice.UsageTotal.Quantity).To(gomega.Equal(1.0))
	g.Expect(invoice.UsageTotal.Gross).To(gomega.Equal(19.0))
}

func Test_Zuora_Emission_Of_High_Watermark_Usage_Zuora_Partial_Month(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// create customer that the watermark job will find and emit usage for
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"copilot"}
	_ = client.CreateCustomer(customerProto)

	zuoraCalled := false
	client.StartZuoraServer([]func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			gotBody, _ := io.ReadAll(r.Body)
			wantBody, _ := json.Marshal([]zuora.UploadUsageRecord{
				{
					CustomerId:      customerProto.ZuoraAccountNumber,
					UsageIdentifier: "GitHub Copilot Usage",
					UsageDate:       zuora.ZuoraUsageDateTime{Time: time.Date(2010, 11, 30, 0, 0, 0, 0, time.UTC)},
					Amount:          9.5,
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

	quantity := 1.0
	customerId := customerProto.CustomerId
	client.EnsureProductExists("copilot", "Copilot", "GitHub Copilot Usage")

	usageDateThen := time.Date(2010, 11, 16, 3, 0, 0, 0, time.UTC)
	copilotPricing := client.EnsureSpecificPricingExistsWithAll(19.0, "copilot_for_business", "copilot", proto.PricingMeterType_DailyUnitCharge, "Copilot for Business", proto.UnitType_UserMonths)
	highWatermarkUsage := stubs.CreateUsage(uuid.NewString(), copilotPricing.GetSku(), quantity, customerId, usageDateThen)

	// Create some usage
	usages := []*hydroSchema.Usage{highWatermarkUsage}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))
	ipd := &models.InvoicePartitionDetail{
		CustomerId: customerProto.CustomerId,
		Period:     models.InvoiceMonthly,
		Year:       2010,
		Month:      11,
	}

	// Schedule invoice generation for the desired year and month
	// This puts a new request with an invoice partition detail into the request handler queue
	_ = client.AdminTriggerInvoiceGeneration(usageDateThen, customerProto.CustomerId)
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	client.RunRequestHandler(1)
	client.RunInvoiceGeneration(1)

	activeInvoice, _ := db.NewQuerier[*models.ActiveInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Active), nil)
	g.Expect(activeInvoice).To(gomega.BeNil())

	g.Expect(zuoraCalled).To(gomega.BeTrue())

	submittedInvoice, _ := db.NewQuerier[*models.SubmittedInvoicesItem](client.DB).ReadItem(
		context.Background(), client.Logger, models.GetInvoiceItemKey(ipd, models.Submitted), nil)
	g.Expect(submittedInvoice).NotTo(gomega.BeNil())
	g.Expect(submittedInvoice.SubmittedAt).NotTo(gomega.BeNil())

	invoice, _ := db.NewQuerier[*models.Invoice](client.DB).ReadItem(context.Background(), client.Logger, models.NewInvoiceKey(ipd), nil)
	g.Expect(invoice.State).To(gomega.Equal(models.Submitted))

	// Check usage matches
	g.Expect(invoice.UsageTotal.Quantity).To(gomega.Equal(0.5))
	g.Expect(invoice.UsageTotal.Gross).To(gomega.Equal(9.5))
}

func Test_Zuora_Emission_With_Zero_NetAmount(t *testing.T) {
	client, _ := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	_ = client.CreateCustomer(customerProto)

	// Ensure product and pricing exist
	client.EnsureProductExists("actions", "Actions", "GitHub Actions Usage")
	pricing := client.EnsureSpecificPricingExists(0.016, "actions_linux_4_core", "actions", "Actions")

	// Create usage with net amount 0
	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 0, customerProto.CustomerId, usageDate)
	usages := []*hydroSchema.Usage{usage}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDailyJob(len(usages))
	client.RunMonthlyJob(len(usages))

	// Schedule invoice generation for the desired year and month
	client.ScheduleInvoiceGeneration(2010, 11)
	client.RunRequestHandler(1)
	client.RunInvoiceGeneration(1)

	// Validate that no usage records were emitted to Zuora
	client.ValidateQueue(0, models.WorkerTypeEmissionHandler)
}
