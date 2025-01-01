//go:build integration
// +build integration

package integrationtests_test

import (
	"fmt"
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	a "github.com/github/billing-platform/testing/assertions"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/integration-tests/helpers"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/google/uuid"
	"github.com/onsi/gomega"
	"github.com/twitchtv/twirp"
)

func Test_Customer_Create_Get_Customer(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customer := &proto.Customer{
		CustomerId:           "999",
		BillingTarget:        proto.BillingTarget_Zuora,
		ZuoraAccountId:       "123",
		ZuoraAccountNumber:   "A123",
		AzureAccountId:       uuid.NewString(),
		DiscountPlanName:     "enterprise",
		HasPaymentMethod:     true,
		HasZuoraSubscription: true,
		IsBillingLocked:      true,
		IsStaffOwned:         false,
		TradeScreening: &proto.TradeScreening{
			HasAnyTradeRestrictions:                       true,
			HasFullTradeRestrictions:                      true,
			FeaturesWithCommercialInteractionRestrictions: []string{"copilot"},
		},
	}

	_ = client.CreateCustomer(customer)
	customerResponse := client.GetCustomer(customer.CustomerId)

	g.Expect(customerResponse.Customer).To(gomega.Not(gomega.BeNil()))
	g.Expect(customerResponse.Customer.CustomerId).To(gomega.Equal(customer.CustomerId))
	g.Expect(customerResponse.Customer.EnterpriseCustomerId).To(gomega.Equal(customer.CustomerId))
	g.Expect(customerResponse.Customer.CostCenterUUID).To(gomega.Equal(customer.CostCenterUUID))
	g.Expect(customerResponse.Customer.IsCostCenterProxy).To(gomega.Equal(customer.IsCostCenterProxy))
	g.Expect(customerResponse.Customer.BillingTarget).To(gomega.Equal(customer.BillingTarget))
	g.Expect(customerResponse.Customer.ZuoraAccountId).To(gomega.Equal(customer.ZuoraAccountId))
	g.Expect(customerResponse.Customer.EnabledProducts).To(gomega.Equal(customer.EnabledProducts))
	g.Expect(customerResponse.Customer.EffectiveAt).To(gomega.Equal(int64(0)))
	g.Expect(customerResponse.Customer.ZuoraAccountNumber).To(gomega.Equal(customer.ZuoraAccountNumber))
	g.Expect(customerResponse.Customer.AzureAccountId).To(gomega.Equal(customer.AzureAccountId))
	g.Expect(customerResponse.Customer.DiscountPlanName).To(gomega.Equal(customer.DiscountPlanName))
	g.Expect(customerResponse.Customer.BillForPublicRepoUsage).To(gomega.Equal(customer.BillForPublicRepoUsage))
	g.Expect(customerResponse.Customer.HasPaymentMethod).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.HasZuoraSubscription).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.IsBillingLocked).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.IsStaffOwned).To(gomega.Equal(false))
	g.Expect(customerResponse.Customer.TradeScreening.HasAnyTradeRestrictions).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.TradeScreening.HasFullTradeRestrictions).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.TradeScreening.FeaturesWithCommercialInteractionRestrictions).To(
		gomega.Equal(customer.TradeScreening.FeaturesWithCommercialInteractionRestrictions),
	)
}

func Test_Customer_Patch_Enterprise_Customer(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customer := &proto.Customer{
		CustomerId:             "1",
		BillingTarget:          proto.BillingTarget_Zuora,
		ZuoraAccountId:         "123",
		ZuoraAccountNumber:     "A123",
		DiscountPlanName:       "enterprise",
		BillForPublicRepoUsage: false,
	}
	_ = client.CreateCustomer(customer)

	patchProto := &proto.Customer{
		CustomerId:             "1",
		CostCenterUUID:         uuid.NewString(),
		IsCostCenterProxy:      true,
		BillForPublicRepoUsage: true,
		AzureAccountId:         "456",
		ZuoraAccountNumber:     "A234",
		EnabledProducts:        []string{"actions", "git_lfs"},
		HasPaymentMethod:       true,
		HasZuoraSubscription:   true,
		IsBillingLocked:        true,
		IsStaffOwned:           false,
		TradeScreening: &proto.TradeScreening{
			HasAnyTradeRestrictions:                       true,
			HasFullTradeRestrictions:                      true,
			FeaturesWithCommercialInteractionRestrictions: []string{"copilot"},
		},
	}
	_ = client.PatchCustomer(patchProto)

	customerResponse := client.GetCustomer(customer.CustomerId)

	// these fields should not be updated
	g.Expect(customerResponse.Customer).To(gomega.Not(gomega.BeNil()))
	g.Expect(customerResponse.Customer.CustomerId).To(gomega.Equal(customer.CustomerId))
	g.Expect(customerResponse.Customer.EnterpriseCustomerId).To(gomega.Equal(customer.CustomerId))
	g.Expect(customerResponse.Customer.CostCenterUUID).To(gomega.Equal(customer.CostCenterUUID))
	g.Expect(customerResponse.Customer.IsCostCenterProxy).To(gomega.Equal(customer.IsCostCenterProxy))
	g.Expect(customerResponse.Customer.ZuoraAccountId).To(gomega.Equal(customer.ZuoraAccountId))
	g.Expect(customerResponse.Customer.BillForPublicRepoUsage).To(gomega.Equal(customer.BillForPublicRepoUsage))

	// these fields should be updated
	g.Expect(customerResponse.Customer.AzureAccountId).To(gomega.Equal(patchProto.AzureAccountId))
	g.Expect(customerResponse.Customer.ZuoraAccountNumber).To(gomega.Equal(patchProto.ZuoraAccountNumber))
	g.Expect(customerResponse.Customer.EnabledProducts).To(gomega.Equal(patchProto.EnabledProducts))
	g.Expect(customerResponse.Customer.EffectiveAt).To(gomega.BeNumerically(">", int64(0)))
	g.Expect(customerResponse.Customer.BillingTarget).To(gomega.Equal(proto.BillingTarget_NoBillingTarget))
	g.Expect(customerResponse.Customer.DiscountPlanName).To(gomega.Equal(""))
	g.Expect(customerResponse.Customer.HasPaymentMethod).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.HasZuoraSubscription).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.IsBillingLocked).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.IsStaffOwned).To(gomega.Equal(false))
	g.Expect(customerResponse.Customer.TradeScreening.HasAnyTradeRestrictions).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.TradeScreening.HasFullTradeRestrictions).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.TradeScreening.FeaturesWithCommercialInteractionRestrictions).To(
		gomega.Equal(patchProto.TradeScreening.FeaturesWithCommercialInteractionRestrictions),
	)
}

func Test_Customer_Patch_Create_Enterprise_Customer(t *testing.T) {

	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// Customer does not exist, should try to create it
	patchProto := &proto.Customer{
		CustomerId:             "1",
		AzureAccountId:         "456",
		ZuoraAccountNumber:     "A234",
		BillForPublicRepoUsage: true,
		EnabledProducts:        []string{"actions", "git_lfs"},
		HasPaymentMethod:       true,
		HasZuoraSubscription:   true,
		IsBillingLocked:        true,
		IsStaffOwned:           false,
		TradeScreening: &proto.TradeScreening{
			HasAnyTradeRestrictions:                       true,
			HasFullTradeRestrictions:                      true,
			FeaturesWithCommercialInteractionRestrictions: []string{"copilot"},
		},
	}
	_ = client.PatchCustomer(patchProto)

	customerResponse := client.GetCustomer(patchProto.CustomerId)

	g.Expect(customerResponse.Customer).To(gomega.Not(gomega.BeNil()))
	g.Expect(customerResponse.Customer.CustomerId).To(gomega.Equal(patchProto.CustomerId))
	g.Expect(customerResponse.Customer.EnterpriseCustomerId).To(gomega.Equal(patchProto.CustomerId))
	g.Expect(customerResponse.Customer.CostCenterUUID).To(gomega.Equal(patchProto.CostCenterUUID))
	g.Expect(customerResponse.Customer.IsCostCenterProxy).To(gomega.Equal(patchProto.IsCostCenterProxy))
	g.Expect(customerResponse.Customer.BillingTarget).To(gomega.Equal(proto.BillingTarget_NoBillingTarget))
	g.Expect(customerResponse.Customer.ZuoraAccountId).To(gomega.Equal(""))
	g.Expect(customerResponse.Customer.EnabledProducts).To(gomega.Equal(patchProto.EnabledProducts))
	g.Expect(customerResponse.Customer.EffectiveAt).To(gomega.BeNumerically(">", int64(0)))
	g.Expect(customerResponse.Customer.DiscountPlanName).To(gomega.Equal(""))
	g.Expect(customerResponse.Customer.AzureAccountId).To(gomega.Equal(patchProto.AzureAccountId))
	g.Expect(customerResponse.Customer.ZuoraAccountNumber).To(gomega.Equal(patchProto.ZuoraAccountNumber))
	g.Expect(customerResponse.Customer.BillForPublicRepoUsage).To(gomega.Equal(patchProto.BillForPublicRepoUsage))
	g.Expect(customerResponse.Customer.HasPaymentMethod).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.HasZuoraSubscription).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.IsBillingLocked).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.IsStaffOwned).To(gomega.Equal(false))
	g.Expect(customerResponse.Customer.TradeScreening.HasAnyTradeRestrictions).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.TradeScreening.HasFullTradeRestrictions).To(gomega.Equal(true))
	g.Expect(customerResponse.Customer.TradeScreening.FeaturesWithCommercialInteractionRestrictions).To(
		gomega.Equal(patchProto.TradeScreening.FeaturesWithCommercialInteractionRestrictions),
	)
}

func Test_Customer_Patch_Cost_Center_Customer(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customer := &proto.Customer{
		CustomerId:        "1",
		BillingTarget:     proto.BillingTarget_Zuora,
		IsCostCenterProxy: true,
		CostCenterUUID:    "123",
	}
	_ = client.CreateCustomer(customer)

	patchProto := &proto.Customer{
		CustomerId:     "123",
		BillingTarget:  proto.BillingTarget_Azure,
		AzureAccountId: "456",
	}
	_ = client.PatchCustomer(patchProto)

	customerResponse := client.GetCustomer(customer.CostCenterUUID)

	// these fields should not be updated
	g.Expect(customerResponse.Customer).To(gomega.Not(gomega.BeNil()))
	g.Expect(customerResponse.Customer.CustomerId).To(gomega.Equal(customer.CostCenterUUID))
	g.Expect(customerResponse.Customer.EnterpriseCustomerId).To(gomega.Equal(customer.CustomerId))
	g.Expect(customerResponse.Customer.CostCenterUUID).To(gomega.Equal(customer.CostCenterUUID))
	g.Expect(customerResponse.Customer.IsCostCenterProxy).To(gomega.Equal(customer.IsCostCenterProxy))
	g.Expect(customerResponse.Customer.BillForPublicRepoUsage).To(gomega.Equal(customer.BillForPublicRepoUsage))
	g.Expect(len(customerResponse.Customer.EnabledProducts)).To(gomega.Equal(0))
	g.Expect(customerResponse.Customer.EffectiveAt).To(gomega.Equal(int64(0)))

	// this should be updated
	g.Expect(customerResponse.Customer.BillingTarget).To(gomega.Equal(patchProto.BillingTarget))
	g.Expect(customerResponse.Customer.ZuoraAccountNumber).To(gomega.Equal(""))
	g.Expect(customerResponse.Customer.DiscountPlanName).To(gomega.Equal(""))
}

