package rollups

import (
	"context"
	"testing"
	"time"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/messaging/handlers"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	"golang.org/x/sync/errgroup"
)

func Test_doCustomerZuoraEmissionDailyRollup(t *testing.T) {

	tests := []struct {
		name          string
		item          models.Item
		patchOrCreate func(ctx context.Context, logger log.Logger, item models.Item) error
		expectedError error
	}{
		{
			name: "Successful Rollup",
			item: models.Item{
				Key: models.Key{
					PartitionKey: models.NewUsageTimeFromTime(time.Now().AddDate(0, 0, -1)).ToPartitionKey(models.Daily) + ":byZuoraEmission", // These keys will be 1 day behind the current date
					Id:           "123:actions_storage:" + models.NewUsageTimeFromTime(time.Now().AddDate(0, 0, -1)).ToPartitionKey(models.Daily),
				},
				Amounts: &models.Amounts{
					Quantity:     10,
					FullQuantity: 10,
					BilledAmount: 100,
				},
				UsageAt: *models.NewUsageTimeFromTime(time.Now().AddDate(0, 0, -2)), // These dates will be 2 days behind the current date
				Pricing: &models.Pricing{
					Price: 10,
					Sku:   "actions_storage",
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123",
					},
				},
			},

			patchOrCreate: func(ctx context.Context, logger log.Logger, item models.Item) error {
				return nil
			},
			expectedError: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fakeContainer, telem, mockedStatter, mockedLogger, mockedDatabase := helpers.SetupMocks(t)

			cfg := &config.Config{
				Environment: "test",
			}

			pegomock.When(mockedDatabase.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(mockedDatabase.GetConnection()).ThenReturn(fakeContainer)
			pegomock.When(mockedDatabase.GetGatewayConnection()).ThenReturn(fakeContainer)
			pegomock.When(mockedDatabase.GetStatter()).ThenReturn(mockedStatter)

			ctx := context.Background()
			g, ctx := errgroup.WithContext(ctx)

			engineParams := engines.NewEngineParams(nil, cfg, mockedDatabase, nil, mockedStatter, nil, telem.Tracer.Tracer)
			totalsPatching := engines.NewTotalPatchingEngine(engineParams)

			handlerParams := handlers.HandlerParams{
				DB:             mockedDatabase,
				TotalsPatching: totalsPatching,
			}

			handler := handlers.NewRollupHandler(
				&handlerParams,
				doCustomerZuoraEmissionDailyRollup,                // Assuming this is the rollup function you want to test
				models.WorkerTypeCustomerZuoraEmissionDailyRollup, // Replace with the appropriate worker type
				"CustomerZuoraEmissionDailyRollup",
				handlers.WithRateLimit(1000),
			)

			err := doCustomerZuoraEmissionDailyRollup(ctx, mockedLogger, tt.item, g, handler)
			assert.Equal(t, tt.expectedError, err)
		})
	}
}
