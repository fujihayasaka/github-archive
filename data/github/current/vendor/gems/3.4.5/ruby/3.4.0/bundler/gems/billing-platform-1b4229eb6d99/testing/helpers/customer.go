package helpers

import (
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/models"
	"github.com/google/uuid"
)

type TestCustomerOptions func(*models.Customer)

// MakeTestCustomer creates a test customer with some sane defaults
// with the given customerId, product, discountPlanName and costCenterDetail
// if costCenterDetail is nil, it will be created with IsCostCenterProxy set to false
func MakeTestCustomer(t *testing.T, options ...TestCustomerOptions) azcosmos.ItemResponse {
	c := &models.Customer{
		Key: &models.Key{
			Id:           "1",
			PartitionKey: "customer:1",
		},
		CostCenterDetail: &models.CostCenterDetail{
			IsCostCenterProxy: false,
			CostCenterUUID:    uuid.New().String(),
		},
		EnabledProducts:  []string{"actions"},
		DiscountPlanName: "enterprise",
		BillingTarget:    models.Azure,
	}

	for _, option := range options {
		option(c)
	}

	return MockAzureItemResponse(t, c)
}

func MakeTestCustomerWithoutPaymentMethod(t *testing.T, options ...TestCustomerOptions) azcosmos.ItemResponse {
	c := &models.Customer{
		Key: &models.Key{
			Id:           "1",
			PartitionKey: "customer:1",
		},
		CostCenterDetail: &models.CostCenterDetail{
			IsCostCenterProxy: false,
			CostCenterUUID:    uuid.New().String(),
		},
		EnabledProducts:  []string{"actions"},
		DiscountPlanName: "enterprise",
		BillingTarget:    models.Zuora,
		HasPaymentMethod: false,
	}

	for _, option := range options {
		option(c)
	}

	return MockAzureItemResponse(t, c)
}

func WithCostCenterProxy(isCostCenterProxy bool) TestCustomerOptions {
	return func(c *models.Customer) {
		c.CostCenterDetail = &models.CostCenterDetail{
			IsCostCenterProxy: isCostCenterProxy,
		}
	}
}

func WithCostCenterUUID(uuid string) TestCustomerOptions {
	return func(c *models.Customer) {
		c.CostCenterDetail = &models.CostCenterDetail{
			CostCenterUUID: uuid,
		}
	}
}

func WithEnabledProducts(products ...string) TestCustomerOptions {
	return func(c *models.Customer) {
		c.EnabledProducts = products
	}
}

func WithDiscountPlanName(discountPlanName string) TestCustomerOptions {
	return func(c *models.Customer) {
		c.DiscountPlanName = discountPlanName
	}
}

func WithBillingTarget(billingTarget models.BillingTarget) TestCustomerOptions {
	return func(c *models.Customer) {
		c.BillingTarget = billingTarget
	}
}

func WithKey(id, partitionKey string) TestCustomerOptions {
	return func(c *models.Customer) {
		c.Key = &models.Key{
			Id:           id,
			PartitionKey: partitionKey,
		}
	}
}

func WithIsBillingLocked(locked bool) TestCustomerOptions {
	return func(c *models.Customer) {
		c.IsBillingLocked = locked
	}
}

func WithTradeScreening(tradeScreening *models.TradeScreening) TestCustomerOptions {
	return func(c *models.Customer) {
		c.TradeScreening = tradeScreening
	}
}

func WithAzureAccountId(azureAccountId string) TestCustomerOptions {
	return func(c *models.Customer) {
		c.AzureAccountId = azureAccountId
	}
}
