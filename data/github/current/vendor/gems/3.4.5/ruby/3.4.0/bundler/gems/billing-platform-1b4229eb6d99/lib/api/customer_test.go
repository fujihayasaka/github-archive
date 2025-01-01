package api

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/feature-management-client-go/vexi/adapter/fake"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats/mocks"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel/trace"
)

type DiscountTestData struct {
	name         string
	targetAmount float64
	percentage   float64
	startDate    int64
	endDate      int64
	err          string
}

func Test_Discount_Validations(t *testing.T) {
	t.Parallel()

	yesterday := time.Now().AddDate(0, 0, -1).Unix()
	tomorrow := time.Now().AddDate(0, 0, 1).Unix()
	nextYear := time.Now().AddDate(1, 0, 0).Unix()

	tests := []DiscountTestData{
		{
			name:         "startDate greater than endDate",
			startDate:    nextYear,
			endDate:      tomorrow,
			targetAmount: 100,
			err:          "twirp error invalid_argument: startDate must be less than or equal to endDate",
		},
		{
			name:         "endDate in the past",
			startDate:    yesterday,
			endDate:      yesterday,
			targetAmount: 100,
			err:          "twirp error invalid_argument: endDate must be in greater than or equal to today's date",
		},
		{
			name:         "targetAmount only",
			targetAmount: 100.05,
			err:          "",
		},
		{
			name:         "percentage only",
			targetAmount: 0,
			percentage:   10.5,
			err:          "",
		},
		{
			name:         "both targetAmount and percentage",
			targetAmount: 100.05,
			percentage:   10,
			err:          "",
		},
		{
			name:         "negative percentage and non-zero targetAmount",
			targetAmount: 10,
			percentage:   -10,
			err:          "",
		},
		{
			name:         "negative percentage and zero targetAmount",
			targetAmount: 0,
			percentage:   -10,
			err:          "twirp error invalid_argument: percentage must be between 0 and 100",
		},
		{
			name:         "negative targetAmount and positive percentage",
			targetAmount: -10,
			percentage:   10,
			err:          "twirp error invalid_argument: targetAmount must be > 0",
		},
		{
			name:         "negative targetAmount and zero percentage",
			targetAmount: -10,
			percentage:   0,
			err:          "twirp error invalid_argument: targetAmount must be > 0",
		},
		{
			name:         "zero values",
			targetAmount: 0,
			percentage:   0,
			err:          "twirp error invalid_argument: percentage|targetAmount either percentage or targetAmount must be > 0",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			testDiscount(t, tt)
		})
	}
}

func testDiscount(t *testing.T, tt DiscountTestData) {
	_, telem, statter, logger, mockDb := helpers.SetupMocks(t)
	customerAPI, _, _ := setupCustomerAPI(t, logger, nil, mockDb, statter, telem.Tracer.Tracer, nil)

	targets := []*proto.DiscountTarget{
		{
			Id:   "actions_linux",
			Type: proto.DiscountTargetType_SkuDiscount,
		},
	}

	yesterday := time.Now().AddDate(0, 0, -1).Unix()
	nextYear := time.Now().AddDate(1, 0, 0).Unix()

	var startDate, endDate int64

	if tt.startDate == 0 {
		startDate = yesterday
	} else {
		startDate = tt.startDate
	}

	if tt.endDate == 0 {
		endDate = nextYear
	} else {
		endDate = tt.endDate
	}

	discount := &proto.Discount{
		CustomerId:   "123",
		Targets:      targets,
		TargetAmount: tt.targetAmount,
		Percentage:   tt.percentage,
		StartDate:    startDate,
		EndDate:      endDate,
	}

	request := &proto.CreateDiscountRequest{
		Discount: discount,
	}

	pegomock.When(
		mockDb.Batch(
			pegomock.Any[context.Context](),
			pegomock.Any[models.ItemKey](),
			pegomock.Any[*interfaces.QueryOptions](),
			pegomock.Any[func(*azcosmos.TransactionalBatch) error](),
		),
	).ThenReturn(true, nil, nil)

	discountResponse, err := customerAPI.CreateDiscount(context.Background(), request)
	if tt.err == "" {
		assert.NotNil(t, discountResponse.Uuid)
	} else {
		assert.NotNil(t, err)
		assert.Equal(t, err.Error(), tt.err)
	}
}

