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
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats/mocks"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
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

type HighWatermarkTestData struct {
	name     string
	targetId string
	expected bool
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
	customerEngine := engines.NewCustomerEngine(engines.NewEngineParams(
		nil, nil, mockDb, nil, nil, nil, nil,
	))
	tracer := telem.Tracer.Tracer
	customerAPI := NewCustomerAPI(customerEngine, logger, statter, tracer)

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

func Test_isBudgetForHighWatermarkProducts(t *testing.T) {
	t.Parallel()

	tests := []HighWatermarkTestData{
		{
			name:     "high watermark sku",
			targetId: "copilot_for_business",
			expected: true,
		},
		{
			name:     "non high watermark sku",
			targetId: "non_high_watermark",
			expected: false,
		},
		{
			name:     "high watermark product",
			targetId: "copilot",
			expected: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			testIsBudgetForHighWatermarkProducts(t, tt)
		})
	}
}

func testIsBudgetForHighWatermarkProducts(t *testing.T, tt HighWatermarkTestData) {
	_, telem, statter, logger, mockDb := helpers.SetupMocks(t)
	customerEngine := engines.NewCustomerEngine(engines.NewEngineParams(
		nil, nil, mockDb, nil, nil, nil, nil,
	))
	tracer := telem.Tracer.Tracer
	customerAPI := NewCustomerAPI(customerEngine, logger, statter, tracer)

	isHighWatermark := customerAPI.isHighWatermarkProduct(tt.targetId)
	assert.Equal(t, tt.expected, isHighWatermark)
}

func Test_CanProceedWithUsagePublicRepoStandardRunner(t *testing.T) {
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
			pegomock.Eq(azcosmos.NewPartitionKeyString("repos")),
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

	pegomock.When(
		c.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Eq(azcosmos.NewPartitionKeyString("pricing")),
			pegomock.Eq(sku),
			pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MockAzureItemResponse(t, &models.Pricing{
				Sku:                sku,
				FreeForPublicRepos: true,
			}),
			nil,
		)

	customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)
	customerEngine := engines.NewCustomerEngine(customerEngineParams)

	customerAPI := NewCustomerAPI(customerEngine, logger, stats, tracer)
	request := &proto.CanProceedWithUsageRequest{
		UsageKey: &proto.UsageKey{
			Sku:     sku,
			Product: "actions",
			EntityDetail: &proto.EntityDetail{
				CustomerId: "1",
				OwnerId:    4,
				RepoId:     int64(repoId),
			},
		},
	}

	// Test
	response, _ := customerAPI.CanProceedWithUsage(context.Background(), request)

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

	customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, tracer)
	customerEngine := engines.NewCustomerEngine(customerEngineParams)

	customerAPI := NewCustomerAPI(customerEngine, logger, stats, tracer)
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

	customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, tracer)
	customerEngine := engines.NewCustomerEngine(customerEngineParams)

	customerAPI := NewCustomerAPI(customerEngine, logger, stats, tracer)
	request := &proto.CanProceedWithUsageRequest{}

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, response)
	assert.ErrorContains(t, err, "twirp error invalid_argument: usageKey is required")
}

func Test_CanProceedWithUsage_NilUsageKeyEntityDetail(t *testing.T) {
	_, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, tracer)
	customerEngine := engines.NewCustomerEngine(customerEngineParams)

	customerAPI := NewCustomerAPI(customerEngine, logger, stats, tracer)
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

	customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, tracer)
	customerEngine := engines.NewCustomerEngine(customerEngineParams)

	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MockAzureItemResponseWith404(t), errors.New("some error"))

	customerAPI := NewCustomerAPI(customerEngine, logger, stats, tracer)
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

	customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, tracer)
	customerEngine := engines.NewCustomerEngine(customerEngineParams)

	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MockAzureItemResponseWith404(t), &azcore.ResponseError{StatusCode: http.StatusNotFound})

	customerAPI := NewCustomerAPI(customerEngine, logger, stats, tracer)
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
	assert.ErrorContains(t, err, "twirp error not_found: Customer with id 1 not found")
}
func Test_CanProceedWithUsage_TradeRestrictions(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, tracer)
	customerEngine := engines.NewCustomerEngine(customerEngineParams)

	customerAPI := NewCustomerAPI(customerEngine, logger, stats, tracer)
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

	customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, tracer)
	customerEngine := engines.NewCustomerEngine(customerEngineParams)

	customerAPI := NewCustomerAPI(customerEngine, logger, stats, tracer)
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
				helpers.WithAzureAccountId("deadbeef")),
			nil,
		)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.False(t, response.CanProceed)
	assert.Equal(t, response.Status, proto.CanProceedWithUsageStatus_OnTrial)
}