func Test_Customer_With_CostCenters_Gets_Patched(t *testing.T) {
	// Whenever a customer with cost center's billing target is updated, the cost center's billing target should be updated as well
	client, g := integration.NewTestClient(t, integration.ClientOptions{PreserveData: false})
	defer client.Close()

	enterpriseId := "1"

	// create an enterprise and cost center withg billing target Zuora
	costCenterKey, err := helpers.CreateCostCenter(enterpriseId, "a cost center", map[int64]proto.ResourceType{21: proto.ResourceType_Org}, proto.CostCenterType_ZuoraSubscription, client)
	g.Expect(err).To(gomega.BeNil())

	// check that the billing target is set to Zuora
	customer := client.GetCustomer(enterpriseId)
	costcenterCustomer := client.GetCustomer(costCenterKey.Uuid)
	costCenter := client.GetCostCenter(costCenterKey)
	g.Expect(customer.Customer.BillingTarget).To(gomega.Equal(proto.BillingTarget_Zuora))
	g.Expect(costcenterCustomer.Customer.BillingTarget).To(gomega.Equal(proto.BillingTarget_Zuora))
	g.Expect(costCenter.CostCenter.CostCenterKey.TargetType).To(gomega.Equal(proto.CostCenterType_ZuoraSubscription))

	// patch the enterprise to have billing target Azure
	patchProto := customer.Customer
	patchProto.BillingTarget = proto.BillingTarget_Azure
	_ = client.PatchCustomer(patchProto)

	// check that the billing target is set to Azure
	customer = client.GetCustomer(enterpriseId)
	costcenterCustomer = client.GetCustomer(costCenterKey.Uuid)
	costCenter = client.GetCostCenter(costCenterKey)
	g.Expect(customer.Customer.BillingTarget).To(gomega.Equal(proto.BillingTarget_Azure))
	g.Expect(costcenterCustomer.Customer.BillingTarget).To(gomega.Equal(proto.BillingTarget_Azure))
	g.Expect(costCenter.CostCenter.CostCenterKey.TargetType).To(gomega.Equal(proto.CostCenterType_AzureSubscription))

}

func Test_Customer_Patch_Creates_Cost_Center_Customer(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	patchProto := &proto.Customer{
		CustomerId:             "1",
		IsCostCenterProxy:      true,
		CostCenterUUID:         "123",
		BillForPublicRepoUsage: true,
		EnabledProducts:        []string{"actions", "git_lfs"},
	}
	_ = client.PatchCustomer(patchProto)

	customerResponse := client.GetCustomer(patchProto.CostCenterUUID)

	g.Expect(customerResponse.Customer).To(gomega.Not(gomega.BeNil()))
	g.Expect(customerResponse.Customer.CustomerId).To(gomega.Equal(patchProto.CostCenterUUID))
	g.Expect(customerResponse.Customer.EnterpriseCustomerId).To(gomega.Equal(patchProto.CustomerId))
	g.Expect(customerResponse.Customer.CostCenterUUID).To(gomega.Equal(patchProto.CostCenterUUID))
	g.Expect(customerResponse.Customer.IsCostCenterProxy).To(gomega.Equal(patchProto.IsCostCenterProxy))
	g.Expect(customerResponse.Customer.BillingTarget).To(gomega.Equal(proto.BillingTarget_NoBillingTarget))
	g.Expect(customerResponse.Customer.ZuoraAccountId).To(gomega.Equal(""))
	g.Expect(customerResponse.Customer.ZuoraAccountNumber).To(gomega.Equal(""))
	g.Expect(customerResponse.Customer.EnabledProducts).To(gomega.Equal(patchProto.EnabledProducts))
	g.Expect(customerResponse.Customer.EffectiveAt).To(gomega.BeNumerically(">", int64(0)))
	g.Expect(customerResponse.Customer.DiscountPlanName).To(gomega.Equal(""))
	g.Expect(customerResponse.Customer.BillForPublicRepoUsage).To(gomega.Equal(patchProto.BillForPublicRepoUsage))
}

func Test_Customer_Patch_Updates_EffectiveAt_When_EnabledProducts_Changes(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	patchProto := &proto.Customer{
		CustomerId:      "1",
		EnabledProducts: []string{},
		EffectiveAt:     100,
	}
	_ = client.PatchCustomer(patchProto)

	customerResponse := client.GetCustomer(patchProto.CustomerId)
	firstEffectiveAt := customerResponse.Customer.EffectiveAt

	g.Expect(len(customerResponse.Customer.EnabledProducts)).To(gomega.Equal(0))
	g.Expect(firstEffectiveAt).To(gomega.Equal(patchProto.EffectiveAt))

	patchProto = &proto.Customer{
		CustomerId:      "1",
		EnabledProducts: []string{"actions"},
	}
	_ = client.PatchCustomer(patchProto)

	customerResponse = client.GetCustomer(patchProto.CustomerId)
	secondEffectiveAt := customerResponse.Customer.EffectiveAt

	// EnabledProducts was updated, so EffectiveAt should change
	g.Expect(customerResponse.Customer.EnabledProducts).To(gomega.Equal(patchProto.EnabledProducts))
	g.Expect(secondEffectiveAt).To(gomega.BeNumerically(">", firstEffectiveAt))

	patchProto = &proto.Customer{
		CustomerId:      "1",
		EnabledProducts: []string{"actions"},
		AzureAccountId:  "123",
	}
	_ = client.PatchCustomer(patchProto)

	customerResponse = client.GetCustomer(patchProto.CustomerId)

	// EnabledProducts did not change from before so EffectiveAt should not change from the previous value
	g.Expect(customerResponse.Customer.EnabledProducts).To(gomega.Equal(patchProto.EnabledProducts))
	g.Expect(customerResponse.Customer.EffectiveAt).To(gomega.Equal(secondEffectiveAt))
}

type CustomerTestData struct {
	customerId    string
	billingTarget proto.BillingTarget
}

func Test_Customer_Create_Get_Customers(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customersData := []CustomerTestData{
		{
			customerId:    "999",
			billingTarget: proto.BillingTarget_Zuora,
		},
		{
			customerId:    "998",
			billingTarget: proto.BillingTarget_Zuora,
		},
		{
			customerId:    "997",
			billingTarget: proto.BillingTarget_Azure,
		},
	}

	customerIDs := []string{}
	for _, tt := range customersData {
		customerId := tt.customerId
		customer := &proto.Customer{
			CustomerId:    customerId,
			BillingTarget: tt.billingTarget,
		}
		_ = client.CreateCustomer(customer)
		customerIDs = append(customerIDs, customer.CustomerId)
	}
	// Adding a non-existing customer id results in us only return what is found
	customerIDs = append(customerIDs, "11111")
	customersResponse := client.GetCustomers(customerIDs)

	matchingOnCustomer := func(customerId string, billingTarget proto.BillingTarget) func(*proto.Customer) bool {
		return func(customer *proto.Customer) bool {
			return customer.CustomerId == customerId && customer.BillingTarget == billingTarget
		}
	}
	for _, customer := range customersData {
		g.Expect(customersResponse.Customers).Should(a.IncludeItem(matchingOnCustomer(customer.customerId, customer.billingTarget)))
	}
}

func Test_Customer_Create_Get_Customer_With_Disabled_Usage_Emission(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// EnabledProducts is an empty array by default
	customer := &proto.Customer{
		CustomerId:         stubs.GetRandomId64AsString(),
		BillingTarget:      proto.BillingTarget_Zuora,
		ZuoraAccountNumber: "123",
	}

	_ = client.CreateCustomer(customer)
	customerResponse := client.GetCustomer(customer.CustomerId)

	g.Expect(len(customerResponse.Customer.EnabledProducts)).To(gomega.Equal(0))
	g.Expect(customerResponse.Customer.EffectiveAt).To(gomega.Equal(int64(0)))

	// EnabledProducts explicitly set to an empty array
	anotherCustomer := &proto.Customer{
		CustomerId:      stubs.GetRandomId64AsString(),
		BillingTarget:   proto.BillingTarget_Zuora,
		ZuoraAccountId:  "456",
		EnabledProducts: []string{},
	}

	_ = client.CreateCustomer(anotherCustomer)
	anotherCustomerResponse := client.GetCustomer(anotherCustomer.CustomerId)

	g.Expect(len(customerResponse.Customer.EnabledProducts)).To(gomega.Equal(0))
	g.Expect(anotherCustomerResponse.Customer.EffectiveAt).To(gomega.Equal(int64(0)))
}

func Test_Customer_Create_Get_Customer_With_Enabled_Usage_Emission(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customer := &proto.Customer{
		CustomerId:      stubs.GetRandomId64AsString(),
		BillingTarget:   proto.BillingTarget_Zuora,
		ZuoraAccountId:  "123",
		EnabledProducts: []string{"actions"},
	}

	_ = client.CreateCustomer(customer)
	customerResponse := client.GetCustomer(customer.CustomerId)

	g.Expect(customerResponse.Customer.EnabledProducts).To(gomega.Equal(customer.EnabledProducts))
	g.Expect(customerResponse.Customer.EffectiveAt).To(gomega.BeNumerically(">", int64(0)))
}

func Test_Customer_Create_Get_Customer_AsCostCenter(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customer := &proto.Customer{
		CustomerId:        "999",
		CostCenterUUID:    uuid.NewString(),
		IsCostCenterProxy: true,
	}

	_ = client.CreateCustomer(customer)
	customerResponse := client.GetCustomer(customer.CostCenterUUID)

	g.Expect(customerResponse.Customer).To(gomega.Not(gomega.BeNil()))
	g.Expect(customerResponse.Customer.CustomerId).To(gomega.Equal(customer.CostCenterUUID))
	g.Expect(customerResponse.Customer.EnterpriseCustomerId).To(gomega.Equal(customer.CustomerId))
	g.Expect(customerResponse.Customer.CostCenterUUID).To(gomega.Equal(customer.CostCenterUUID))
	g.Expect(customerResponse.Customer.IsCostCenterProxy).To(gomega.Equal(customer.IsCostCenterProxy))
}

func Test_Customer_Create_Get_CustomerBudget(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Azure)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	amount := 99.9
	targetId := stubs.GetRandomId64AsString()
	targetType := proto.ResourceType_Enterprise

	budget := stubs.CreateBudgetWithLimitType(customerId, targetType, targetId, proto.PricingTargetType_SkuPricing, "sku", amount, proto.BudgetLimitType_PreventFurtherUsage)

	_ = client.UpsertBudget(budget)

	response := client.GetBudget(budget.Key)
	g.Expect(response.Budget).ToNot(gomega.BeNil())
	g.Expect(response.Budget.TargetAmount).To(gomega.Equal(amount))
	g.Expect(response.Budget.BudgetLimitType).To(gomega.Equal(proto.BudgetLimitType_PreventFurtherUsage))
}

