package engines

import (
	"context"
	"testing"
	"time"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/feature-management-client-go/vexi/adapter/fake"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

type TestPricingObject struct {
	mocker                pegomock.Option
	mockDB                *fakes.MockDatabase
	aqueductClient        *fakes.MockAqueductClient
	pricingEngine         PricingEngineInterface
	pricingQuerier        *fakes.MockQuerier[*models.Pricing]
	gatewayPricingQuerier *fakes.MockQuerier[*models.Pricing]
	vexiFakeAdapter       *fake.Adapter
}

type HighWatermarkPricingTestData struct {
	name     string
	targetId string
	expected bool
}

func InitializePricingTestObject(t *testing.T) TestPricingObject {
	mocker := pegomock.WithT(t)
	pricingQuerier := fakes.NewMockQuerier[*models.Pricing](mocker)
	gatewayPricingQuerier := fakes.NewMockQuerier[*models.Pricing](mocker)
	mockDB := fakes.NewMockDatabase(mocker)
	aqueductClient := &fakes.MockAqueductClient{}

	_, _, stats, _, _ := helpers.SetupMocks(t)

	cfg := &config.Config{
		Environment: "test",
	}

	vexiClient, vexiAdapter := helpers.NewFeatureFlagClient(context.Background(), t, false)

	engineParams := &EngineParams{
		db:             mockDB,
		cfg:            cfg,
		aqueductClient: aqueductClient,
		statter:        stats,
		flagger:        vexiClient,
	}

	pricingEngine := NewPricingEngineWithQuerier(engineParams, pricingQuerier, gatewayPricingQuerier)
	return TestPricingObject{
		mocker:                mocker,
		mockDB:                mockDB,
		aqueductClient:        aqueductClient,
		pricingEngine:         pricingEngine,
		pricingQuerier:        pricingQuerier,
		gatewayPricingQuerier: gatewayPricingQuerier,
		vexiFakeAdapter:       vexiAdapter,
	}
}

func Test_GetAllPricing(t *testing.T) {
	// Register Pegomock with the testing object
	pegomock.RegisterMockTestingT(t)

	// Initialize the PricingTestObject using the helper function
	testPricingObject := InitializePricingTestObject(t)

	actionsRolloutEffectiveAt := time.Date(2023, 7, 14, 20, 30, 0, 0, time.UTC).Unix()

	// Prepare mock pricing data
	mockPricings := []*models.Pricing{
		{
			Price:              int64(1000 * 0.008),
			Sku:                "actions_linux",
			FriendlyName:       "Actions Linux",
			Product:            "actions",
			AzureMeterId:       "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
			MeterType:          models.PricingMeterDefault,
			FreeForPublicRepos: true,
			EffectiveAt:        actionsRolloutEffectiveAt,
			UnitType:           models.UnitTypeMinutes,
		},
		{
			Price:              int64(1000 * 0.064),
			Sku:                "actions_linux_16_core",
			FriendlyName:       "Actions Linux 16-core",
			Product:            "actions",
			AzureMeterId:       "cdc3163b-3623-5f85-9c2b-980c77501091",
			MeterType:          models.PricingMeterDefault,
			FreeForPublicRepos: false,
			EffectiveAt:        actionsRolloutEffectiveAt,
			UnitType:           models.UnitTypeMinutes,
		},
		{
			Price:              int64(1000 * 0.128),
			Sku:                "actions_linux_32_core",
			FriendlyName:       "Actions Linux 32-core",
			Product:            "actions",
			AzureMeterId:       "8a019f97-b29d-54e1-9cff-ca30b7b7bdca",
			MeterType:          models.PricingMeterDefault,
			FreeForPublicRepos: false,
			EffectiveAt:        actionsRolloutEffectiveAt,
			UnitType:           models.UnitTypeMinutes,
		},
	}

	// Set up the mock behavior for QueryItems using matchers for all arguments
	pegomock.When(testPricingObject.pricingQuerier.QueryItems(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(db.QueryStringAll),
		pegomock.Eq("pricing"),
	)).ThenReturn(mockPricings, nil)

	// Call the method under test
	ctx := context.Background()
	logger := log.NewNullLogger()
	skipCache := true
	pricings, err := testPricingObject.pricingEngine.GetAllPricing(ctx, logger, skipCache)

	// Assertions
	assert.NoError(t, err)
	assert.Equal(t, mockPricings, pricings)
}

func Test_isBudgetForHighWatermarkProducts(t *testing.T) {
	t.Parallel()

	tests := []HighWatermarkPricingTestData{
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

func testIsBudgetForHighWatermarkProducts(t *testing.T, tt HighWatermarkPricingTestData) {
	// Register Pegomock with the testing object
	pegomock.RegisterMockTestingT(t)

	testPricingObject := InitializePricingTestObject(t)

	// Prepare mock pricing data
	mockPricing := &models.Pricing{
		Sku:       "copilot_for_business",
		Product:   "copilot",
		MeterType: models.PricingMeterDefault,
		UnitType:  models.UnitTypeUserMonths,
	}

	// Set up the mock behavior for QueryItems using matchers for all arguments
	itemKey := &models.Key{
		Id:           "copilot_for_business",
		PartitionKey: "pricing",
	}
	pegomock.When(testPricingObject.pricingQuerier.ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(itemKey),
		pegomock.Any[*interfaces.QueryOptions](),
	)).ThenReturn(mockPricing, nil)

	logger := log.NewNullLogger()
	skipCache := true
	isHighWatermark := testPricingObject.pricingEngine.IsHighWatermarkProduct(context.Background(), logger, tt.targetId, skipCache)
	assert.Equal(t, tt.expected, isHighWatermark)
}

func Test_GetPricing_Cache(t *testing.T) {
	tests := []struct {
		name               string
		cachedPriceData    *models.Pricing
		nonCachedPriceData *models.Pricing
	}{
		{
			name: "successful integrated cache hit returns pricing",
			cachedPriceData: &models.Pricing{
				Sku: "actions_linux",
			},
		},
		{
			name:            "integrated cache hit with no data queries database",
			cachedPriceData: nil,
			nonCachedPriceData: &models.Pricing{
				Sku: "actions_linux",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pegomock.RegisterMockTestingT(t)
			testPricingObject := InitializePricingTestObject(t)

			itemKey := &models.Key{
				Id:           "actions_linux",
				PartitionKey: "pricing",
			}
			pegomock.When(testPricingObject.gatewayPricingQuerier.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Any[log.Logger](),
				pegomock.Eq(itemKey),
				pegomock.Any[*interfaces.QueryOptions](),
			)).ThenReturn(tt.cachedPriceData, nil)
			pegomock.When(testPricingObject.pricingQuerier.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Any[log.Logger](),
				pegomock.Eq(itemKey),
				pegomock.Any[*interfaces.QueryOptions](),
			)).ThenReturn(tt.nonCachedPriceData, nil)

			pricing, err := testPricingObject.pricingEngine.GetPricing(context.TODO(), log.NewNullLogger(), "actions_linux", false)
			assert.NoError(t, err)

			// verify no calls to the pricing querier if cached data is not nil
			if tt.cachedPriceData != nil {
				testPricingObject.pricingQuerier.VerifyWasCalled(pegomock.Never()).ReadItem(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.Key](), pegomock.Any[*interfaces.QueryOptions]())
				assert.Equal(t, tt.cachedPriceData, pricing)
			} else {
				testPricingObject.pricingQuerier.VerifyWasCalledOnce().ReadItem(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.Key](), pegomock.Any[*interfaces.QueryOptions]())
				assert.Equal(t, tt.nonCachedPriceData, pricing)
			}
		})
	}
}