func Test_CanProceedWithUsagePublicRepoStandardRunner(t *testing.T) {
	pegomock.RegisterMockTestingT(t)
	c, telem, stats, logger, db := helpers.SetupMocks(t)
	cfg := &config.Config{
		Environment: "test",
	}
	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(c)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
	pegomock.When(db.GetStatter()).ThenReturn(stats)

	repoId := 3
	sku := "actions_linux"

	pegomock.When(
		c.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[string](),
			pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.StaticTestCustomerReadItemWithAzureBillingResponse(t), nil,
		)

	pegomock.When(
		c.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Eq(azcosmos.NewPartitionKeyString(fmt.Sprintf("repo:%v", repoId))),
			pegomock.Eq(fmt.Sprintf("%v", repoId)),
			pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MockAzureItemResponse(t, &models.Repo{
				RepoKey: &models.RepoKey{
					RepoId: int64(repoId),
				},
				IsPublic: true,
			}), nil,
		)

	customerAPI, mockPricingEngine, _ := setupCustomerAPI(t, logger, cfg, db, stats, telem.Tracer.Tracer, nil)

	pegomock.When(mockPricingEngine.GetCurrentPricing(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.PricingSelectionData](),
	)).ThenReturn(&models.Pricing{
		Sku:                sku,
		FreeForPublicRepos: true,
	})

	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     sku,
			Product: "actions",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     int64(repoId),
			},
			RepositoryVisibility: proto.RepositoryVisibility_PUBLIC,
		},
	}

	mockPricing := getMockNonFreePricing(t, sku)

	// Mock GetPricing response
	pegomock.When(mockPricingEngine.GetPricing(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(sku),
		pegomock.Eq(false),
	)).ThenReturn(mockPricing, nil)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)
	assert.NoError(t, err)

	// Assert
	assert.True(t, response.CanProceed)
}
func Test_CanProceedWithUsageWhenBillingLocked(t *testing.T) {
	// Setup
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	sku := "actions_linux"
	r := helpers.MakeTestCustomer(t, helpers.WithIsBillingLocked(true))

	pegomock.When(
		c.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[string](),
			pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(r, nil)

	customerAPI, _, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)
	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     sku,
			Product: "actions",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     199,
			},
		},
	}

	// Test
	response, _ := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.False(t, response.CanProceed)
}

func Test_CanProceedWithUsage_NilUsageKey(t *testing.T) {
	_, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, _, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)

	request := &proto.CanProceedWithUsageRequest{}

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, response)
	assert.ErrorContains(t, err, "twirp error invalid_argument: usageKey is required")
}

func Test_CanProceedWithUsage_NilUsageKeyEntityDetail(t *testing.T) {
	_, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, _, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)
	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     "actions_linux",
			Product: "actions",
		},
	}

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, response)
	assert.ErrorContains(t, err, "twirp error invalid_argument: entityDetail is required")
}

func Test_CanProceedWithUsage_ErrorOnGettingCustomer(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MockAzureItemResponseWith404(t), errors.New("some error"))

	customerAPI, _, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)
	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     "actions_linux",
			Product: "actions",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     199,
			},
		},
	}

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, response)
	assert.ErrorContains(t, err, "twirp error internal: some error")
}

func Test_CanProceedWithUsage_NilCustomer(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, _, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)
	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     "actions_linux",
			Product: "actions",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     199,
			},
		},
	}

	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MockAzureItemResponseWith404(t), &azcore.ResponseError{StatusCode: http.StatusNotFound})

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, response)
	assert.ErrorContains(t, err, "twirp error not_found: Customer with id 1 not found")
}

