package api

import (
	"context"
	"testing"

	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/feature-management-client-go/vexi/adapter/fake"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats/mocks"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	"go.opentelemetry.io/otel/trace"
)

func Test_GetEnterpriseUsageTotals(t *testing.T) {
	tests := []struct {
		name                     string
		customerId               string
		costCenters              []*models.CostCenter
		items                    []*models.Item
		costCenteritems          []*models.Item
		withFlag                 bool
		expectedCustomerAmount   float64
		expectedCostCenterAmount float64
	}{
		{
			name:       "GetEnterpriseUsageTotals returns cost centers with flag",
			customerId: "2",
			costCenters: []*models.CostCenter{
				{
					Name: "cost-center-1",
					CostCenterKey: &models.CostCenterKey{
						Key: &models.Key{
							Id: "uuid-1",
						},
					},
				},
			},
			items: []*models.Item{
				{
					EntityDetail: &models.EntityDetail{
						CostCenterDetail: nil,
					},
					Amounts: &models.Amounts{
						BilledAmount: 150.0 * nano.NanoDivisor,
						Quantity:     15.0 * nano.NanoDivisor,
					},
				},
			},
			costCenteritems: []*models.Item{
				{
					EntityDetail: &models.EntityDetail{
						CostCenterDetail: &models.CostCenterDetail{
							CostCenterUUID:    "uuid-1",
							IsCostCenterProxy: true,
						},
					},
					Amounts: &models.Amounts{
						BilledAmount: 250.0 * nano.NanoDivisor,
						Quantity:     25.0 * nano.NanoDivisor,
					},
				},
			},
			withFlag:                 false,
			expectedCustomerAmount:   150.0,
			expectedCostCenterAmount: 250.0,
		},

		{
			name:       "GetEnterpriseUsageTotals returns cost centers with flag",
			customerId: "2",
			costCenters: []*models.CostCenter{
				{
					Name: "cost-center-1",
					CostCenterKey: &models.CostCenterKey{
						Key: &models.Key{
							Id: "uuid-1",
						},
					},
				},
			},
			items: []*models.Item{
				{
					EntityDetail: &models.EntityDetail{
						CostCenterDetail: nil,
					},
					Amounts: &models.Amounts{
						BilledAmount: 150.0 * nano.NanoDivisor,
						Quantity:     15.0 * nano.NanoDivisor,
					},
				},
			},
			costCenteritems: []*models.Item{
				{
					EntityDetail: &models.EntityDetail{
						CostCenterDetail: &models.CostCenterDetail{
							CostCenterUUID:    "uuid-1",
							IsCostCenterProxy: true,
						},
					},
					Amounts: &models.Amounts{
						BilledAmount: 250.0 * nano.NanoDivisor,
						Quantity:     25.0 * nano.NanoDivisor,
					},
				},
			},
			withFlag:                 true,
			expectedCustomerAmount:   150.0,
			expectedCostCenterAmount: 250.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pegomock.RegisterMockTestingT(t)
			_, telem, stats, logger, db := helpers.SetupMocks(t)
			tracer := telem.Tracer.Tracer
			cfg := &config.Config{
				Environment: "test",
			}
			var vexiAdapter *fake.Adapter
			usageApi, _, vexiAdapter := setupUsageAPI(t, logger, cfg, db, stats, tracer)

			// Cost Center Customer
			pegomock.When(usageApi.costCenterEngine.GetAllCostCentersFromCache(
				pegomock.Any[context.Context](),
				pegomock.Any[log.Logger](),
				pegomock.Eq(models.NewCustomer("2")),
			)).ThenReturn(tt.costCenters, nil)

			if tt.withFlag {
				vexiAdapter.AddFeatureFlag(featureflags.UpdateGetUsageTotal, true)
				// UsagePartitionDetail for our cost center
				pegomock.When(usageApi.usageEngine.GetUsageTotalItems(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.ArgThat[*models.UsagePartitionDetail](helpers.UsagePartitionDetailMatches("uuid-1")),
					pegomock.Any[string](),
					pegomock.Any[int64](),
					pegomock.Any[int64](),
				)).ThenReturn(tt.costCenteritems, nil)

				// UsagePartitionDetail for parent customer
				pegomock.When(usageApi.usageEngine.GetUsageTotalItems(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.ArgThat[*models.UsagePartitionDetail](helpers.UsagePartitionDetailMatches("2")),
					pegomock.Any[string](),
					pegomock.Any[int64](),
					pegomock.Any[int64](),
				)).ThenReturn(tt.items, nil)
			} else {
				vexiAdapter.AddFeatureFlag(featureflags.UpdateGetUsageTotal, false)
				pegomock.When(usageApi.usageEngine.GetEnterpriseUsageTotalItems(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.ArgThat[*models.UsagePartitionDetail](helpers.UsagePartitionDetailMatches("uuid-1")),
					pegomock.Any[*proto.GetEnterpriseUsageTotalsRequest](),
				)).ThenReturn(tt.costCenteritems, nil)

				// UsagePartitionDetail for parent customer
				pegomock.When(usageApi.usageEngine.GetEnterpriseUsageTotalItems(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.ArgThat[*models.UsagePartitionDetail](helpers.UsagePartitionDetailMatches("2")),
					pegomock.Any[*proto.GetEnterpriseUsageTotalsRequest](),
				)).ThenReturn(tt.items, nil)
			}

			response, err := usageApi.GetEnterpriseUsageTotals(context.Background(), &proto.GetEnterpriseUsageTotalsRequest{
				CustomerId: tt.customerId,
			})

			assert.Nil(t, err)
			for _, item := range response.Totals {
				if item.Name == "Enterprise Only" {
					assert.Equal(t, tt.expectedCustomerAmount, item.GrossAmount)
				} else {
					assert.Equal(t, tt.expectedCostCenterAmount, item.GrossAmount)
				}
			}
		})
	}
}