func Test_Customer_Update_BudgetState(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	skuPrice1 := 10.0

	pricing1 := client.EnsureSpecificPricingExists(skuPrice1, "actions_windows_64_core", "actions", "Actions")

	entity := &hydroSchemaEntities.EntityDetail{
		CustomerId:     int64(stubs.GetRandomId()),
		OrganizationId: int64(stubs.GetRandomId()),
		RepoId:         int64(stubs.GetRandomId()),
		ActorId:        int64(stubs.GetRandomId()),
	}

	entity2 := &hydroSchemaEntities.EntityDetail{
		CustomerId:     entity.CustomerId,
		OrganizationId: int64(stubs.GetRandomId()),
		RepoId:         int64(stubs.GetRandomId()),
		ActorId:        int64(stubs.GetRandomId()),
	}

	customerId := fmt.Sprintf("%d", entity.CustomerId)
	orgId := fmt.Sprintf("%d", entity.OrganizationId)
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.CustomerId = customerId
	client.CreateCustomer(customerProto)

	costCenterOrgResource := &proto.Resource{Id: fmt.Sprintf("%d", entity2.OrganizationId), Type: proto.ResourceType_Org}
	costCenterRepoResource := &proto.Resource{Id: fmt.Sprintf("%d", entity2.RepoId), Type: proto.ResourceType_Repo}
	costCenter := stubs.CreateCostCenterWithAll(customerId, proto.CostCenterType_AzureSubscription, true, "test", []*proto.Resource{costCenterOrgResource, costCenterRepoResource})
	res, _ := client.CreateCostCenter(costCenter)
	costCenterId := res.CostCenter.CostCenterKey.Uuid
	repoId2 := fmt.Sprintf("%d", entity2.RepoId)
	orgId2 := fmt.Sprintf("%d", entity2.OrganizationId)
	targetAmount := 10.0

	orgBudget := stubs.CreateBudgetWithPricing(customerId, proto.ResourceType_Org, orgId, proto.PricingTargetType_ProductPricing, "actions", targetAmount)
	orgBudget2 := stubs.CreateBudgetWithPricing(customerId, proto.ResourceType_Org, orgId2, proto.PricingTargetType_ProductPricing, "actions", targetAmount)
	repoBudget := stubs.CreateBudgetWithPricing(customerId, proto.ResourceType_Repo, repoId2, proto.PricingTargetType_ProductPricing, "actions", targetAmount)
	costCenterBudget := stubs.CreateBudgetWithPricing(customerId, proto.ResourceType_CostCenterResource, costCenterId, proto.PricingTargetType_ProductPricing, "actions", targetAmount)
	enterpriseBudget := stubs.CreateBudgetWithPricing(customerId, proto.ResourceType_Enterprise, customerId, proto.PricingTargetType_ProductPricing, "actions", targetAmount)

	client.UpsertBudget(orgBudget)
	client.UpsertBudget(orgBudget2)
	client.UpsertBudget(repoBudget)
	client.UpsertBudget(costCenterBudget)
	client.UpsertBudget(enterpriseBudget)

	now := models.UTCNow()
	activeDate := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing1.Sku, 1, activeDate, entity)
	usage2 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing1.Sku, 1, activeDate, entity2)
	usages := []*hydroSchema.Usage{
		usage1, usage2,
	}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestionWithTimeTravel(len(usages), activeDate)

	// org budget state updates correctly when the org is not in a cost center
	response := client.GetBudgetState(orgBudget.Key, activeDate)
	g.Expect(response.BudgetState).ToNot(gomega.BeNil())
	g.Expect(response.BudgetState.TargetAmount).To(gomega.Equal(targetAmount))
	g.Expect(response.BudgetState.CurrentAmount).To(gomega.Equal(targetAmount))
	g.Expect(response.BudgetState.IsFullyFunded).To(gomega.BeTrue())

	newTargetAmount := 20.0

	orgBudget.TargetAmount = newTargetAmount
	client.UpsertBudget(orgBudget)

	testCases := []struct {
		name                  string
		budgetKey             *proto.BudgetKey
		expectedTargetAmount  float64
		expectedCurrentAmount float64
		isFullyFunded         bool
	}{
		{
			name:                  "org budget's budget state updates correctly after a target amount change (non cost center org)",
			budgetKey:             orgBudget.Key,
			expectedTargetAmount:  newTargetAmount,
			expectedCurrentAmount: usage1.Quantity * skuPrice1,
			isFullyFunded:         false,
		},
		{
			name:                  "org budget's budget state updates when org is in a cost center",
			budgetKey:             orgBudget2.Key,
			expectedTargetAmount:  targetAmount,
			expectedCurrentAmount: usage2.Quantity * skuPrice1,
			isFullyFunded:         true,
		},
		{
			name:                  "repo budget's budget state updates when repo is in a cost center",
			budgetKey:             repoBudget.Key,
			expectedTargetAmount:  targetAmount,
			expectedCurrentAmount: usage2.Quantity * skuPrice1,
			isFullyFunded:         true,
		},
		{
			name:                  "cost center budget's budget state updates correctly",
			budgetKey:             costCenterBudget.Key,
			expectedTargetAmount:  targetAmount,
			expectedCurrentAmount: usage2.Quantity * skuPrice1,
			isFullyFunded:         true,
		},
		{
			name:                  "enterprise budget's budget state updates with both cost center and non cost center usage",
			budgetKey:             enterpriseBudget.Key,
			expectedTargetAmount:  targetAmount,
			expectedCurrentAmount: (usage1.Quantity + usage2.Quantity) * skuPrice1,
			isFullyFunded:         true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			response := client.GetBudgetState(tc.budgetKey, activeDate)
			budgetState := response.BudgetState
			g.Expect(budgetState).ToNot(gomega.BeNil())
			g.Expect(budgetState.TargetAmount).To(gomega.Equal(tc.expectedTargetAmount))
			g.Expect(budgetState.CurrentAmount).To(gomega.Equal(tc.expectedCurrentAmount))
			g.Expect(budgetState.IsFullyFunded).To(gomega.Equal(tc.isFullyFunded))
		})
	}
}

func Test_Customer_Get_All_Budgets(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	skuPrice1 := 5.0

	pricing1 := client.EnsureSpecificPricingExists(skuPrice1, "actions_windows_64_core", "actions", "Actions")

	entity := &hydroSchemaEntities.EntityDetail{
		CustomerId:     int64(stubs.GetRandomId()),
		OrganizationId: int64(stubs.GetRandomId()),
		RepoId:         int64(stubs.GetRandomId()),
		ActorId:        int64(stubs.GetRandomId()),
	}

	customerId := fmt.Sprintf("%d", entity.CustomerId)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.CustomerId = customerId
	_ = client.CreateCustomer(customerProto)

	allBudgetsBeforeInserting := client.GetAllBudgets(customerId)
	g.Expect(len(allBudgetsBeforeInserting.Budgets)).To(gomega.Equal(0))

	customerBudget := stubs.CreateBudgetForNumeric(entity.CustomerId, proto.ResourceType_Enterprise, entity.CustomerId, 20.0)
	_ = client.UpsertBudget(customerBudget)

	orgBudget := stubs.CreateBudgetForNumeric(entity.CustomerId, proto.ResourceType_Org, entity.OrganizationId, 10.0)
	_ = client.UpsertBudget(orgBudget)
	now := models.UTCNow()
	activeDate := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing1.Sku, 1, activeDate, entity)
	usages := []*hydroSchema.Usage{
		usage1,
	}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestionWithTimeTravel(len(usages), activeDate)

	allBudgetsResponse := client.GetAllBudgets(customerId)
	u1 := client.GetBudgetState(customerBudget.Key, activeDate.UTC())
	u2 := client.GetBudgetState(orgBudget.Key, activeDate.UTC())
	g.Expect(u1.BudgetState).ToNot(gomega.BeNil())
	g.Expect(u2.BudgetState).ToNot(gomega.BeNil())
	g.Expect(allBudgetsResponse.Budgets).Should(a.IncludeItem(func(r *proto.BudgetInfo) bool {
		return r.Budget.Key.TargetId == customerBudget.Key.TargetId
	}))
	g.Expect(allBudgetsResponse.Budgets).Should(a.IncludeItem(func(r *proto.BudgetInfo) bool {
		return r.Budget.Key.TargetId == orgBudget.Key.TargetId
	}))
	g.Expect(allBudgetsResponse.Budgets).Should(a.IncludeItem(func(r *proto.BudgetInfo) bool {
		return r.BudgetState.CurrentAmount == u1.BudgetState.CurrentAmount &&
			r.BudgetState.TargetAmount == u1.BudgetState.TargetAmount &&
			r.BudgetState.Quantity == u1.BudgetState.Quantity &&
			r.BudgetState.IsFullyFunded == u1.BudgetState.IsFullyFunded &&
			r.BudgetState.ThresholdMet.Name == u1.BudgetState.ThresholdMet.Name &&
			r.BudgetState.ThresholdMet.MinimumUsagePercentage == u1.BudgetState.ThresholdMet.MinimumUsagePercentage &&
			r.BudgetState.ThresholdMet.Alertable == u1.BudgetState.ThresholdMet.Alertable
	}))
	g.Expect(allBudgetsResponse.Budgets).Should(a.IncludeItem(func(r *proto.BudgetInfo) bool {
		return r.BudgetState.CurrentAmount == u2.BudgetState.CurrentAmount &&
			r.BudgetState.TargetAmount == u2.BudgetState.TargetAmount &&
			r.BudgetState.Quantity == u2.BudgetState.Quantity &&
			r.BudgetState.IsFullyFunded == u2.BudgetState.IsFullyFunded &&
			r.BudgetState.ThresholdMet.Name == u2.BudgetState.ThresholdMet.Name &&
			r.BudgetState.ThresholdMet.MinimumUsagePercentage == u2.BudgetState.ThresholdMet.MinimumUsagePercentage &&
			r.BudgetState.ThresholdMet.Alertable == u2.BudgetState.ThresholdMet.Alertable
	}))

	g.Expect(len(allBudgetsResponse.Budgets)).To(gomega.Equal(2))
}

func Test_Customer_Get_All_Budgets_NotPersistent_Budget_States(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     int64(stubs.GetRandomId()),
		OrganizationId: int64(stubs.GetRandomId()),
	}

	customerId := fmt.Sprintf("%d", entity.CustomerId)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.CustomerId = customerId
	_ = client.CreateCustomer(customerProto)

	allBudgetsBeforeInserting := client.GetAllBudgets(customerId)
	g.Expect(len(allBudgetsBeforeInserting.Budgets)).To(gomega.Equal(0))

	customerBudget := stubs.CreateBudgetForNumeric(entity.CustomerId, proto.ResourceType_Enterprise, entity.CustomerId, 20.0)
	_ = client.UpsertBudget(customerBudget)

	orgBudget := stubs.CreateBudgetForNumeric(entity.CustomerId, proto.ResourceType_Org, entity.OrganizationId, 10.0)
	_ = client.UpsertBudget(orgBudget)
	now := models.UTCNow()
	activeDate := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)

	allBudgetsResponse := client.GetAllBudgets(customerId)
	u1 := client.GetBudgetState(customerBudget.Key, activeDate.UTC())
	u2 := client.GetBudgetState(orgBudget.Key, activeDate.UTC())
	g.Expect(u1.BudgetState.TargetAmount).To(gomega.Equal(customerBudget.TargetAmount))
	g.Expect(u2.BudgetState.TargetAmount).To(gomega.Equal(orgBudget.TargetAmount))

	g.Expect(allBudgetsResponse.Budgets).Should(a.IncludeItem(func(r *proto.BudgetInfo) bool {
		return r.BudgetState.TargetAmount == customerBudget.TargetAmount
	}))
	g.Expect(allBudgetsResponse.Budgets).Should(a.IncludeItem(func(r *proto.BudgetInfo) bool {
		return r.BudgetState.TargetAmount == orgBudget.TargetAmount
	}))
}