func Test_CanProceedWithUsage_ProductNotEnabled(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, _, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)

	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     "copilot",
			Product: "copilot",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     199,
			},
		},
	}

	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MakeTestCustomer(t,
				helpers.WithDiscountPlanName("enterprise_trial"),
				helpers.WithAzureAccountId("deadbeef"),
				helpers.WithEnabledProducts("actions"),
			),

			nil,
		)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.False(t, response.CanProceed)
	assert.Equal(t, response.Status, proto.CanProceedWithUsageStatus_ProductNotEnabled)
}

func Test_CanProceedWithUsage_TradeRestrictions(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, _, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)

	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     "copilot",
			Product: "copilot",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     199,
			},
		},
	}

	tests := []struct {
		name          string
		ts            *models.TradeScreening
		expectedError proto.CanProceedWithUsageStatus
	}{
		{
			name: "full trade restrictions",
			ts: &models.TradeScreening{
				HasAnyTradeRestrictions:  false,
				HasFullTradeRestrictions: true,
			},
			expectedError: proto.CanProceedWithUsageStatus_FullTradeRestrictionsApplied,
		},
		{
			name: "any trade restrictions",
			ts: &models.TradeScreening{
				HasAnyTradeRestrictions:  true,
				HasFullTradeRestrictions: false,
			},
			expectedError: proto.CanProceedWithUsageStatus_AnyTradeRestrictionsApplied,
		},
		{
			name: "commercial interaction restrictions",
			ts: &models.TradeScreening{
				HasAnyTradeRestrictions:                       false,
				HasFullTradeRestrictions:                      false,
				FeaturesWithCommercialInteractionRestrictions: []string{"copilot"},
			},
			expectedError: proto.CanProceedWithUsageStatus_CommercialInteractionRestrictionApplied,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pegomock.When(c.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Any[azcosmos.PartitionKey](),
				pegomock.Any[string](),
				pegomock.Any[*azcosmos.ItemOptions]())).
				ThenReturn(helpers.MakeTestCustomer(t,
					helpers.WithTradeScreening(tt.ts),
					helpers.WithEnabledProducts("copilot")),
					nil)

			response, err := customerAPI.CanProceedWithUsage(context.Background(), request)
			assert.Nil(t, err)
			assert.False(t, response.CanProceed)
			assert.Equal(t, response.Status, tt.expectedError)
		})
	}
}

func Test_CanProceedWithUsage_PlanDiscounts_Trial(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, mockPricingEngine, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)

	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     "copilot",
			Product: "copilot",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     199,
			},
		},
	}

	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MakeTestCustomer(t,
				helpers.WithDiscountPlanName("enterprise_trial"),
				helpers.WithAzureAccountId("deadbeef"),
				helpers.WithEnabledProducts("copilot"),
			),

			nil,
		)

	sku := "copilot"
	mockPricing := getMockNonFreePricing(t, sku)

	// Mock GetPricing response
	pegomock.When(mockPricingEngine.GetPricing(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(sku),
		pegomock.Eq(false),
	)).ThenReturn(mockPricing, nil)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.False(t, response.CanProceed)
	assert.Equal(t, response.Status, proto.CanProceedWithUsageStatus_OnTrial)
}

func Test_CanProceedWithUsage_PlanDiscounts_NotBillable(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, mockPricingEngine, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)
	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     "copilot",
			Product: "copilot",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     199,
			},
		},
	}

	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MakeTestCustomer(t, helpers.WithEnabledProducts("copilot")), nil)

	sku := "copilot"
	mockPricing := getMockNonFreePricing(t, sku)

	// Mock GetPricing response
	pegomock.When(mockPricingEngine.GetPricing(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(sku),
		pegomock.Eq(false),
	)).ThenReturn(mockPricing, nil)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.False(t, response.CanProceed)
	assert.Equal(t, response.Status, proto.CanProceedWithUsageStatus_NotBillable)
}

