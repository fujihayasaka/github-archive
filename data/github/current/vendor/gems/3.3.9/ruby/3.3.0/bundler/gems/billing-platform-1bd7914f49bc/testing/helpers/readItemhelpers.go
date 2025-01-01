package helpers

import (
	"embed"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/models"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

//go:embed fixtures
var fixtures embed.FS

// ReadEmbeddedFile reads the content of an embedded file
func ReadEmbeddedFile(fileName string) ([]byte, error) {
	f, err := fixtures.ReadFile(fileName)
	if err != nil {
		return f, fmt.Errorf("error reading fixture file %s: %w", fileName, err)
	}
	return f, nil
}

// MockAzureItemResponse mocks an Azure ItemResponse for the given model
// Use this when you want to mock a ReadItem for a specific model that you expect to be returned
// when making a db call
// e.g to Mock and ItemResponse for a Customer
// call MockAzureItemResponse(t, &models.Customer{}) or MockAzureItemResponse[models.Customer](t, &models.Customer{})
func MockAzureItemResponse[T any](t *testing.T, item *T) azcosmos.ItemResponse {
	itemBytes, jErr := json.Marshal(item)
	assert.NoError(t, jErr)
	return azcosmos.ItemResponse{
		Value: itemBytes,
		Response: azcosmos.Response{
			RawResponse: &http.Response{
				Status:     "200 OK",
				StatusCode: 200,
			},
			RequestCharge: 15.0,
			ActivityID:    uuid.NewString(),
		},
	}
}

// MockAzureItemResponseWith404 returns nil item and a parsable 404 azure response error
func MockAzureItemResponseWith404(t *testing.T) azcosmos.ItemResponse {
	return azcosmos.ItemResponse{
		Value: nil,
		Response: azcosmos.Response{
			RawResponse: &http.Response{
				Status:     "404 Not Found",
				StatusCode: 404,
			},
			RequestCharge: 3.0,
			ActivityID:    uuid.NewString(),
		},
	}
}

// StaticEnterpriseInfo mocks an EnterpriseInfo ItemResponse with a few hardcoded values
func StaticEnterpriseInfo(t *testing.T) azcosmos.ItemResponse {
	enterpriseInfo := &models.EnterpriseInfo{
		BillForPublicRepoUsage: false,
		DiscountPlanName:       "enterprise",
	}
	return MockAzureItemResponse(t, enterpriseInfo)
}

// StaticTestCustomerReadItemResponse mocks a Customer ItemResponse with a few hardcoded values
// Key is hardcoded as is CostCenterDetail
func StaticTestCustomerReadItemResponse(t *testing.T) azcosmos.ItemResponse {
	customer := &models.Customer{
		Key: &models.Key{
			Id:           "123",
			PartitionKey: "123:sku1:events",
		},
		CostCenterDetail: &models.CostCenterDetail{
			EnterpriseCustomerId: "456",
			CostCenterUUID:       uuid.New().String(),
		},
	}
	return MockAzureItemResponse(t, customer)
}

// StaticTestCustomerReadItemResponse mocks a Customer ItemResponse with enabled products with a few hardcoded values
// Key is hardcoded as is CostCenterDetail
func StaticTestCustomerWithEnabledProductsReadItemResponse(t *testing.T) azcosmos.ItemResponse {
	customer := &models.Customer{
		Key: &models.Key{
			Id:           "123",
			PartitionKey: "123:sku1:events",
		},
		CostCenterDetail: &models.CostCenterDetail{
			EnterpriseCustomerId: "456",
			CostCenterUUID:       uuid.New().String(),
		},
		EnabledProducts: []string{"ghec"},
		BillingTarget:   models.Zuora,
	}
	return MockAzureItemResponse(t, customer)
}

func TestCustomerReadItemResponse(t *testing.T, customerId int64, product string) azcosmos.ItemResponse {
	customer := &models.Customer{
		Key: &models.Key{
			Id:           fmt.Sprintf("%d", customerId),
			PartitionKey: fmt.Sprintf("customer:%d", customerId),
		},
		CostCenterDetail: &models.CostCenterDetail{
			IsCostCenterProxy: false,
		},
		EnabledProducts:  []string{product},
		DiscountPlanName: "enterprise",
	}

	return MockAzureItemResponse(t, customer)
}

// StaticTestCustomerReadZeroResponse mocks a Customer ItemResponse with a few hardcoded values
// Customer ID is set to 0
func StaticTestCustomerReadZeroResponse(t *testing.T) azcosmos.ItemResponse {
	customer := &models.Customer{
		Key: &models.Key{
			Id:           "123",
			PartitionKey: "123:sku1:events",
		},
		CostCenterDetail: &models.CostCenterDetail{
			EnterpriseCustomerId: "0",
			CostCenterUUID:       uuid.New().String(),
		},
	}
	return MockAzureItemResponse(t, customer)
}

// StaticTestCustomerReadItemWithAzureBillingResponse mocks a Customer ItemResponse with a few hardcoded values
// Returns a Customer with Azure BillingTarget
func StaticTestCustomerReadItemWithAzureBillingResponse(t *testing.T) azcosmos.ItemResponse {
	customer := &models.Customer{
		Key: &models.Key{
			Id:           "123",
			PartitionKey: "123:sku1:events",
		},
		CostCenterDetail: &models.CostCenterDetail{
			EnterpriseCustomerId: "456",
			CostCenterUUID:       uuid.New().String(),
		},
		BillingTarget: models.Azure,
	}
	return MockAzureItemResponse(t, customer)
}

// StaticTestPricing mocks a Pricing ItemResponse with a few hardcoded values
// mainly SKU and price are hardcoded
func StaticTestPricing(t *testing.T) azcosmos.ItemResponse {
	pricing := &models.Pricing{
		Sku:   "sku1",
		Price: 5.0,
	}
	return MockAzureItemResponse(t, pricing)
}

// TestPricingForHighWatermark mocks a Pricing ItemResponse with a few hardcoded values
// mainly SKU and price and meterType are hardcoded
func TestPricingForHighWatermark(t *testing.T) azcosmos.ItemResponse {
	pricing := &models.Pricing{
		Sku:       "sku1",
		Price:     5.0,
		MeterType: models.PricingMeterDailyUnitCharge,
	}
	return MockAzureItemResponse(t, pricing)
}

func TestCustomPricing(t *testing.T, product, sku string, price float64, effectiveAt int64) azcosmos.ItemResponse {
	pricing := &models.Pricing{
		Product:     product,
		Sku:         sku,
		Price:       models.ToWholeAmount[int64](price),
		EffectiveAt: effectiveAt,
	}
	return MockAzureItemResponse(t, pricing)
}

// StaticTestCostCenterCustomerIdZero mocks a CostCenter ItemResponse with a few hardcoded values
// Key is hardcoded as is Customer with no Billing target is set
func StaticTestCostCenterCustomerIdZero(t *testing.T) azcosmos.ItemResponse {
	cc := &models.CostCenter{
		CostCenterKey: &models.CostCenterKey{
			UUID: "0",
			Key: &models.Key{
				Id:           "123",
				PartitionKey: "123:sku1:events",
			},
			Customer: &models.Customer{
				CostCenterDetail: &models.CostCenterDetail{
					EnterpriseCustomerId: "0",
					CostCenterUUID:       uuid.New().String(),
				},
			},
		},
	}
	return MockAzureItemResponse(t, cc)
}

// StaticTestCostCenter mocks a CostCenter ItemResponse with a few hardcoded values
// Key is hardcoded as is Customer with no Billing target is set
func StaticTestCostCenter(t *testing.T) azcosmos.ItemResponse {
	cc := &models.CostCenter{
		CostCenterKey: &models.CostCenterKey{
			UUID: uuid.New().String(),
			Key: &models.Key{
				Id:           "123",
				PartitionKey: "123:sku1:events",
			},
			Customer: &models.Customer{
				CostCenterDetail: &models.CostCenterDetail{
					EnterpriseCustomerId: "456",
					CostCenterUUID:       uuid.New().String(),
				},
			},
		},
	}
	return MockAzureItemResponse(t, cc)
}

func TestDiscountStateReadItemResponse(t *testing.T, customerId int64, discountAmount float64, uuid string) (*models.DiscountState, azcosmos.ItemResponse) {
	discountState := &models.DiscountState{
		Key: &models.Key{
			Id:           fmt.Sprintf("customer:%d:budgets", customerId),
			PartitionKey: "discountState",
		},
		IsFullyApplied: false,
		CurrentAmount:  0,
		TargetAmount:   models.ToWholeAmount[int64](discountAmount),
		Uuid:           uuid,
	}

	return discountState, MockAzureItemResponse(t, discountState)
}

func TestBudgetReadItemResponse(t *testing.T, customerId int64, product string, targetId int64, targetType models.ResourceType, targetAmount float64, uuid string) (*models.Budget, azcosmos.ItemResponse) {
	budget := &models.Budget{
		BudgetKey: &models.BudgetKey{
			Key: &models.Key{
				Id:           fmt.Sprintf("customer:%d:budgets:customer:%d", customerId, customerId),
				PartitionKey: fmt.Sprintf("customer:%d:budgets", customerId),
			},
			CustomerId:        fmt.Sprintf("%d", customerId),
			TargetId:          fmt.Sprintf("%d", targetId),
			TargetType:        targetType,
			PricingTargetType: models.ProductPricing,
			PricingTargetId:   product,
		},
		TargetAmount:   models.ToWholeAmount[uint64](targetAmount),
		Uuid:           uuid,
		BudgetAlerting: &models.BudgetAlerting{},
	}

	return budget, MockAzureItemResponse(t, budget)
}

func TestBudgetStateReadItemResponse(t *testing.T, customerId int64, usageAt *models.UsageTime, targetAmount float64) (*models.BudgetState, azcosmos.ItemResponse) {
	year := int64(usageAt.Year())
	month := int64(usageAt.Month())
	budgetStatePartitionKey := fmt.Sprintf("customer:%d:budgets:customer:%d:%d:%d", customerId, customerId, year, month)

	budgetState := &models.BudgetState{
		Key: &models.Key{
			Id:           "budgetState",
			PartitionKey: budgetStatePartitionKey,
		},
		CurrentAmount: 0,
		TargetAmount:  models.ToWholeAmount[uint64](targetAmount),
		IsFullyFunded: false,
	}

	return budgetState, MockAzureItemResponse(t, budgetState)
}

// StaticTestBudget mocks a Budget ItemResponse given an input budget
func StaticTestBudget(t *testing.T, budget *models.Budget) azcosmos.ItemResponse {
	return MockAzureItemResponse(t, budget)
}

// StaticTestBudget mocks a BudgetState ItemResponse given an input budget state
func StaticTestBudgetState(t *testing.T, budgetState *models.BudgetState) azcosmos.ItemResponse {
	return MockAzureItemResponse(t, budgetState)
}

func MockBudgetsItemResponseFromFixture[T any](t *testing.T, fixture string) azcosmos.ItemResponse {
	var item *T
	err := ReadFixture(fixture, &item)
	assert.NoError(t, err)

	return MockAzureItemResponse(t, &item)

}

// readFixture parses a JSON fixture into the given interface
func ReadFixture[T any](fixture string, out *T) error {
	// json read file
	f, err := ReadEmbeddedFile(fixture)
	if err != nil {
		return err
	}
	// unmarshal
	err = json.Unmarshal(f, out)
	if err != nil {
		return fmt.Errorf("error unmarshalling fixture file %s: %w", fixture, err)
	}
	return nil
}
