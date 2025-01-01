package api

import (
	"context"
	"testing"
	"time"

	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"

	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func Test_GetAzureEmissions(t *testing.T) {
	mocker := pegomock.WithT(t)
	_, _, _, logger, _ := helpers.SetupMocks(t)

	actionsRolloutEffectiveAt := time.Date(2023, 7, 14, 20, 30, 0, 0, time.UTC).Unix()
	mockPricings := []*models.Pricing{
		{
			Price:              int64(1400000000), // $1.4 in nano
			Sku:                "actions_linux",
			FriendlyName:       "Actions Linux",
			Product:            "actions",
			AzureMeterId:       "8a019f97-b29d-54e1-9cff-ca30b7b7bdca",
			MeterType:          models.PricingMeterDefault,
			FreeForPublicRepos: false,
			EffectiveAt:        actionsRolloutEffectiveAt,
			UnitType:           models.UnitTypeMinutes,
		},
	}

	tests := []struct {
		name                      string
		customerId                string
		year                      int64
		month                     int64
		day                       int64
		product                   string
		azureEmissions            *models.AzureEmission
		expectedEmissionsCount    int
		expectInvalidProductError bool
		expectedIsCostCenter      bool
		pricings                  []*models.Pricing
		costCenters               []*models.CostCenter
		costCenterCacheFF         bool
	}{
		{
			name:                   "GetAzureEmissions returns no emissions",
			customerId:             "1",
			year:                   2022,
			month:                  1,
			day:                    1,
			product:                "actions",
			azureEmissions:         nil,
			expectedEmissionsCount: 0,
			pricings:               mockPricings,
		},
		{
			name:       "GetAzureEmissions returns emissions",
			customerId: "1",
			year:       2022,
			month:      1,
			day:        1,
			product:    "actions",
			azureEmissions: &models.AzureEmission{
				Key: &models.Key{
					PartitionKey: "1:actions_linux:2022:1",
					Id:           "1::actions_linux:2022:1:1",
				},
				AzurePartitionKey: "1:2022:1",
				Quantity:          165,
			},
			expectedEmissionsCount: 1,
			expectedIsCostCenter:   false,
			pricings:               mockPricings,
		},
		{
			name:       "GetAzureEmissions returns emissions with cost centers",
			customerId: "1",
			year:       2022,
			month:      1,
			day:        1,
			product:    "actions",
			azureEmissions: &models.AzureEmission{
				Key: &models.Key{
					PartitionKey: "a5da61a7-ef2e-46a8-a636-822ecc4c767c:actions_linux:2022:1",
					Id:           "a5da61a7-ef2e-46a8-a636-822ecc4c767c:actions_linux:2022:1:1",
				},
				AzurePartitionKey: "0db277b1-649d-43c4-82ca-a2b0d78e91c0",
				Quantity:          165,
			},
			costCenters: []*models.CostCenter{
				{
					Name: "cost-center-1",
					CostCenterKey: &models.CostCenterKey{
						UUID: "a5da61a7-ef2e-46a8-a636-822ecc4c767c",
						Key: &models.Key{
							Id: "cost-center-id",
						},
					},
				},
			},
			expectedIsCostCenter:      true,
			expectInvalidProductError: false,
			expectedEmissionsCount:    1,
			pricings:                  mockPricings,
		},
		{
			name:                      "Returns error on invalid product",
			customerId:                "1",
			year:                      2022,
			month:                     1,
			day:                       1,
			product:                   "invalid-product",
			azureEmissions:            nil,
			expectedEmissionsCount:    0,
			expectInvalidProductError: true,
			pricings:                  nil,
		},
		{
			name:                   "GetAzureEmissions returns no emissions",
			customerId:             "1",
			year:                   2022,
			month:                  1,
			day:                    1,
			product:                "actions",
			azureEmissions:         nil,
			expectedEmissionsCount: 0,
			pricings:               mockPricings,
			costCenterCacheFF:      true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockPricingEngine := fakes.NewMockPricingEngineInterface()
			mockAzureEmissionEngine := fakes.NewMockAzureEmissionEngineInterface(mocker)
			mockCostCenterEngine := fakes.NewMockCostCenterEngineInterface(mocker)

			pegomock.When(mockPricingEngine.GetPricingsByProduct(
				pegomock.Any[context.Context](),
				pegomock.Any[log.Logger](),
				pegomock.Any[string](),
			)).ThenReturn(tt.pricings, nil)

			if tt.expectedIsCostCenter {
				pegomock.When(mockAzureEmissionEngine.GetAzureEmission(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Eq(&models.AzureEmissionPartitionDetail{
						CustomerId: "a5da61a7-ef2e-46a8-a636-822ecc4c767c",
						Sku:        "actions_linux",
						Year:       2022,
						Month:      1,
						Day:        1,
					}),
				)).ThenReturn(tt.azureEmissions, nil)
				pegomock.When(mockAzureEmissionEngine.GetAzureEmission(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Eq(&models.AzureEmissionPartitionDetail{
						CustomerId: "1",
						Sku:        "actions_linux",
						Year:       2022,
						Month:      1,
						Day:        1,
					}),
				)).ThenReturn(nil, nil)
			} else {
				pegomock.When(mockAzureEmissionEngine.GetAzureEmission(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Eq(&models.AzureEmissionPartitionDetail{
						CustomerId: "a5da61a7-ef2e-46a8-a636-822ecc4c767c",
						Sku:        "actions_linux",
						Year:       2022,
						Month:      1,
						Day:        1,
					}),
				)).ThenReturn(nil, nil)
				pegomock.When(mockAzureEmissionEngine.GetAzureEmission(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Eq(&models.AzureEmissionPartitionDetail{
						CustomerId: "1",
						Sku:        "actions_linux",
						Year:       2022,
						Month:      1,
						Day:        1,
					}),
				)).ThenReturn(tt.azureEmissions, nil)
			}

			if tt.costCenterCacheFF {
				pegomock.When(mockCostCenterEngine.GetAllCostCentersFromCache(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[*models.Customer](),
				)).ThenReturn(tt.costCenters, nil)
			} else {
				pegomock.When(mockCostCenterEngine.GetAllCostCenters(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[*models.Customer](),
				)).ThenReturn(tt.costCenters, nil)
			}

			vexiClient, vexiAdapter := helpers.NewFeatureFlagClient(context.Background(), t, false)
			vexiAdapter.AddFeatureFlag(featureflags.CostCenterQueryCaching, tt.costCenterCacheFF)

			adminApi := NewAdminAPI(nil, mockAzureEmissionEngine, nil, mockCostCenterEngine, logger, mockPricingEngine, vexiClient)

			response, err := adminApi.GetAzureEmissions(context.Background(), &proto.GetAzureEmissionsRequest{
				CustomerId: tt.customerId,
				Year:       tt.year,
				Month:      tt.month,
				Day:        tt.day,
				Product:    tt.product,
			})

			if tt.expectInvalidProductError {
				assert.Error(t, err)
				assert.Contains(t, err.Error(), "invalid product value provided")
			} else {
				if tt.costCenterCacheFF {
					mockCostCenterEngine.VerifyWasCalledOnce().GetAllCostCentersFromCache(
						pegomock.Any[context.Context](),
						pegomock.Any[log.Logger](),
						pegomock.Any[*models.Customer](),
					)
				} else {
					mockCostCenterEngine.VerifyWasCalledOnce().GetAllCostCenters(
						pegomock.Any[context.Context](),
						pegomock.Any[log.Logger](),
						pegomock.Any[*models.Customer](),
					)
				}

				assert.Nil(t, err)
				assert.Equal(t, tt.expectedEmissionsCount, len(response.AzureEmissions))
				if len(response.AzureEmissions) > 0 {
					if tt.expectedIsCostCenter {
						// Called twice, once for customer id and another for cost center uuid
						mockAzureEmissionEngine.VerifyWasCalled(pegomock.Times(2)).GetAzureEmission(
							pegomock.Any[context.Context](),
							pegomock.Any[log.Logger](),
							pegomock.Any[*models.AzureEmissionPartitionDetail](),
						)

						assert.Equal(t, tt.expectedIsCostCenter, response.AzureEmissions[0].UsageEntity.IsCostCenter)
						assert.Equal(t, 231.0, response.AzureEmissions[0].EstimatedBilledAmount)
					} else {
						mockAzureEmissionEngine.VerifyWasCalledOnce().GetAzureEmission(
							pegomock.Any[context.Context](),
							pegomock.Any[log.Logger](),
							pegomock.Any[*models.AzureEmissionPartitionDetail](),
						)

						assert.Equal(t, tt.expectedIsCostCenter, response.AzureEmissions[0].UsageEntity.IsCostCenter)
						assert.Equal(t, 231.0, response.AzureEmissions[0].EstimatedBilledAmount)
					}
				}
			}
		})
	}
}