func Test_CanProceedWithUsage_PlanDiscounts_noFullyFundedBudgets(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, mockPricingEngine, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)
	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     "copilot",
			Product: "copilot",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     199,
			},
		},
	}

	// mock customer response
	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1")),
		pegomock.Eq("customer"), // id
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MakeTestCustomer(t, helpers.WithAzureAccountId("testAzureAccountID"), helpers.WithEnabledProducts("actions", "copilot")), nil)

	// mock cost center response
	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1:costCenters")),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MockAzureItemResponse(t, &models.CostCenter{
			CostCenterKey: &models.CostCenterKey{
				Key: &models.Key{
					Id:           "customer:1:costCenters:4",
					PartitionKey: "customer:1:costCenters",
				},
			},
		}), nil)

	// mock budget state response
	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		helpers.Contains(azcosmos.NewPartitionKeyString("customer:1:budgets:repository:199:product:copilot")),
		pegomock.Eq("budgetState"),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MockAzureItemResponse(t, &models.BudgetState{
			TargetAmount: 200,
		}), nil)

	var budgets []*models.Budget

	budgets = append(budgets, &models.Budget{
		BudgetKey: &models.BudgetKey{
			Key: &models.Key{
				Id:           "customer:1:budgets:repository:199:product:copilot",
				PartitionKey: "customer:1:budgets",
			},
			TargetType: models.Repository,
			TargetId:   "199",
		},
		TargetAmount: 100,
	})

	pager := helpers.MakePagerWithData(t, budgets)

	pegomock.When(
		c.NewQueryItemsPager(
			pegomock.Eq("SELECT * FROM c"),
			pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1:budgets")),
			pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	sku := "copilot"
	mockPricing := getMockNonFreePricing(t, sku)

	// Mock GetPricing response
	pegomock.When(mockPricingEngine.GetPricing(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(sku),
		pegomock.Eq(false),
	)).ThenReturn(mockPricing, nil)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.True(t, response.CanProceed)
	assert.Equal(t, proto.CanProceedWithUsageStatus_UsageAllowed, response.Status)
	// called ReadItem 4 times
	// 1 call to get the customer, 2 calls for cost center lookups, 1 call for budget state
	c.VerifyWasCalled(pegomock.Times(4)).ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions](),
	)
}

func Test_CanProceedWithUsage_PlanDiscounts_IsFullyFundedBudgetsWithoutHardLimits(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, mockPricingEngine, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)
	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     "copilot",
			Product: "copilot",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     199,
			},
		},
	}

	// mock customer response
	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1")),
		pegomock.Eq("customer"), // id
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MakeTestCustomer(t, helpers.WithAzureAccountId("testAzureAccountID"), helpers.WithEnabledProducts("actions", "copilot")), nil)

	// mock cost center response
	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1:costCenters")),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MockAzureItemResponse(t, &models.CostCenter{
			CostCenterKey: &models.CostCenterKey{
				Key: &models.Key{
					Id:           "customer:1:costCenters:4",
					PartitionKey: "customer:1:costCenters",
				},
			},
		}), nil)

	// mock budget state response
	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		helpers.Contains(azcosmos.NewPartitionKeyString("customer:1:budgets:repository:199:product:copilot")),
		pegomock.Eq("budgetState"),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MockAzureItemResponse(t, &models.BudgetState{
				CurrentAmount: 200, // To simulate fully funded budget
				TargetAmount:  200,
				IsFullyFunded: true, // This is only ever set during usage processing
			}), nil)

	var budgets []*models.Budget

	budgets = append(budgets, &models.Budget{
		BudgetKey: &models.BudgetKey{
			Key: &models.Key{
				Id:           "customer:1:budgets:repository:199:product:copilot",
				PartitionKey: "customer:1:budgets",
			},
			TargetType: models.Repository,
			TargetId:   "199",
		},
		TargetAmount: 200,
	})

	pager := helpers.MakePagerWithData(t, budgets)

	pegomock.When(
		c.NewQueryItemsPager(
			pegomock.Eq("SELECT * FROM c"),
			pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1:budgets")),
			pegomock.Any[*azcosmos.QueryOptions]())).
		ThenReturn(pager)

	sku := "copilot"
	mockPricing := getMockNonFreePricing(t, sku)

	// Mock GetPricing response
	pegomock.When(mockPricingEngine.GetPricing(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(sku),
		pegomock.Eq(false),
	)).ThenReturn(mockPricing, nil)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.True(t, response.CanProceed)
	assert.Equal(t, proto.CanProceedWithUsageStatus_UsageAllowed, response.Status)
	assert.Equal(t, 1, len(response.ApplicableBudgets))
	actualCurrentAmount := response.ApplicableBudgets[0].GetBudgetState().GetCurrentAmount()
	assert.Equal(t, float64(200)/models.ToNanoCents, actualCurrentAmount)
	// called ReadItem 4 times
	// 1 call to get the customer, 2 calls for cost center lookups, 1 call for budget state
	c.VerifyWasCalled(pegomock.Times(4)).ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions](),
	)
}