func Test_Customer_Get_Alertable_Budget_State_Info(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	skuPrice1 := 5.0

	pricing1 := client.EnsureSpecificPricingExists(skuPrice1, "actions_windows_64_core", "actions", "Actions")

	entity := &hydroSchemaEntities.EntityDetail{
		CustomerId:     int64(stubs.GetRandomId()),
		OrganizationId: int64(stubs.GetRandomId()),
		RepoId:         int64(stubs.GetRandomId()),
		ActorId:        int64(stubs.GetRandomId()),
	}

	customerId := fmt.Sprintf("%d", entity.CustomerId)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.CustomerId = customerId
	_ = client.CreateCustomer(customerProto)

	allBudgetsBeforeInserting := client.GetAlertableBudgetStateInfo(customerId)
	g.Expect(len(allBudgetsBeforeInserting.Budgets)).To(gomega.Equal(0))

	customerBudget := stubs.CreateBudgetForNumeric(entity.CustomerId, proto.ResourceType_Enterprise, entity.CustomerId, 0)
	_ = client.UpsertBudget(customerBudget)

	orgBudget := stubs.CreateBudgetForNumeric(entity.CustomerId, proto.ResourceType_Org, entity.OrganizationId, 10.0)
	_ = client.UpsertBudget(orgBudget)
	now := models.UTCNow()
	activeDate := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing1.Sku, 1, activeDate, entity)
	usages := []*hydroSchema.Usage{
		usage1,
	}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestionWithTimeTravel(len(usages), activeDate)

	allBudgetsResponse := client.GetAlertableBudgetStateInfo(customerId)
	u1 := client.GetBudgetState(customerBudget.Key, activeDate.UTC())
	u2 := client.GetBudgetState(orgBudget.Key, activeDate.UTC())

	g.Expect(u1.BudgetState).ToNot(gomega.BeNil())
	g.Expect(u2.BudgetState).ToNot(gomega.BeNil())

	g.Expect(allBudgetsResponse.Budgets).Should(a.IncludeItem(func(r *proto.BudgetInfo) bool {
		return r.Budget.Key.TargetId == customerBudget.Key.TargetId
	}))

	g.Expect(allBudgetsResponse.Budgets).Should(a.IncludeItem(func(r *proto.BudgetInfo) bool {
		return r.BudgetState.CurrentAmount == u1.BudgetState.CurrentAmount &&
			r.BudgetState.TargetAmount == u1.BudgetState.TargetAmount &&
			r.BudgetState.Quantity == u1.BudgetState.Quantity &&
			r.BudgetState.IsFullyFunded == u1.BudgetState.IsFullyFunded &&
			r.BudgetState.ThresholdMet.Name == u1.BudgetState.ThresholdMet.Name &&
			r.BudgetState.ThresholdMet.MinimumUsagePercentage == u1.BudgetState.ThresholdMet.MinimumUsagePercentage &&
			r.BudgetState.ThresholdMet.Alertable == u1.BudgetState.ThresholdMet.Alertable
	}))

	g.Expect(len(allBudgetsResponse.Budgets)).To(gomega.Equal(1))
}

func Test_Customer_Create_Update_CustomerBudget(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customer := &proto.Customer{
		CustomerId: stubs.GetRandomId64AsString(),
	}

	_ = client.CreateCustomer(customer)

	amount := 99.9
	targetId := stubs.GetRandomId64AsString()
	targetType := proto.ResourceType_Enterprise
	budgetAlerting := stubs.CreateBudgetAlerting([]string{customer.CustomerId})

	budget := stubs.CreateBudgetWithAlerting(customer.CustomerId, targetType, targetId, proto.PricingTargetType_SkuPricing, "sku", amount, proto.BudgetLimitType_PreventFurtherUsage, budgetAlerting)

	_ = client.UpsertBudget(budget)

	response := client.GetBudget(budget.Key)
	g.Expect(response.Budget).ToNot(gomega.BeNil())
	g.Expect(response.Budget.Uuid).ToNot(gomega.BeNil())
	g.Expect(response.Budget.TargetAmount).To(gomega.Equal(amount))
	g.Expect(response.Budget.BudgetLimitType).To(gomega.Equal(proto.BudgetLimitType_PreventFurtherUsage))
	g.Expect(response.Budget.BudgetAlerting.WillAlert).To(gomega.BeTrue())
	g.Expect(response.Budget.BudgetAlerting.RecipientUserIds).To(gomega.Equal([]string{customer.CustomerId}))

	amount = 199.99
	budget = stubs.CreateBudgetWithLimitType(customer.CustomerId, targetType, targetId, proto.PricingTargetType_SkuPricing, "sku", amount, proto.BudgetLimitType_PreventFurtherUsage)

	_ = client.UpsertBudget(budget)

	response = client.GetBudget(budget.Key)
	g.Expect(response.Budget).ToNot(gomega.BeNil())
	g.Expect(response.Budget.TargetAmount).To(gomega.Equal(amount))
	g.Expect(response.Budget.BudgetLimitType).To(gomega.Equal(proto.BudgetLimitType_PreventFurtherUsage))
}

func Test_Customer_Get_Budget_By_Uuid(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customer := &proto.Customer{
		CustomerId: stubs.GetRandomId64AsString(),
	}

	_ = client.CreateCustomer(customer)

	amount := 99.9
	targetId := stubs.GetRandomId64AsString()
	targetType := proto.ResourceType_Enterprise
	budgetAlerting := stubs.CreateBudgetAlerting([]string{customer.CustomerId})

	budget := stubs.CreateBudgetWithAlerting(customer.CustomerId, targetType, targetId, proto.PricingTargetType_SkuPricing, "sku", amount, proto.BudgetLimitType_PreventFurtherUsage, budgetAlerting)

	_ = client.UpsertBudget(budget)
	createdBudget := client.GetBudget(budget.Key).Budget

	response := client.GetBudgetByUuid(customer.CustomerId, createdBudget.Uuid)
	g.Expect(response.Budget.Key).To(gomega.Equal(createdBudget.Key))
}

func Test_Customer_Delete_Budget(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	skuPrice1 := 10.0

	pricing1 := client.EnsureSpecificPricingExists(skuPrice1, "actions_windows_64_core", "actions", "Actions")

	entity := &hydroSchemaEntities.EntityDetail{
		CustomerId:     int64(stubs.GetRandomId()),
		OrganizationId: int64(stubs.GetRandomId()),
	}

	customerId := fmt.Sprintf("%d", entity.CustomerId)
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.CustomerId = customerId
	client.CreateCustomer(customerProto)

	targetAmount := 10.0

	orgBudget := stubs.CreateBudgetWithPricing(customerId, proto.ResourceType_Org, fmt.Sprintf("%d", entity.OrganizationId), proto.PricingTargetType_ProductPricing, "actions", targetAmount)
	repoBudget := stubs.CreateBudgetWithPricing(customerId, proto.ResourceType_Repo, stubs.GetRandomId64AsString(), proto.PricingTargetType_ProductPricing, "actions", targetAmount)

	client.UpsertBudget(orgBudget)
	client.UpsertBudget(repoBudget)
	createdBudget := client.GetBudget(orgBudget.Key).Budget
	createdBudget2 := client.GetBudget(repoBudget.Key).Budget

	now := models.UTCNow()
	activeDate := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing1.Sku, 1, activeDate, entity)
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestionWithTimeTravel(len(usages), activeDate)

	// budget exists
	queryResponse := client.GetBudgetByUuid(customerId, createdBudget.Uuid)
	g.Expect(queryResponse.Budget.Key).To(gomega.Equal(createdBudget.Key))

	// repo budget exists
	queryResponse2 := client.GetBudgetByUuid(customerId, createdBudget2.Uuid)
	g.Expect(queryResponse2.Budget.Key).To(gomega.Equal(createdBudget2.Key))

	// org budget state exists with correct current amount
	response := client.GetBudgetState(orgBudget.Key, activeDate)
	g.Expect(response.BudgetState).ToNot(gomega.BeNil())
	g.Expect(response.BudgetState.CurrentAmount).To(gomega.Equal(10.0))

	// repo budget in-memory state is returned
	response = client.GetBudgetState(repoBudget.Key, activeDate)
	g.Expect(response.BudgetState).ToNot(gomega.BeNil())
	g.Expect(response.BudgetState.CurrentAmount).To(gomega.Equal(0.0))

	// delete org and repo budget
	client.DeleteBudget(customerId, createdBudget.Uuid)
	client.DeleteBudget(customerId, createdBudget2.Uuid)

	// org budgets no longer exist
	budgetExists := client.BudgetByUuidExists(customerId, createdBudget.Uuid)
	g.Expect(budgetExists).To(gomega.Equal(false))

	// repo budgets no longer exist
	budgetExists = client.BudgetByUuidExists(customerId, createdBudget2.Uuid)
	g.Expect(budgetExists).To(gomega.Equal(false))

	// org budget state no longer exists
	response = client.GetBudgetState(orgBudget.Key, activeDate)
	g.Expect(response).ToNot(gomega.BeNil())
	g.Expect(response.BudgetState).To(gomega.BeNil())
}

type BudgetTestData struct {
	fullyFunded    bool
	budgetTarget   float64
	expectedAmount float64
	quantity       float64
	limitType      proto.BudgetLimitType
	canProceed     bool
}

func Test_Customer_Budget_Across_Multiple_Skus(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	budgetTargetAmount := 56.3077
	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     int64(stubs.GetRandomId()),
		OrganizationId: int64(stubs.GetRandomId()),
		RepoId:         int64(stubs.GetRandomId()),
		ActorId:        int64(stubs.GetRandomId()),
	}

	// this for price and quantity. the sum of these * themselves is 56.3076
	skuPrice1 := 2.0
	skuPrice2 := 3.24
	skuPrice3 := 4.1
	skuPrice4 := 5.0

	pricing1 := client.EnsureSpecificPricingExists(skuPrice1, "actions_windows_64_core", "actions", "Actions")
	pricing2 := client.EnsureSpecificPricingExists(skuPrice2, "actions_windows_32_core", "actions", "Actions")
	pricing3 := client.EnsureSpecificPricingExists(skuPrice3, "actions_linux_64_core", "actions", "Actions")
	pricing4 := client.EnsureSpecificPricingExists(skuPrice4, "actions_linux_32_core", "actions", "Actions")

	customerId := fmt.Sprintf("%d", entity.CustomerId)
	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.EnabledProducts = []string{"actions"}
	customerProto.CustomerId = customerId

	_ = client.CreateCustomer(customerProto)

	budget := stubs.CreateBudgetWithPricing(customerId, proto.ResourceType_Enterprise, customerId, proto.PricingTargetType_ProductPricing, "actions", budgetTargetAmount)

	_ = client.UpsertBudget(budget)

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, pricing1.Price, customerId, time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC))
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing2.Sku, pricing2.Price, customerId, time.Date(2010, 11, 15, 4, 0, 0, 0, time.UTC))
	usage3 := stubs.CreateUsage(uuid.NewString(), pricing3.Sku, pricing3.Price, customerId, time.Date(2010, 11, 16, 5, 0, 0, 0, time.UTC))
	usage4 := stubs.CreateUsage(uuid.NewString(), pricing4.Sku, pricing4.Price, customerId, time.Date(2010, 11, 17, 6, 0, 0, 0, time.UTC))

	if usage1 == nil || usage2 == nil || usage3 == nil || usage4 == nil {
		t.Fail()
	}

	usages := []*hydroSchema.Usage{
		usage1,
		usage2,
		usage3,
		usage4,
	}

	client.ProduceMeteredUsage(usages)

	activeDate := time.Date(2024, 3, 18, 9, 0, 0, 0, time.UTC)
	client.RunUsageIngestionWithTimeTravel(len(usages), activeDate)

	// get usage from hourly bucket running total
	u := client.GetBudgetState(budget.Key, activeDate)
	g.Expect(u).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState.CurrentAmount).To(gomega.Equal(56.3076))
	g.Expect(u.BudgetState.IsFullyFunded).To(gomega.BeFalse())

	usage5 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, pricing1.Price, customerId, time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC))

	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage5})
	client.RunUsageIngestionWithTimeTravel(1, activeDate)

	u2 := client.GetBudgetState(budget.Key, activeDate)
	g.Expect(u2.BudgetState.IsFullyFunded).To(gomega.BeTrue())
}

