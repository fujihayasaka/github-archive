package models

type EnterpriseInfo struct {
	EnabledProducts      []string
	EnterpriseCustomerId string
	CostCenterUUID       string
	ZuoraAccountNumber   string
	//TODO: Change AzureAccountId to AzureSubscriptionId
	// This value is actually maps to a customer's azure subscription id, in dotcom speak this is Customer.zuora_subscription_id
	// Issue: https://github.com/github/gitcoin/issues/11260
	AzureAccountId         string
	DiscountPlanName       string
	BillingTarget          BillingTarget
	BillForPublicRepoUsage bool
	HasPaymentMethod       bool
	HasZuoraSubscription   bool
	IsBillingLocked        bool
	TradeScreening         *TradeScreening
}

func (ei *EnterpriseInfo) IsProductEnabled(product string) bool {
	for _, p := range ei.EnabledProducts {
		if p == product {
			return true
		}
	}

	return false
}