func Test_CanProceedWithUsage_PlanDiscounts_IsFullyFundedBudgetsHardLimits(t *testing.T) {
	mockContainer, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, mockPricingEngine, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)
	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     "copilot",
			Product: "copilot",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     199,
			},
		},
	}

	// mock customer response
	pegomock.When(mockContainer.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1")),
		pegomock.Eq("customer"), // id
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MakeTestCustomer(t, helpers.WithAzureAccountId("testAzureAccountID"), helpers.WithEnabledProducts("actions", "copilot")), nil)

	// mock cost center response
	pegomock.When(mockContainer.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1:costCenters")),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MockAzureItemResponse(t, &models.CostCenter{
			CostCenterKey: &models.CostCenterKey{
				Key: &models.Key{
					Id:           "customer:1:costCenters:4",
					PartitionKey: "customer:1:costCenters",
				},
			},
		}), nil)

	// mock budget state response
	pegomock.When(mockContainer.ReadItem(
		pegomock.Any[context.Context](),
		helpers.Contains(azcosmos.NewPartitionKeyString("customer:1:budgets:repository:199:product:copilot")),
		pegomock.Eq("budgetState"),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MockAzureItemResponse(t, &models.BudgetState{
				CurrentAmount: 200, // To simulate fully funded budget
				TargetAmount:  200,
				IsFullyFunded: true, // This is only ever set during usage processing
			}), nil)

	var budgets []*models.Budget

	budgets = append(budgets, &models.Budget{
		BudgetKey: &models.BudgetKey{
			Key: &models.Key{
				Id:           "customer:1:budgets:repository:199:product:copilot",
				PartitionKey: "customer:1:budgets",
			},
			TargetType: models.Repository,
			TargetId:   "199",
		},
		TargetAmount:    200,
		BudgetLimitType: models.StopActiveUsage,
	})

	pager := helpers.MakePagerWithData(t, budgets)

	pegomock.When(
		mockContainer.NewQueryItemsPager(
			pegomock.Eq("SELECT * FROM c"),
			pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1:budgets")),
			pegomock.Any[*azcosmos.QueryOptions]())).
		ThenReturn(pager)

	sku := "copilot"
	mockPricing := getMockNonFreePricing(t, sku)

	// Mock GetPricing response
	pegomock.When(mockPricingEngine.GetPricing(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(sku),
		pegomock.Eq(false),
	)).ThenReturn(mockPricing, nil)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.False(t, response.CanProceed)
	assert.Equal(t, proto.CanProceedWithUsageStatus_BudgetLimitReached, response.Status)
	assert.Equal(t, 1, len(response.ApplicableBudgets))
	actualCurrentAmount := response.ApplicableBudgets[0].GetBudgetState().GetCurrentAmount()
	assert.Equal(t, float64(200)/models.ToNanoCents, actualCurrentAmount)

	// called ReadItem 4 times
	// 1 call to get the customer, 2 calls for cost center lookups, 1 call for budget state
	mockContainer.VerifyWasCalled(pegomock.Times(4)).ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions](),
	)
}