func Test_CanProceedWithUsage_PlanDiscounts_NotBillable(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, tracer)
	customerEngine := engines.NewCustomerEngine(customerEngineParams)

	customerAPI := NewCustomerAPI(customerEngine, logger, stats, tracer)
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
		ThenReturn(helpers.MakeTestCustomer(t), nil)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.False(t, response.CanProceed)
	assert.Equal(t, response.Status, proto.CanProceedWithUsageStatus_NotBillable)
}

func Test_CanProceedWithUsage_PlanDiscounts_noFullyFundedBudgets(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, tracer)
	customerEngine := engines.NewCustomerEngine(customerEngineParams)

	customerAPI := NewCustomerAPI(customerEngine, logger, stats, tracer)
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
		helpers.Contains(azcosmos.NewPartitionKeyString("customer:")),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MakeTestCustomer(t, helpers.WithAzureAccountId("testAzureAccountID")), nil)

	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Eq("budgetState"),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MockAzureItemResponse(t, &models.BudgetState{}), nil)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.True(t, response.CanProceed)
	assert.Equal(t, proto.CanProceedWithUsageStatus_UsageAllowed, response.Status)
}

func Test_CanProceedWithUsage_PlanDiscounts_IsFullyFundedBudgetsWithoutHardLimits(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, tracer)
	customerEngine := engines.NewCustomerEngine(customerEngineParams)

	customerAPI := NewCustomerAPI(customerEngine, logger, stats, tracer)
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
		helpers.Contains(azcosmos.NewPartitionKeyString("customer:")),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MakeTestCustomer(t, helpers.WithAzureAccountId("testAzureAccountID")), nil)

	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Eq("budgetState"),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MockAzureItemResponse(t, &models.BudgetState{
			IsFullyFunded: true,
		}), nil)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.True(t, response.CanProceed)
	assert.Equal(t, proto.CanProceedWithUsageStatus_UsageAllowed, response.Status)
}

func Test_CanProceedWithUsage_PlanDiscounts_IsFullyFundedBudgetsHardLimits(t *testing.T) {
	c, _, stats, logger, db, tracer, cfg := setupMocks(t)

	customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, tracer)
	customerEngine := engines.NewCustomerEngine(customerEngineParams)

	customerAPI := NewCustomerAPI(customerEngine, logger, stats, tracer)
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
		helpers.Contains(azcosmos.NewPartitionKeyString("customer:")),
		pegomock.Any[string](),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MakeTestCustomer(t, helpers.WithAzureAccountId("testAzureAccountID")), nil)

	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[azcosmos.PartitionKey](),
		pegomock.Eq("budgetState"),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MockAzureItemResponse(t, &models.BudgetState{
			IsFullyFunded: true,
		}), nil)
	pegomock.When(c.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("customer:1:budgets")),
		pegomock.Eq("customer:1:budgets:repository:199:product:copilot"),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MockAzureItemResponse(t, &models.Budget{
			BudgetKey: &models.BudgetKey{
				Key: &models.Key{
					Id:           "customer:1:budgets:repository:199:product:copilot",
					PartitionKey: "customer:1:budgets"},
			},
			TargetAmount:    100,
			BudgetLimitType: models.StopActiveUsage,
		}), nil)

	// Test
	response, err := customerAPI.CanProceedWithUsage(context.Background(), request)

	// Assert
	assert.Nil(t, err)
	assert.False(t, response.CanProceed)
	assert.Equal(t, proto.CanProceedWithUsageStatus_BudgetLimitReached, response.Status)
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
