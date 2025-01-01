package models

import (
	"encoding/json"
	"testing"

	"github.com/onsi/gomega"
)

func Test_GetPartitionKey(t *testing.T) {

	g := gomega.NewGomegaWithT(t)

	costCenterCustomer := &Customer{
		CostCenterDetail: &CostCenterDetail{
			CostCenterUUID:       "456",
			IsCostCenterProxy:    true,
			EnterpriseCustomerId: "123",
		},
		BillingTarget:  NoBillingTarget,
		AzureAccountId: "789",
		ZuoraAccountId: "101112",
	}

	g.Expect(costCenterCustomer.GetCustomerId()).To(gomega.Equal("456"))
	g.Expect(costCenterCustomer.ToPartitionKey()).To(gomega.Equal("customer:456"))

	customer := &Customer{
		CostCenterDetail: &CostCenterDetail{
			CostCenterUUID:       "456",
			IsCostCenterProxy:    false,
			EnterpriseCustomerId: "123",
		},
		BillingTarget:  NoBillingTarget,
		AzureAccountId: "789",
		ZuoraAccountId: "101112",
	}

	g.Expect(customer.GetCustomerId()).To(gomega.Equal("123"))
	g.Expect(customer.ToPartitionKey()).To(gomega.Equal("customer:123"))
	g.Expect(customer.ToBudgetsPartitionKey()).To(gomega.Equal("customer:123:budgets"))
	g.Expect(customer.ToCostCentersPartitionKey()).To(gomega.Equal("customer:123:costCenters"))
	g.Expect(customer.ToDiscountsPartitionKey()).To(gomega.Equal("customer:123:discounts"))
	g.Expect(customer.ToInvoicePartitionKey()).To(gomega.Equal("customer:123:invoices"))
}

func Test_GetCustomer_Serilazer(t *testing.T) {

	g := gomega.NewGomegaWithT(t)

	customer := &Customer{
		CostCenterDetail: &CostCenterDetail{
			CostCenterUUID:       "456",
			IsCostCenterProxy:    true,
			EnterpriseCustomerId: "123",
		},
		BillingTarget:  NoBillingTarget,
		AzureAccountId: "789",
		ZuoraAccountId: "101112",
	}

	bytes, err := json.Marshal(customer)
	g.Expect(err).To(gomega.BeNil())

	var customer2 Customer
	err = json.Unmarshal(bytes, &customer2)
	g.Expect(err).To(gomega.BeNil())

	g.Expect(*customer).To(gomega.Equal(customer2))
}

func Test_IsOnTrial(t *testing.T) {

	g := gomega.NewGomegaWithT(t)

	// Test case 1: Customer is on trial
	customer1 := &Customer{
		BillingTarget:   NoBillingTarget,
		AzureAccountId:  "789",
		ZuoraAccountId:  "101112",
		IsBillingLocked: false,
		TradeScreening: &TradeScreening{
			HasAnyTradeRestrictions: false,
		},
		DiscountPlanName: "enterprise_trial",
	}
	g.Expect(customer1.IsOnTrial()).To(gomega.BeTrue())

	// Test case 2: Customer is not on trial
	customer2 := &Customer{
		BillingTarget:   NoBillingTarget,
		AzureAccountId:  "789",
		ZuoraAccountId:  "101112",
		IsBillingLocked: false,
		TradeScreening: &TradeScreening{
			HasAnyTradeRestrictions: false,
		},
		DiscountPlanName: "enterprise",
	}
	g.Expect(customer2.IsOnTrial()).To(gomega.BeFalse())
}