func Test_CanProceedWithUsage_FreeSkusReturnsTrueWhenFeatureFlagOn(t *testing.T) {
	mockContainer, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, pricingEngine, vexiAdapter := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)
	vexiAdapter.AddFeatureFlag(featureflags.FreeSkuCheckEnabled, true)
	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     "actions_self_hosted_linux",
			Product: "actions",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     199,
			},
		},
	}

	// mock customer response
	pegomock.When(mockContainer.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1")),
		pegomock.Eq("customer"), // id
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MakeTestCustomerWithoutPaymentMethod(t, helpers.WithAzureAccountId("testAzureAccountID"), helpers.WithEnabledProducts("actions", "copilot")), nil)

	// mock cost center response
	pegomock.When(mockContainer.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1:costCenters")),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MockAzureItemResponse(t, &models.CostCenter{
			CostCenterKey: &models.CostCenterKey{
				Key: &models.Key{
					Id:           "customer:1:costCenters:4",
					PartitionKey: "customer:1:costCenters",
				},
			},
		}), nil)

	// mock budget state response
	pegomock.When(mockContainer.ReadItem(
		pegomock.Any[context.Context](),
		helpers.Contains(azcosmos.NewPartitionKeyString("customer:1:budgets:repository:199:product:copilot")),
		pegomock.Eq("budgetState"),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MockAzureItemResponse(t, &models.BudgetState{
				CurrentAmount: 200, // To simulate fully funded budget
				TargetAmount:  200,
				IsFullyFunded: true, // This is only ever set during usage processing
			}), nil)

	var budgets []*models.Budget

	budgets = append(budgets, &models.Budget{
		BudgetKey: &models.BudgetKey{
			Key: &models.Key{
				Id:           "customer:1:budgets:repository:199:product:copilot",
				PartitionKey: "customer:1:budgets",
			},
			TargetType: models.Repository,
			TargetId:   "199",
		},
		TargetAmount:    200,
		BudgetLimitType: models.StopActiveUsage,
	})

	pager := helpers.MakePagerWithData(t, budgets)

	pegomock.When(
		mockContainer.NewQueryItemsPager(
			pegomock.Eq("SELECT * FROM c"),
			pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1:budgets")),
			pegomock.Any[*azcosmos.QueryOptions]())).
		ThenReturn(pager)

	mockPricing := &models.Pricing{
		Price:              int64(0),
		Sku:                "actions_self_hosted_linux",
		FriendlyName:       "Actions self hosted Linux",
		Product:            "actions",
		AzureMeterId:       "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
		MeterType:          models.PricingMeterDefault,
		FreeForPublicRepos: false,
		EffectiveAt:        time.Date(2023, 7, 14, 20, 30, 0, 0, time.UTC).Unix(),
		UnitType:           models.UnitTypeMinutes,
	}

	// Mock GetPricing response
	pegomock.When(pricingEngine.GetPricing(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq("actions_self_hosted_linux"),
		pegomock.Eq(false),
	)).ThenReturn(mockPricing, nil)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.True(t, response.CanProceed)
	assert.Equal(t, proto.CanProceedWithUsageStatus_UsageAllowed, response.Status)
}