func Test_Customer_Multiple_Budget_For_Same_SKU(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// this for price and quantity. the sum of these * themselves is 56.3076
	skuPrice1 := 5.0

	pricing1 := client.EnsureSpecificPricingExists(skuPrice1, "actions_windows_64_core", "actions", "Actions")

	entity := &hydroSchemaEntities.EntityDetail{
		CustomerId:     stubs.GetRandomId64(),
		OrganizationId: stubs.GetRandomId64(),
		RepoId:         stubs.GetRandomId64(),
		ActorId:        stubs.GetRandomId64(),
	}

	customerId := fmt.Sprintf("%d", entity.CustomerId)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.CustomerId = customerId
	_ = client.CreateCustomer(customerProto)

	customerBudget := stubs.CreateBudgetWithPricing(fmt.Sprintf("%d", entity.CustomerId), proto.ResourceType_Enterprise, fmt.Sprintf("%d", entity.CustomerId), proto.PricingTargetType_ProductPricing, "actions", 20.0)
	_ = client.UpsertBudget(customerBudget)

	orgBudget := stubs.CreateBudgetWithPricing(fmt.Sprintf("%d", entity.CustomerId), proto.ResourceType_Org, fmt.Sprintf("%d", entity.OrganizationId), proto.PricingTargetType_ProductPricing, "actions", 10.0)
	//orgBudget := stubs.CreateBudgetForNumeric(entity.CustomerId, proto.ResourceType_Org, entity.OrganizationId, 10.0)
	_ = client.UpsertBudget(orgBudget)

	repoBudget := stubs.CreateBudgetWithPricing(fmt.Sprintf("%d", entity.CustomerId), proto.ResourceType_Repo, fmt.Sprintf("%d", entity.RepoId), proto.PricingTargetType_ProductPricing, "actions", 5.0)
	//repoBudget := stubs.CreateBudgetForNumeric(entity.CustomerId, proto.ResourceType_Repo, entity.RepoId, 5.0)
	_ = client.UpsertBudget(repoBudget)

	userBudget := stubs.CreateBudgetWithPricing(fmt.Sprintf("%d", entity.CustomerId), proto.ResourceType_User, fmt.Sprintf("%d", entity.ActorId), proto.PricingTargetType_ProductPricing, "actions", 1.0)
	//userBudget := stubs.CreateBudgetForNumeric(entity.CustomerId, proto.ResourceType_User, entity.ActorId, 1.0)
	_ = client.UpsertBudget(userBudget)

	usage1 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing1.Sku, 1, time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC), entity)
	usage2 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing1.Sku, 1, time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC), entity)
	usage3 := stubs.CreateUsageWithEntity(uuid.NewString(), pricing1.Sku, 1, time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC), entity)
	usages := []*hydroSchema.Usage{
		usage1,
	}

	client.ProduceMeteredUsage(usages)

	activeDate := time.Date(2024, 3, 18, 9, 0, 0, 0, time.UTC)
	client.RunUsageIngestionWithTimeTravel(len(usages), activeDate)

	// validate user budget
	userStateFirstUsage := client.GetBudgetState(userBudget.Key, activeDate)
	g.Expect(userStateFirstUsage).To(gomega.Not(gomega.BeNil()))
	g.Expect(userStateFirstUsage.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(userStateFirstUsage.BudgetState.CurrentAmount).To(gomega.Equal(5.0))
	g.Expect(userStateFirstUsage.BudgetState.IsFullyFunded).To(gomega.BeTrue())

	repoStateFirstUsage := client.GetBudgetState(repoBudget.Key, activeDate)
	g.Expect(repoStateFirstUsage).To(gomega.Not(gomega.BeNil()))
	g.Expect(repoStateFirstUsage.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(repoStateFirstUsage.BudgetState.CurrentAmount).To(gomega.Equal(5.0))
	g.Expect(repoStateFirstUsage.BudgetState.IsFullyFunded).To(gomega.BeTrue())

	orgStateFirstUsage := client.GetBudgetState(orgBudget.Key, activeDate)
	g.Expect(orgStateFirstUsage).To(gomega.Not(gomega.BeNil()))
	g.Expect(orgStateFirstUsage.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(orgStateFirstUsage.BudgetState.CurrentAmount).To(gomega.Equal(5.0))
	g.Expect(orgStateFirstUsage.BudgetState.IsFullyFunded).To(gomega.BeFalse())

	customerStateFirstUsage := client.GetBudgetState(customerBudget.Key, activeDate)
	g.Expect(customerStateFirstUsage).To(gomega.Not(gomega.BeNil()))
	g.Expect(customerStateFirstUsage.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(customerStateFirstUsage.BudgetState.CurrentAmount).To(gomega.Equal(5.0))
	g.Expect(customerStateFirstUsage.BudgetState.IsFullyFunded).To(gomega.BeFalse())

	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage2, usage3})
	client.RunUsageIngestionWithTimeTravel(2, activeDate)

	customerStateThirdUsage := client.GetBudgetState(customerBudget.Key, activeDate)
	g.Expect(customerStateThirdUsage).To(gomega.Not(gomega.BeNil()))
	g.Expect(customerStateThirdUsage.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(customerStateThirdUsage.BudgetState.IsFullyFunded).To(gomega.BeFalse())
	g.Expect(customerStateThirdUsage.BudgetState.CurrentAmount).To(gomega.Equal(15.0))

	// validate user budget
	userStateThirdUsage := client.GetBudgetState(userBudget.Key, activeDate)
	g.Expect(userStateThirdUsage).To(gomega.Not(gomega.BeNil()))
	g.Expect(userStateThirdUsage.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(userStateThirdUsage.BudgetState.CurrentAmount).To(gomega.Equal(15.0))
	g.Expect(userStateThirdUsage.BudgetState.IsFullyFunded).To(gomega.BeTrue())

	repoStateThirdUsage := client.GetBudgetState(repoBudget.Key, activeDate)
	g.Expect(repoStateThirdUsage).To(gomega.Not(gomega.BeNil()))
	g.Expect(repoStateThirdUsage.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(repoStateThirdUsage.BudgetState.CurrentAmount).To(gomega.Equal(15.0))
	g.Expect(repoStateThirdUsage.BudgetState.IsFullyFunded).To(gomega.BeTrue())

	orgStateThirdUsage := client.GetBudgetState(orgBudget.Key, activeDate)
	g.Expect(orgStateThirdUsage).To(gomega.Not(gomega.BeNil()))
	g.Expect(orgStateThirdUsage.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(orgStateThirdUsage.BudgetState.CurrentAmount).To(gomega.Equal(15.0))
	g.Expect(orgStateThirdUsage.BudgetState.IsFullyFunded).To(gomega.BeTrue())
}

func Test_Customer_Budget_For_Product(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	budgetTargetAmount := 56.3077

	// this for price and quantity. the sum of these * themselves is 56.3076
	skuPrice1 := 2.0

	pricing1 := client.EnsureSpecificPricingExists(skuPrice1, "actions_windows_64_core", "actions", "Actions")

	_ = client.UpsertPricing(pricing1)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	targetType := proto.ResourceType_Enterprise
	budget := stubs.CreateBudgetWithPricing(customerId, targetType, customerId, proto.PricingTargetType_ProductPricing, pricing1.Product, budgetTargetAmount)
	_ = client.UpsertBudget(budget)

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, pricing1.Price, customerId, time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC))
	usages := []*hydroSchema.Usage{
		usage1,
	}

	client.ProduceMeteredUsage(usages)

	activeDate := time.Date(2024, 3, 18, 9, 0, 0, 0, time.UTC)
	client.RunUsageIngestionWithTimeTravel(len(usages), activeDate)

	// get usage from hourly bucket running total
	u := client.GetBudgetState(budget.Key, activeDate)
	g.Expect(u).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState.CurrentAmount).To(gomega.Equal(4.0))
	g.Expect(u.BudgetState.IsFullyFunded).To(gomega.BeFalse())

	budgetThatShouldNotBeActive := stubs.CreateBudgetKey(customerId, targetType, customerId)
	u2 := client.GetBudgetState(budgetThatShouldNotBeActive, activeDate)
	g.Expect(u2.BudgetState).To(gomega.BeNil(), "budget without product should not be active")
}

func Test_Customer_Budget_For_Sku(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	budgetTargetAmount := 56.3077

	// this for price and quantity. the sum of these * themselves is 56.3076
	price := 2.0
	pricing := client.EnsureSpecificPricingExists(price, "actions_windows_64_core", "actions", "Actions")

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	targetType := proto.ResourceType_Enterprise
	budget := stubs.CreateBudgetWithPricing(customerId, targetType, customerId, proto.PricingTargetType_SkuPricing, pricing.GetSku(), budgetTargetAmount)
	_ = client.UpsertBudget(budget)

	usage1 := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), pricing.GetPrice(), customerId, time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC))
	usages := []*hydroSchema.Usage{
		usage1,
	}

	client.ProduceMeteredUsage(usages)

	activeDate := time.Date(2024, 3, 18, 9, 0, 0, 0, time.UTC)
	client.RunUsageIngestionWithTimeTravel(len(usages), activeDate)

	// get usage from hourly bucket running total
	u := client.GetBudgetState(budget.Key, activeDate)
	g.Expect(u).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState.CurrentAmount).To(gomega.Equal(4.0))
	g.Expect(u.BudgetState.IsFullyFunded).To(gomega.BeFalse())

	budgetThatShouldNotBeActive := stubs.CreateBudgetKey(customerId, targetType, customerId)
	u2 := client.GetBudgetState(budgetThatShouldNotBeActive, activeDate)
	g.Expect(u2.BudgetState).To(gomega.BeNil(), "budget without product should not be active")
}

