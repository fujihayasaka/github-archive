package stubs

import (
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/google/uuid"
)

func CreateCustomerWithTarget(billingTarget proto.BillingTarget) *proto.Customer {
	return &proto.Customer{
		CustomerId:         GetRandomId64AsString(),
		BillingTarget:      billingTarget,
		ZuoraAccountId:     GetRandomId64AsString(),
		ZuoraAccountNumber: GetRandomZuoraAccountNumber(),
		AzureAccountId:     uuid.NewString(),
		DiscountPlanName:   "enterprise",
	}
}

func CreateCustomerWithTargetAndAzureAccountId(billingTarget proto.BillingTarget, azureAccountId string) *proto.Customer {
	return &proto.Customer{
		CustomerId:         GetRandomId64AsString(),
		BillingTarget:      billingTarget,
		ZuoraAccountId:     GetRandomId64AsString(),
		ZuoraAccountNumber: GetRandomZuoraAccountNumber(),
		AzureAccountId:     azureAccountId,
		IsCostCenterProxy:  false,
		DiscountPlanName:   "enterprise",
	}
}

func CreateEnabledCustomerWithTargetAndAzureAccountId(billingTarget proto.BillingTarget, azureAccountId string) *proto.Customer {
	customer := CreateCustomerWithTargetAndAzureAccountId(billingTarget, azureAccountId)
	customer.EnabledProducts = []string{"actions", "git_lfs", "copilot", "ghec"}
	customer.HasPaymentMethod = true
	return customer
}

func CreateCustomerWithTargetAndZuoraAccountNumber(billingTarget proto.BillingTarget, zuoraAccountNumber string) *proto.Customer {
	return &proto.Customer{
		CustomerId:         GetRandomId64AsString(),
		BillingTarget:      billingTarget,
		ZuoraAccountNumber: zuoraAccountNumber,
		AzureAccountId:     uuid.NewString(),
		DiscountPlanName:   "enterprise",
	}
}

func CreateEnabledCustomerWithTargetAndZuoraAccountNumber(billingTarget proto.BillingTarget, zuoraAccountNumber string) *proto.Customer {
	customer := CreateCustomerWithTargetAndZuoraAccountNumber(billingTarget, zuoraAccountNumber)
	customer.EnabledProducts = []string{"actions", "git_lfs", "copilot", "ghec"}
	customer.HasPaymentMethod = true
	return customer
}

func CreateEnabledCustomerWithTarget(billingTarget proto.BillingTarget) *proto.Customer {
	customer := CreateCustomerWithTarget(billingTarget)
	customer.EnabledProducts = []string{"actions", "git_lfs", "copilot", "ghec"}
	customer.HasPaymentMethod = true
	return customer
}

func CreateEnabledCustomerWithId(customerId string, billingTarget proto.BillingTarget) *proto.Customer {
	customer := &proto.Customer{
		CustomerId:         customerId,
		BillingTarget:      billingTarget,
		ZuoraAccountId:     GetRandomId64AsString(),
		ZuoraAccountNumber: GetRandomZuoraAccountNumber(),
		AzureAccountId:     uuid.NewString(),
		DiscountPlanName:   "enterprise",
	}
	customer.EnabledProducts = []string{"actions", "git_lfs", "copilot", "ghec"}
	customer.HasPaymentMethod = true
	return customer
}