func Test_CanProceedWithUsage_FreeSkusReturnsFalseWhenFeatureFlagOff(t *testing.T) {
	mockContainer, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, pricingEngine, vexiAdapter := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)
	vexiAdapter.AddFeatureFlag(featureflags.FreeSkuCheckEnabled, false)
	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     "actions_self_hosted_linux",
			Product: "actions",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     199,
			},
		},
	}

	// mock customer response
	pegomock.When(mockContainer.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1")),
		pegomock.Eq("customer"), // id
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MakeTestCustomerWithoutPaymentMethod(t, helpers.WithAzureAccountId("testAzureAccountID"), helpers.WithEnabledProducts("actions", "copilot")), nil)

	// mock cost center response
	pegomock.When(mockContainer.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1:costCenters")),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MockAzureItemResponse(t, &models.CostCenter{
			CostCenterKey: &models.CostCenterKey{
				Key: &models.Key{
					Id:           "customer:1:costCenters:4",
					PartitionKey: "customer:1:costCenters",
				},
			},
		}), nil)

	// mock budget state response
	pegomock.When(mockContainer.ReadItem(
		pegomock.Any[context.Context](),
		helpers.Contains(azcosmos.NewPartitionKeyString("customer:1:budgets:repository:199:product:copilot")),
		pegomock.Eq("budgetState"),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MockAzureItemResponse(t, &models.BudgetState{
				CurrentAmount: 200, // To simulate fully funded budget
				TargetAmount:  200,
				IsFullyFunded: true, // This is only ever set during usage processing
			}), nil)

	var budgets []*models.Budget

	budgets = append(budgets, &models.Budget{
		BudgetKey: &models.BudgetKey{
			Key: &models.Key{
				Id:           "customer:1:budgets:repository:199:product:copilot",
				PartitionKey: "customer:1:budgets",
			},
			TargetType: models.Repository,
			TargetId:   "199",
		},
		TargetAmount:    200,
		BudgetLimitType: models.StopActiveUsage,
	})

	pager := helpers.MakePagerWithData(t, budgets)

	pegomock.When(
		mockContainer.NewQueryItemsPager(
			pegomock.Eq("SELECT * FROM c"),
			pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1:budgets")),
			pegomock.Any[*azcosmos.QueryOptions]())).
		ThenReturn(pager)

	mockPricing := &models.Pricing{
		Price:              int64(0),
		Sku:                "actions_self_hosted_linux",
		FriendlyName:       "Actions self hosted Linux",
		Product:            "actions",
		AzureMeterId:       "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
		MeterType:          models.PricingMeterDefault,
		FreeForPublicRepos: false,
		EffectiveAt:        time.Date(2023, 7, 14, 20, 30, 0, 0, time.UTC).Unix(),
		UnitType:           models.UnitTypeMinutes,
	}

	// Mock GetPricing response
	pegomock.When(pricingEngine.GetPricing(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq("actions_self_hosted_linux"),
		pegomock.Eq(false),
	)).ThenReturn(mockPricing, nil)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.False(t, response.CanProceed)
	assert.Equal(t, proto.CanProceedWithUsageStatus_NotBillable, response.Status)
}

func Test_PatchCustomer(t *testing.T) {
	_, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerAPI, _, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, nil)

	tests := []struct {
		name          string
		request       *proto.PatchCustomerRequest
		expectedError error
	}{
		{
			name: "successfully patches customer",
			request: &proto.PatchCustomerRequest{
				Customer: &proto.Customer{
					CustomerId:       "123",
					DiscountPlanName: "PlanA",
				},
			},
			expectedError: nil,
		},
		{
			name: "produces required argument error when customer is nil",
			request: &proto.PatchCustomerRequest{
				Customer: nil,
			},
			expectedError: twirp.RequiredArgumentError("customer"),
		},
		{
			name: "produces required argument error when customer id is blank",
			request: &proto.PatchCustomerRequest{
				Customer: &proto.Customer{
					CustomerId: "",
				},
			},
			expectedError: twirp.RequiredArgumentError("customer.customerId"),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Stub nil error return from customerService.UpsertAndMigrateCustomer
			pegomock.When(customerAPI.customerService.UpsertAndMigrateCustomer(pegomock.Any[context.Context](), pegomock.Any[*proto.Customer](), pegomock.Any[string](), pegomock.Any[log.Logger]())).
				ThenReturn(nil)

			_, err := customerAPI.PatchCustomer(context.Background(), tt.request)
			assert.Equal(t, err, tt.expectedError)
		})
	}
}