func Test_Customer_CanProcessUsage(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	hardLimitsData := []BudgetTestData{
		{limitType: proto.BudgetLimitType_StopActiveUsage},
		{limitType: proto.BudgetLimitType_PreventFurtherUsage},
	}

	softLimitsData := []BudgetTestData{
		{limitType: proto.BudgetLimitType_AlertingOnly},
		{limitType: proto.BudgetLimitType_IgnoreLimit},
	}

	for _, tt := range hardLimitsData {
		t.Run(fmt.Sprintf("FullyFunded_%v", tt.limitType), func(t *testing.T) {
			tt.fullyFunded = true
			tt.budgetTarget = 5.0
			tt.expectedAmount = 5.0
			tt.quantity = 3.0
			tt.canProceed = false
			testCanProceed(tt, client, g)
		})
		t.Run(fmt.Sprintf("NotFullyFunded_%v", tt.limitType), func(t *testing.T) {
			tt.fullyFunded = false
			tt.budgetTarget = 5.0
			tt.expectedAmount = 4.0
			tt.quantity = 2.0
			tt.canProceed = true
			testCanProceed(tt, client, g)
		})
	}

	for _, tt := range softLimitsData {
		t.Run(fmt.Sprintf("FullyFunded_%v", tt.limitType), func(t *testing.T) {
			tt.fullyFunded = true
			tt.budgetTarget = 5.0
			tt.expectedAmount = 6.0
			tt.quantity = 3.0
			tt.canProceed = true
			testCanProceed(tt, client, g)
		})
		t.Run(fmt.Sprintf("NotFullyFunded_%v", tt.limitType), func(t *testing.T) {
			tt.fullyFunded = false
			tt.budgetTarget = 5.0
			tt.expectedAmount = 4.0
			tt.quantity = 2.0
			tt.canProceed = true
			testCanProceed(tt, client, g)
		})
	}
}
func testCanProceed(tt BudgetTestData, client *integration.IntegrationClient, g *gomega.GomegaWithT) {
	pricing1 := client.EnsureSpecificPricingExists(2.0, "actions_windows_64_core", "actions", "Actions")
	_ = client.UpsertPricing(pricing1)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.HasPaymentMethod = true
	customerProto.HasZuoraSubscription = true
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	targetType := proto.ResourceType_Enterprise
	budget := stubs.CreateBudgetWithLimitType(customerId, targetType, customerId, proto.PricingTargetType_SkuPricing, pricing1.Sku, tt.budgetTarget, tt.limitType)
	_ = client.UpsertBudget(budget)

	usageDate := time.Date(2010, 11, 14, 3, 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, tt.quantity, customerId, usageDate)
	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage})

	activeDate := time.Date(2024, 3, 18, 9, 0, 0, 0, time.UTC)
	client.RunUsageIngestionWithTimeTravel(1, activeDate)

	// get usage from hourly bucket running total
	u := client.GetBudgetState(budget.Key, activeDate)
	g.Expect(u).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState.CurrentAmount).To(gomega.Equal(tt.expectedAmount))
	g.Expect(u.BudgetState.IsFullyFunded).To(gomega.Equal(tt.fullyFunded))

	canProceedWithUsage := client.CanProceedWithUsage(pricing1, usage.Entity, activeDate)

	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(tt.canProceed))
	g.Expect(canProceedWithUsage.PlanName).To(gomega.Equal("enterprise"))
}

func Test_Can_Proceed_With_Customer_Not_Found(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	now := models.UTCNow()

	pricing1 := client.EnsureSpecificPricingExists(0.0875, "git_lfs_bandwidth", "git_lfs", "Git LFS")
	_ = client.UpsertPricing(pricing1)

	customerId := stubs.GetRandomId64AsString()

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)

	canProceedWithUsageError := client.CanProceedWithUsageError(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsageError).Should(gomega.Equal(twirp.NewError(
		twirp.NotFound,
		fmt.Sprintf("Customer with id %s not found", customerId),
	)))
}

func Test_Customer_Can_Proceed_With_Billing_Locked(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	now := models.UTCNow()

	pricing1 := client.EnsureSpecificPricingExists(0.0875, "git_lfs_bandwidth", "git_lfs", "Git LFS")
	_ = client.UpsertPricing(pricing1)

	// customer without Azure or Zuora details
	customerProto := &proto.Customer{
		CustomerId:       stubs.GetRandomId64AsString(),
		DiscountPlanName: "enterprise",
	}
	customerProto.EnabledProducts = []string{"git_lfs"}
	customerProto.IsBillingLocked = true
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	canProceedWithUsage := client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_BillingLocked))
}

func Test_Customer_Can_Proceed_With_Full_Trade_Restrictions(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	now := models.UTCNow()

	pricing1 := client.EnsureSpecificPricingExists(0.0875, "git_lfs_bandwidth", "git_lfs", "Git LFS")
	_ = client.UpsertPricing(pricing1)

	// customer without Azure or Zuora details
	customerProto := &proto.Customer{
		CustomerId:       stubs.GetRandomId64AsString(),
		DiscountPlanName: "enterprise",
	}
	customerProto.EnabledProducts = []string{"git_lfs"}
	customerProto.IsBillingLocked = false
	customerProto.TradeScreening = &proto.TradeScreening{
		HasFullTradeRestrictions: true,
	}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	canProceedWithUsage := client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_FullTradeRestrictionsApplied))
}

func Test_Customer_Can_Proceed_With_Any_Trade_Restrictions(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	now := models.UTCNow()

	pricing1 := client.EnsureSpecificPricingExists(0.0875, "git_lfs_bandwidth", "git_lfs", "Git LFS")
	_ = client.UpsertPricing(pricing1)

	// customer without Azure or Zuora details
	customerProto := &proto.Customer{
		CustomerId:       stubs.GetRandomId64AsString(),
		DiscountPlanName: "enterprise",
	}
	customerProto.EnabledProducts = []string{"git_lfs"}
	customerProto.IsBillingLocked = false
	customerProto.TradeScreening = &proto.TradeScreening{
		HasFullTradeRestrictions: false,
		HasAnyTradeRestrictions:  true,
	}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	canProceedWithUsage := client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_AnyTradeRestrictionsApplied))
}

func Test_Customer_Can_Proceed_With_Commercial_Interaction_Restriction(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	now := models.UTCNow()

	pricing1 := client.EnsureSpecificPricingExists(0.0875, "git_lfs_bandwidth", "git_lfs", "Git LFS")
	_ = client.UpsertPricing(pricing1)

	// customer without Azure or Zuora details
	customerProto := &proto.Customer{
		CustomerId:       stubs.GetRandomId64AsString(),
		DiscountPlanName: "enterprise",
	}
	customerProto.EnabledProducts = []string{"git_lfs"}
	customerProto.IsBillingLocked = false
	customerProto.TradeScreening = &proto.TradeScreening{
		HasFullTradeRestrictions:                      false,
		HasAnyTradeRestrictions:                       false,
		FeaturesWithCommercialInteractionRestrictions: []string{"cost_management"},
	}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	canProceedWithUsage := client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_CommercialInteractionRestrictionApplied))
}

func Test_Customer_Can_Proceed_With_Commercial_Interaction_Restriction_For_Copilot(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	now := models.UTCNow()

	pricing1 := client.EnsureSpecificPricingExists(19.0, "copilot_for_business", "copilot", "Copilot Business")
	_ = client.UpsertPricing(pricing1)

	pricing2 := client.EnsureSpecificPricingExists(0.0875, "git_lfs_bandwidth", "git_lfs", "Git LFS")
	_ = client.UpsertPricing(pricing2)

	// customer without Azure or Zuora details
	customerProto := &proto.Customer{
		CustomerId:       stubs.GetRandomId64AsString(),
		DiscountPlanName: "enterprise",
	}
	customerProto.EnabledProducts = []string{"copilot", "git_lfs"}
	customerProto.IsBillingLocked = false
	customerProto.TradeScreening = &proto.TradeScreening{
		HasFullTradeRestrictions:                      false,
		HasAnyTradeRestrictions:                       false,
		FeaturesWithCommercialInteractionRestrictions: []string{"copilot_vnext"},
	}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)
	usage2 := stubs.CreateUsage(uuid.NewString(), pricing2.Sku, 1, customerId, usageDate)
	usages := []*hydroSchema.Usage{usage1, usage2}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	// Cannot proceed with copilot usage
	canProceedWithUsage := client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_CommercialInteractionRestrictionApplied))

	// Can proceed with git_lfs usage
	canProceedWithUsage = client.CanProceedWithUsage(pricing2, usage2.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_UsageAllowed))
}

func Test_Customer_Can_Proceed_Without_Applicable_Discounts(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	now := models.UTCNow()

	pricing1 := client.EnsureSpecificPricingExists(19.0, "copilot_for_business", "copilot", "Copilot")
	_ = client.UpsertPricing(pricing1)

	// customer without Azure or Zuora details
	customerProto := &proto.Customer{
		CustomerId:       stubs.GetRandomId64AsString(),
		DiscountPlanName: "enterprise",
	}
	customerProto.EnabledProducts = []string{"copilot"}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))

	// can't proceed because there are no applicable discounts for Copilot
	canProceedWithUsage := client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_NotBillable))
	g.Expect(len(canProceedWithUsage.PlanDiscounts)).To(gomega.Equal(0))

	customerProto = &proto.Customer{
		CustomerId:           customerId,
		BillingTarget:        proto.BillingTarget_Zuora,
		ZuoraAccountId:       stubs.GetRandomId64AsString(),
		ZuoraAccountNumber:   stubs.GetRandomZuoraAccountNumber(),
		DiscountPlanName:     "enterprise",
		HasPaymentMethod:     true,
		HasZuoraSubscription: true,
	}
	customerProto.EnabledProducts = []string{"copilot"}
	_ = client.CreateCustomer(customerProto)

	// can proceed when payment method and subscription are present
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_UsageAllowed))
	g.Expect(len(canProceedWithUsage.PlanDiscounts)).To(gomega.Equal(0))
}

func Test_Customer_Can_Proceed_With_Discounts_Fully_Applied(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	now := models.UTCNow()

	pricing1 := client.EnsureSpecificPricingExists(0.0875, "git_lfs_bandwidth", "git_lfs", "Git LFS")
	_ = client.UpsertPricing(pricing1)

	// customer without Azure or Zuora details
	customerProto := &proto.Customer{
		CustomerId:       stubs.GetRandomId64AsString(),
		DiscountPlanName: "enterprise",
	}
	customerProto.EnabledProducts = []string{"git_lfs"}
	customerProto.HasPaymentMethod = true
	customerProto.HasZuoraSubscription = true
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 7752, customerId, usageDate)
	usages := []*hydroSchema.Usage{usage1}

	// can proceed because there is no usage yet and discounts are available
	canProceedWithUsage := client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_UsageAllowed))
	g.Expect(len(canProceedWithUsage.PlanDiscounts)).To(gomega.Equal(0))

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDiscountStateUpdateJob(len(usages))

	// can't proceed because discounts are fully applied
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_NotBillable))
	g.Expect(len(canProceedWithUsage.PlanDiscounts)).To(gomega.Equal(1))
	g.Expect(canProceedWithUsage.PlanDiscounts[0].IsFullyApplied).To(gomega.BeTrue())

	// can proceed because discounts for "git_lfs_storage" are not fully applied
	pricing1.Sku = "git_lfs_storage"
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))

	customerProto = &proto.Customer{
		CustomerId:           customerId,
		BillingTarget:        proto.BillingTarget_Zuora,
		ZuoraAccountId:       stubs.GetRandomId64AsString(),
		ZuoraAccountNumber:   stubs.GetRandomZuoraAccountNumber(),
		DiscountPlanName:     "enterprise",
		HasPaymentMethod:     true,
		HasZuoraSubscription: true,
	}
	customerProto.EnabledProducts = []string{"git_lfs"}
	_ = client.CreateCustomer(customerProto)

	// can proceed since we added Zuora credentials to the customer
	pricing1.Sku = "git_lfs_bandwidth"
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_UsageAllowed))

	// can't proceed since we switched the customer to the trial plan and discounts are fully applied
	customerProto = &proto.Customer{
		CustomerId:       customerId,
		DiscountPlanName: "enterprise_trial",
	}
	customerProto.EnabledProducts = []string{"git_lfs"}
	_ = client.CreateCustomer(customerProto)

	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_OnTrial))
}