func Test_GetUsageTotal(t *testing.T) {
	tests := []struct {
		name           string
		usageEntityId  string
		year           int
		month          int
		expectedAmount float64
		expectedQty    float64
		items          []*models.Item
	}{
		{
			name:          "GetUsageTotal returns no usage",
			usageEntityId: "1",
			year:          2022,
			month:         1,
			items:         []*models.Item{},
		},
		{
			name:          "GetUsageTotal returns usage",
			usageEntityId: "1",
			year:          2022,
			month:         1,
			items: []*models.Item{
				{
					Amounts: &models.Amounts{
						BilledAmount: 100.0 * nano.NanoDivisor,
						Quantity:     10.0 * nano.NanoDivisor,
					},
				},
				{
					Amounts: &models.Amounts{
						BilledAmount: 200.0 * nano.NanoDivisor,
						Quantity:     20.0 * nano.NanoDivisor,
					},
				},
			},
			expectedAmount: 300.0,
			expectedQty:    30.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pegomock.RegisterMockTestingT(t)
			_, telem, stats, logger, db := helpers.SetupMocks(t)
			tracer := telem.Tracer.Tracer
			cfg := &config.Config{
				Environment: "test",
			}

			usageApi, _, vexiAdapter := setupUsageAPI(t, logger, cfg, db, stats, tracer)
			vexiAdapter.AddFeatureFlag(featureflags.UpdateGetUsageTotal, true)

			pegomock.When(usageApi.usageEngine.GetUsageTotalItems(
				pegomock.Any[context.Context](),
				pegomock.Any[log.Logger](),
				pegomock.Any[*models.UsagePartitionDetail](),
				pegomock.Any[string](),
				pegomock.Any[int64](),
				pegomock.Any[int64](),
			)).ThenReturn(tt.items, nil)

			response, err := usageApi.GetUsageTotal(context.Background(), &proto.GetUsageRequest{
				UsageEntityId: tt.usageEntityId,
				Year:          int64(tt.year),
				Month:         int64(tt.month),
			})

			assert.Nil(t, err)
			assert.Equal(t, tt.expectedAmount, response.BillableAmount)
			assert.Equal(t, tt.expectedQty, response.Quantity)
		})
	}
}

func setupUsageAPI(t *testing.T, logger log.Logger, cfg *config.Config, db *fakes.MockDatabase, stats *mocks.Client, tracer trace.Tracer) (*UsageApi, *fakes.MockUsageEngineInterface, *fake.Adapter) {
	vexiClient, vexiAdapter := helpers.NewFeatureFlagClient(context.Background(), t, false)
	engineParams := engines.NewEngineParams(nil, cfg, db, vexiClient, stats, nil, tracer)
	usageEngine := fakes.NewMockUsageEngineInterface()
	pricingEngine := fakes.NewMockPricingEngineInterface()
	discountEngine := engines.NewDiscountEngine(engineParams, pricingEngine, nil)
	kustoService := fakes.NewMockKustoService()
	costCenterEngine := fakes.NewMockCostCenterEngineInterface()

	return NewUsageAPI(nil, usageEngine, pricingEngine, nil, costCenterEngine, discountEngine, logger, stats, kustoService, nil, tracer, vexiClient), usageEngine, vexiAdapter
}