func Test_Get_Alertable_Budget_State_Info(t *testing.T) {
	_, _, stats, logger, db, tracer, cfg := setupMocks(t)

	mockBudgetEngine := fakes.NewMockBudgetEngineInterface()
	customerAPI, _, _ := setupCustomerAPI(t, logger, cfg, db, stats, tracer, mockBudgetEngine)

	tests := []struct {
		name          string
		request       *proto.GetAllBudgetsRequest
		expectedError error
	}{
		{
			name:          "produces required argument error when request is nil",
			request:       nil,
			expectedError: twirp.RequiredArgumentError("request"),
		},
		{
			name: "produces required argument error when customer id is blank",
			request: &proto.GetAllBudgetsRequest{
				CustomerId: "",
			},
			expectedError: twirp.RequiredArgumentError("customerId"),
		},
		{
			name: "successfully gets alertable budget state info",
			request: &proto.GetAllBudgetsRequest{
				CustomerId: "123",
			},
			expectedError: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.expectedError == nil {
				pegomock.When(mockBudgetEngine.GetAlertableBudgetStateInfo(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[string]())).
					ThenReturn([]*models.BudgetInfo{}, nil)
			} else {
				pegomock.When(mockBudgetEngine.GetAlertableBudgetStateInfo(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[string]())).
					ThenReturn(nil, tt.expectedError)
			}

			_, err := customerAPI.GetAlertableBudgetStateInfo(context.Background(), tt.request)
			assert.Equal(t, tt.expectedError, err)
		})
	}
}

func setupMocks(t *testing.T) (*fakes.MockCosmosConnection, *telemetry.Provider, *mocks.Client, log.Logger, *fakes.MockDatabase, trace.Tracer, *config.Config) {
	pegomock.RegisterMockTestingT(t)
	c, telem, stats, logger, db := helpers.SetupMocks(t)
	tracer := telem.Tracer.Tracer
	cfg := &config.Config{
		Environment: "test",
	}
	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(c)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
	pegomock.When(db.GetStatter()).ThenReturn(stats)
	return c, telem, stats, logger, db, tracer, cfg
}

func setupCustomerAPI(t *testing.T, logger log.Logger, cfg *config.Config, db *fakes.MockDatabase, stats *mocks.Client, tracer trace.Tracer, budgetEngine engines.BudgetEngineInterface) (*CustomerApi, engines.PricingEngineInterface, *fake.Adapter) {
	vexiClient, vexiAdapter := helpers.NewFeatureFlagClient(context.Background(), t, false)

	engineParams := engines.NewEngineParams(nil, cfg, db, vexiClient, stats, nil, tracer)
	customerEngine := engines.NewCustomerEngine(engineParams)
	pricingEngine := fakes.NewMockPricingEngineInterface()
	subscriptionsEngine := engines.NewSubscriptionsEngine(engineParams, nil, logger)
	discountEngine := engines.NewDiscountEngine(engineParams, pricingEngine, subscriptionsEngine)
	customerService := fakes.NewMockCustomerServiceInterface()
	costCenterEngine := engines.NewCostCenterEngine(engineParams, pricingEngine, customerEngine)
	if budgetEngine == nil {
		budgetEngine = engines.NewBudgetEngine(engineParams, customerEngine)
	}

	return NewCustomerAPI(customerEngine, discountEngine, pricingEngine, costCenterEngine, budgetEngine, customerService, logger, stats, tracer, vexiClient), pricingEngine, vexiAdapter
}

func getMockNonFreePricing(t *testing.T, sku string) *models.Pricing {
	mockPricing := &models.Pricing{
		Price:              int64(1),
		Sku:                sku,
		FriendlyName:       "friendly-sku",
		Product:            "some-product",
		AzureMeterId:       "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
		MeterType:          models.PricingMeterDefault,
		FreeForPublicRepos: false,
		EffectiveAt:        time.Date(2023, 7, 14, 20, 30, 0, 0, time.UTC).Unix(),
		UnitType:           models.UnitTypeMinutes,
	}

	return mockPricing
}