func Test_Customer_Can_Proceed_With_Discounts_Partially_Applied(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	now := models.UTCNow()

	pricing1 := client.EnsureSpecificPricingExists(0.0875, "git_lfs_bandwidth", "git_lfs", "Git LFS")
	_ = client.UpsertPricing(pricing1)

	// customer without Azure or Zuora details
	customerProto := &proto.Customer{
		CustomerId:       stubs.GetRandomId64AsString(),
		DiscountPlanName: "enterprise",
	}
	customerProto.EnabledProducts = []string{"git_lfs"}
	customerProto.HasPaymentMethod = false
	customerProto.HasZuoraSubscription = false
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 1, customerId, usageDate)
	usages := []*hydroSchema.Usage{usage1}

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDiscountStateUpdateJob(len(usages))

	// can proceed because discounts are not fully applied
	canProceedWithUsage := client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_UsageAllowed))
	g.Expect(len(canProceedWithUsage.PlanDiscounts)).To(gomega.Equal(1))
	g.Expect(canProceedWithUsage.PlanDiscounts[0].IsFullyApplied).To(gomega.BeFalse())
	g.Expect(canProceedWithUsage.PlanDiscounts[0].CurrentAmount).To(gomega.Equal(0.0875))
	g.Expect(canProceedWithUsage.PlanDiscounts[0].TargetAmount).To(gomega.Equal(21.875))
	g.Expect(canProceedWithUsage.PlanDiscounts[0].Uuid).To(gomega.Equal("dd97934f-1d5c-48c6-b821-22f98da6acfd")) // lfsBandwidth250GiBDiscount
}

func Test_Customer_Can_Proceed_With_Zuora_CostCenter_And_Discounts_Fully_Applied(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	now := models.UTCNow()

	pricing1 := client.EnsureSpecificPricingExists(0.0875, "git_lfs_bandwidth", "git_lfs", "Git LFS")
	_ = client.UpsertPricing(pricing1)

	// customer without Azure or Zuora details
	customerProto := &proto.Customer{
		CustomerId:       stubs.GetRandomId64AsString(),
		DiscountPlanName: "enterprise",
	}
	customerProto.EnabledProducts = []string{"git_lfs"}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 7752, customerId, usageDate)
	usages := []*hydroSchema.Usage{usage1}

	costCenterRepoId := usage1.Entity.RepoId

	// cost center without Azure or Zuora details
	costCenterProto := &proto.CostCenter{
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: customerId,
			TargetType: proto.CostCenterType_ZuoraSubscription,
			TargetId:   "",
		},
		Name: "TestCostCenter",
		Resources: []*proto.Resource{
			{
				Id:   fmt.Sprintf("%d", costCenterRepoId),
				Type: proto.ResourceType_Repo,
			}},
	}

	costCenterResponse, _ := client.CreateCostCenter(costCenterProto)

	// can proceed because there is no usage yet and discounts are available
	canProceedWithUsage := client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDiscountStateUpdateJob(len(usages))

	// can't proceed with the usage associated with the cost center because discounts are fully applied and shared
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))

	// can't proceed with the usage associated with the customer because discounts are fully applied and shared
	usage1.Entity.RepoId = stubs.GetRandomId64()
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))

	// adding Zuora details to the customer
	customerProto.HasPaymentMethod = true
	customerProto.HasZuoraSubscription = true
	customerProto.BillingTarget = proto.BillingTarget_Zuora
	customerProto.ZuoraAccountNumber = stubs.GetRandomZuoraAccountNumber()
	_ = client.CreateCustomer(customerProto)

	// customer can proceed
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))
	// cost center can proceed
	usage1.Entity.RepoId = costCenterRepoId
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))

	// removing Zuora details from the customer
	customerProto.BillingTarget = proto.BillingTarget_NoBillingTarget
	customerProto.ZuoraAccountNumber = ""
	_ = client.CreateCustomer(customerProto)

	// adding Zuora details to the cost center
	costCenterProto.CostCenterKey.TargetId = stubs.GetRandomId64AsString()
	costCenterProto.CostCenterKey.Uuid = costCenterResponse.CostCenter.CostCenterKey.Uuid
	costCenterRepoId = stubs.GetRandomId64()
	costCenterProto.Resources = []*proto.Resource{
		{
			Id:   fmt.Sprintf("%d", costCenterRepoId),
			Type: proto.ResourceType_Repo,
		}}

	updateArgs := integration.UpdateCostCenterArgs{
		CostCenterKey:     costCenterProto.CostCenterKey,
		Name:              costCenterProto.Name,
		TargetId:          costCenterProto.CostCenterKey.TargetId,
		ResourcesToAdd:    costCenterProto.Resources,
		ResourcesToRemove: []*proto.Resource{}, // Assuming no resources to remove in this context
	}

	r, err := client.UpdateCostCenter(updateArgs)
	g.Expect(err).ToNot(gomega.HaveOccurred())
	g.Expect(r.CostCenter.CostCenterKey.TargetId).ToNot(gomega.Equal(0))

	// still can't proceed with the usage associated with the cost center because Zuora details on it mean nothing at this point :/
	usage1.Entity.RepoId = costCenterRepoId
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))

	// can't proceed with the customer usage
	usage1.Entity.RepoId = stubs.GetRandomId64()
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))
}

func Test_Customer_Can_Proceed_With_Azure_CostCenter_And_Discounts_Fully_Applied(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	now := models.UTCNow()

	pricing1 := client.EnsureSpecificPricingExists(0.0875, "git_lfs_bandwidth", "git_lfs", "Git LFS")
	_ = client.UpsertPricing(pricing1)

	// customer without Azure or Zuora details
	customerProto := &proto.Customer{
		CustomerId:       stubs.GetRandomId64AsString(),
		DiscountPlanName: "enterprise",
	}
	customerProto.EnabledProducts = []string{"git_lfs"}
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage1 := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 7752, customerId, usageDate)
	usages := []*hydroSchema.Usage{usage1}

	costCenterRepoId := usage1.Entity.RepoId

	// cost center without Azure or Zuora details
	costCenterProto := &proto.CostCenter{
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: customerId,
			TargetType: proto.CostCenterType_AzureSubscription,
			TargetId:   "",
		},
		Name: "TestCostCenter",
		Resources: []*proto.Resource{
			{
				Id:   fmt.Sprintf("%d", costCenterRepoId),
				Type: proto.ResourceType_Repo,
			}},
	}

	costCenterResponse, _ := client.CreateCostCenter(costCenterProto)

	// can proceed because there is no usage yet and discounts are available
	canProceedWithUsage := client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDiscountStateUpdateJob(len(usages))

	// can't proceed with the usage associated with the cost center because discounts are fully applied and shared
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))

	// can't proceed with the usage associated with the customer because discounts are fully applied and shared
	usage1.Entity.RepoId = stubs.GetRandomId64()
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))

	// adding Azure details to the customer
	customerProto.HasPaymentMethod = true
	customerProto.HasZuoraSubscription = true
	customerProto.BillingTarget = proto.BillingTarget_Azure
	customerProto.AzureAccountId = uuid.NewString()
	_ = client.CreateCustomer(customerProto)

	// customer can proceed
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))
	// cost center can proceed
	usage1.Entity.RepoId = costCenterRepoId
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))

	// removing Azure details from the customer
	customerProto.BillingTarget = proto.BillingTarget_NoBillingTarget
	customerProto.AzureAccountId = ""
	_ = client.CreateCustomer(customerProto)

	// adding Azure details to the cost center
	costCenterProto.CostCenterKey.TargetId = uuid.NewString()
	costCenterProto.CostCenterKey.Uuid = costCenterResponse.CostCenter.CostCenterKey.Uuid
	costCenterRepoId = stubs.GetRandomId64()
	costCenterProto.Resources = []*proto.Resource{
		{
			Id:   fmt.Sprintf("%d", costCenterRepoId),
			Type: proto.ResourceType_Repo,
		}}

	updateArgs := integration.UpdateCostCenterArgs{
		CostCenterKey:     costCenterProto.CostCenterKey,
		Name:              costCenterProto.Name,
		TargetId:          costCenterProto.CostCenterKey.TargetId,
		ResourcesToAdd:    costCenterProto.Resources,
		ResourcesToRemove: []*proto.Resource{},
	}

	r, err := client.UpdateCostCenter(updateArgs)
	g.Expect(err).ToNot(gomega.HaveOccurred())
	g.Expect(r.CostCenter.CostCenterKey.TargetId).ToNot(gomega.Equal(""))

	// can proceed with the usage associated with the cost center because it has Azure account id now
	usage1.Entity.RepoId = costCenterRepoId
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))

	// but still can't proceed with the customer usage
	usage1.Entity.RepoId = stubs.GetRandomId64()
	canProceedWithUsage = client.CanProceedWithUsage(pricing1, usage1.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))
}

func Test_Customer_Can_Proceed_WithCostCenterBudgets(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	now := models.UTCNow()

	actionsWindows64 := client.EnsureSpecificPricingExists(2.0, "actions_windows_64_core", "actions", "Actions")
	_ = client.UpsertPricing(actionsWindows64)
	actionsLinux := client.EnsureSpecificPricingExists(2.0, "actions_linux", "actions", "Actions")
	_ = client.UpsertPricing(actionsLinux)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.HasPaymentMethod = true
	customerProto.HasZuoraSubscription = true
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	actionsWindows64Usage := stubs.CreateUsage(uuid.NewString(), actionsWindows64.Sku, 11, customerId, usageDate)
	usages := []*hydroSchema.Usage{actionsWindows64Usage}

	costCenterOrgId := actionsWindows64Usage.Entity.OrganizationId

	costCenterProto := &proto.CostCenter{
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: customerId,
			TargetType: proto.CostCenterType_ZuoraSubscription,
			TargetId:   "",
		},
		Name: "TestCostCenter",
		Resources: []*proto.Resource{
			{
				Id:   fmt.Sprintf("%d", costCenterOrgId),
				Type: proto.ResourceType_Org,
			}},
	}

	costCenterResponse, _ := client.CreateCostCenter(costCenterProto)

	costCenterBudget := stubs.CreateBudgetWithLimitType(
		customerId,
		proto.ResourceType_CostCenterResource,
		costCenterResponse.CostCenter.CostCenterKey.Uuid,
		proto.PricingTargetType_ProductPricing,
		"actions",
		10,
		proto.BudgetLimitType_PreventFurtherUsage,
	)
	_ = client.UpsertBudget(costCenterBudget)

	canProceedWithUsage := client.CanProceedWithUsage(actionsWindows64, actionsWindows64Usage.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true)) // can proceed because there is no usage yet

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDiscountStateUpdateJob(len(usages))

	canProceedWithUsage = client.CanProceedWithUsage(actionsWindows64, actionsWindows64Usage.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false)) // can't proceed because budget is fully funded and SKU is not discounted

	applicableBudget := canProceedWithUsage.ApplicableBudgets[0]
	g.Expect(applicableBudget.BudgetLimitType).To(gomega.Equal(proto.BudgetLimitType_PreventFurtherUsage))
	g.Expect(applicableBudget.BudgetState.CurrentAmount).To(gomega.Equal(10.0))
	g.Expect(applicableBudget.BudgetState.IsFullyFunded).To(gomega.Equal(true))

	actionsLinuxUsage := stubs.CreateUsage(uuid.NewString(), actionsLinux.Sku, 50000, customerId, usageDate)
	actionsLinuxUsage.Entity = actionsWindows64Usage.Entity
	usages = []*hydroSchema.Usage{actionsLinuxUsage}

	canProceedWithUsage = client.CanProceedWithUsage(actionsLinux, actionsLinuxUsage.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true)) // can proceed because of the included discounts for that SKU

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDiscountStateUpdateJob(len(usages))

	canProceedWithUsage = client.CanProceedWithUsage(actionsLinux, actionsLinuxUsage.Entity, now.Time)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false)) // can't proceed because budget is fully funded and discounts are exhausted
}

func Test_Customer_Can_Proceed_WithManyBudgets(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{
		PreserveData: true,
	})
	defer client.Close()

	pricing1 := client.EnsureSpecificPricingExists(2.0, "actions_windows_64_core", "actions", "Actions")
	_ = client.UpsertPricing(pricing1)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.HasPaymentMethod = true
	customerProto.HasZuoraSubscription = true
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), pricing1.Sku, 4, customerId, usageDate)
	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage})

	enterpriseBudget := stubs.CreateBudgetWithLimitType(customerId, proto.ResourceType_Enterprise, customerId, proto.PricingTargetType_ProductPricing, "actions", 1000.0, proto.BudgetLimitType_StopActiveUsage)
	_ = client.UpsertBudget(enterpriseBudget)
	orgBudget := stubs.CreateBudgetWithLimitType(customerId, proto.ResourceType_Org, fmt.Sprintf("%d", usage.Entity.OrganizationId), proto.PricingTargetType_ProductPricing, "actions", 2000.0, proto.BudgetLimitType_StopActiveUsage)
	_ = client.UpsertBudget(orgBudget)
	repoBudget := stubs.CreateBudgetWithLimitType(customerId, proto.ResourceType_Repo, fmt.Sprintf("%d", usage.Entity.RepoId), proto.PricingTargetType_ProductPricing, "actions", 3000.0, proto.BudgetLimitType_StopActiveUsage)
	_ = client.UpsertBudget(repoBudget)
	actorBudget := stubs.CreateBudgetWithLimitType(customerId, proto.ResourceType_User, fmt.Sprintf("%d", usage.Entity.ActorId), proto.PricingTargetType_ProductPricing, "actions", 5.0, proto.BudgetLimitType_StopActiveUsage)
	_ = client.UpsertBudget(actorBudget)

	activeDate := time.Date(2024, 4, 1, 3, 0, 0, 0, time.UTC)
	client.RunUsageIngestionWithTimeTravel(1, activeDate)

	// get usage from hourly bucket running total
	u := client.GetBudgetState(enterpriseBudget.Key, activeDate)
	g.Expect(u).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState.CurrentAmount).To(gomega.Equal(5.0))
	g.Expect(u.BudgetState.IsFullyFunded).To(gomega.Equal(false))

	u = client.GetBudgetState(orgBudget.Key, activeDate)
	g.Expect(u).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState.CurrentAmount).To(gomega.Equal(5.0))
	g.Expect(u.BudgetState.IsFullyFunded).To(gomega.Equal(false))

	u = client.GetBudgetState(repoBudget.Key, activeDate)
	g.Expect(u).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState.CurrentAmount).To(gomega.Equal(5.0))
	g.Expect(u.BudgetState.IsFullyFunded).To(gomega.Equal(false))

	u = client.GetBudgetState(actorBudget.Key, activeDate)
	g.Expect(u).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState).To(gomega.Not(gomega.BeNil()))
	g.Expect(u.BudgetState.CurrentAmount).To(gomega.Equal(5.0))
	g.Expect(u.BudgetState.IsFullyFunded).To(gomega.Equal(true))

	canProceedWithUsage := client.CanProceedWithUsage(pricing1, usage.Entity, activeDate)

	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false))
	g.Expect(canProceedWithUsage.Status).To(gomega.Equal(proto.CanProceedWithUsageStatus_BudgetLimitReached))
	g.Expect(canProceedWithUsage.ApplicableBudgets).To(a.IncludeItem(func(i *proto.CanProceedWithUsageInfo) bool {
		return i.BudgetKey.CustomerId == actorBudget.Key.CustomerId &&
			i.BudgetKey.TargetType == actorBudget.Key.TargetType &&
			i.BudgetKey.TargetId == actorBudget.Key.TargetId
	}))
}

func TestAdmin_CreateChargeWithAmount(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(2.0, "actions_windows_64_core", "actions", "Actions")
	_ = client.UpsertPricing(pricing)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	now := models.NewUsageTimeFromTime(time.Now()).Time

	_ = client.AdminGenerateUsage(&proto.GenerateUsageRequest{
		CustomerId: customerId,
		Sku:        pricing.GetSku(),
		Amount:     10.00,
	})

	client.ValidateQueue(1, models.WorkerTypeUsageIngestion)
	client.RunUsageIngestion(1)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	client.RunDailyJob(1)

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(1), "a line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(5.00))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(10.00))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
	g.Expect(billingItem.OrgId).Should(gomega.Equal(int64(0)))
	g.Expect(billingItem.RepoId).Should(gomega.Equal(int64(0)))
}

func Test_Customer_Can_Proceed_With_Azure_But_No_Payment_Method(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(2.0, "actions_windows_64_core", "actions", "Actions")
	_ = client.UpsertPricing(pricing)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Azure)
	customerProto.HasPaymentMethod = false
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Date(2023, 4, 30, 3, 0, 0, 0, time.UTC)
	usage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 4, customerId, usageDate)
	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage})

	activeDate := time.Date(2024, 4, 1, 3, 0, 0, 0, time.UTC)
	client.RunUsageIngestionWithTimeTravel(1, activeDate)

	canProceedWithUsage := client.CanProceedWithUsage(pricing, usage.Entity, activeDate)

	g.Expect(customerProto.HasPaymentMethod).To(gomega.Equal(false))
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true))
	g.Expect(canProceedWithUsage.ApplicableBudgets).To(gomega.BeEmpty())
}

func TestAdmin_CreateChargeWithQuantity(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(2.0, "actions_windows_64_core", "actions", "Actions")
	_ = client.UpsertPricing(pricing)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	now := models.NewUsageTimeFromTime(time.Now()).Time

	_ = client.AdminGenerateUsage(&proto.GenerateUsageRequest{
		CustomerId: customerId,
		Sku:        pricing.GetSku(),
		Quantity:   5.00,
	})

	client.ValidateQueue(1, models.WorkerTypeUsageIngestion)
	client.RunUsageIngestion(1)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	client.RunDailyJob(1)

	u := client.GetUsageLineItems("", "", customerId, now, proto.BillingPeriod_Daily)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(1), "a line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(5.00))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(10.00))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
	g.Expect(billingItem.OrgId).Should(gomega.Equal(int64(0)))
	g.Expect(billingItem.RepoId).Should(gomega.Equal(int64(0)))
}

func TestAdmin_CreateChargeWithOrgAndRepoId(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(2.0, "actions_windows_64_core", "actions", "Actions")
	_ = client.UpsertPricing(pricing)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	now := models.NewUsageTimeFromTime(time.Now()).Time

	_ = client.AdminGenerateUsage(&proto.GenerateUsageRequest{
		CustomerId: customerId,
		Sku:        pricing.GetSku(),
		OrgId:      1,
		RepoId:     2,
		Amount:     5.00,
	})

	client.ValidateQueue(1, models.WorkerTypeUsageIngestion)
	client.RunUsageIngestion(1)
	client.ValidateQueue(0, models.WorkerTypeUsageIngestion)

	client.RunDailyJob(1)

	u := client.GetUsageLineItemsGroupBy("", "", customerId, now, proto.BillingPeriod_Daily, proto.UsageGroupBy_GroupByOrgRepoProductSku)
	g.Expect(len(u.BillingItems)).Should(gomega.Equal(1), "a line item should be created")

	billingItem := u.BillingItems[0]
	g.Expect(billingItem.Quantity).Should(gomega.Equal(2.50))
	g.Expect(billingItem.BilledAmount).Should(gomega.Equal(5.00))
	g.Expect(billingItem.AppliedCostPerQuantity).Should(gomega.Equal(pricing.GetPrice()))
	g.Expect(billingItem.OrgId).Should(gomega.Equal(int64(1)))
	g.Expect(billingItem.RepoId).Should(gomega.Equal(int64(2)))
}

func TestAdmin_CannotSetBothValueTypes(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(2.0, "actions_windows_64_core", "actions", "Actions")
	_ = client.UpsertPricing(pricing)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	err := client.AdminGenerateUsage(&proto.GenerateUsageRequest{
		CustomerId: customerId,
		Sku:        pricing.GetSku(),
		OrgId:      1,
		RepoId:     2,
		Amount:     5.00,
		Quantity:   400.0,
	})

	g.Expect(err).Should(gomega.Equal(twirp.NewError(
		twirp.Internal,
		"Must set only one of Amount or Quantity",
	).WithMeta("cause", "*errors.fundamental")))
}

func Test_Customer_CanProceedWithUsage_With_ZeroDollar_Budget(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	pricing := client.EnsureSpecificPricingExists(2.0, "actions_linux", "actions", "Actions")
	_ = client.UpsertPricing(pricing)

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.HasPaymentMethod = true
	customerProto.HasZuoraSubscription = true
	customerId := customerProto.CustomerId
	_ = client.CreateCustomer(customerProto)

	usageDate := time.Now().UTC()
	usage := stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 50000, customerId, usageDate) // enough usage to exceed included discounts for the "enterprise" plan
	usages := []*hydroSchema.Usage{usage}

	canProceedWithUsage := client.CanProceedWithUsage(pricing, usage.Entity, usageDate)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true)) // usage allowed since budget is not set and we have included discounts

	targetType := proto.ResourceType_Enterprise
	budget := stubs.CreateBudgetWithLimitType(customerId, targetType, customerId, proto.PricingTargetType_SkuPricing, pricing.Sku, 0, proto.BudgetLimitType_PreventFurtherUsage)
	_ = client.UpsertBudget(budget)

	canProceedWithUsage = client.CanProceedWithUsage(pricing, usage.Entity, usageDate)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true)) // usage still allowed regardless of budget, because of the included discounts

	client.ProduceMeteredUsage(usages)
	client.RunUsageIngestion(len(usages))
	client.RunDiscountStateUpdateJob(len(usages))

	canProceedWithUsage = client.CanProceedWithUsage(pricing, usage.Entity, usageDate)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(false)) // usage is not allowed, because discounts are exhausted and budget is set to 0

	usageDate = usageDate.AddDate(0, 1, 0)
	usage = stubs.CreateUsage(uuid.NewString(), pricing.GetSku(), 4, customerId, usageDate)

	canProceedWithUsage = client.CanProceedWithUsage(pricing, usage.Entity, usageDate)
	g.Expect(canProceedWithUsage.CanProceed).To(gomega.Equal(true)) // usage allowed since it's a new month and discounts are reset
}

func Test_Customer_UpsertBudget_WillNotUpsertForTrial(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customer := &proto.Customer{
		CustomerId:       stubs.GetRandomId64AsString(),
		DiscountPlanName: "enterprise_trial",
	}

	_ = client.CreateCustomer(customer)

	amount := 99.9
	targetId := stubs.GetRandomId64AsString()
	targetType := proto.ResourceType_Enterprise
	budgetAlerting := stubs.CreateBudgetAlerting([]string{customer.CustomerId})

	budget := stubs.CreateBudgetWithAlerting(customer.CustomerId, targetType, targetId, proto.PricingTargetType_SkuPricing, "sku", amount, proto.BudgetLimitType_PreventFurtherUsage, budgetAlerting)

	err := client.UpsertBudgetError(budget)

	// expect response to be a permissiondenied error
	g.Expect(err).Should(gomega.Equal(
		twirp.NewError(
			twirp.PermissionDenied,
			"Customers on trial cannot create budgets",
		),
	))
}
