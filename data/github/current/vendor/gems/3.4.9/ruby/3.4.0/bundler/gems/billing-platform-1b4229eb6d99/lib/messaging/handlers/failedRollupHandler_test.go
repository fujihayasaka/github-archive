package handlers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats/mocks"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func setupTestHandler(t *testing.T) (*FailedRollupHandler, *fakes.MockDatabase, *telemetry.Provider, *mocks.Client, vexi.Adapter) {
	fakeContainer, telem, stats, _, db := helpers.SetupMocks(t)

	cfg := &config.Config{
		Environment: "test",
	}

	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
	pegomock.When(db.GetStatter()).ThenReturn(stats)

	// mock readitem to return cost center
	pegomock.When(
		db.GetConnection().ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[string](),
			pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.StaticTestCustomerReadItemResponse(t),
			nil,
		)

	engineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)
	totalsPatching := engines.NewTotalPatchingEngine(engineParams)

	vexiClient, vexiAdapter := helpers.NewFeatureFlagClient(context.Background(), t, false)
	handler := NewFailedRollupHandler(
		&HandlerParams{
			tracer:         telem.Tracer.Tracer,
			statter:        stats,
			flagger:        vexiClient,
			DB:             db,
			TotalsPatching: totalsPatching,
		},
	)

	return handler, db, telem, stats, vexiAdapter
}

func createPayload(processorType models.ActiveType, aggregationType models.RollupJobAggregationType) []byte {
	i := models.FailedRollupJob{
		ProcessorType:   processorType,
		AggregationType: aggregationType,
		From:            models.ByCustomer,
		To:              models.ByCustomerSku,
		KeysToIgnore:    []string{},
		Item: models.Item{
			Key: models.Key{
				PartitionKey: "123:actions_storage:2240:2",
				Id:           "123:actions_storage:2240:2",
			},
			UsageAt: *models.NewUsageTimeFromTime(time.Date(1970, time.January, 1, 0, 0, 0, 0, time.UTC)),
		},
	}
	p, _ := json.Marshal(&i)
	return p
}

func Test_ProcessMessage(t *testing.T) {
	pegomock.RegisterMockTestingT(t)

	tests := []struct {
		name            string
		processorType   models.ActiveType
		aggregationType models.RollupJobAggregationType
		payload         []byte
		expectedError   string
	}{
		{
			name:            "ProcessMessage with invalid payload",
			processorType:   models.Yearly,
			aggregationType: models.DiscountUsageAggregation,
			payload:         []byte("Invalid Payload"),
			expectedError:   "failedRollupHandler failed to unmarshal enveloped message",
		},
		{
			name:            "ProcessMessage for a Normal Usage Aggregation Daily Rollup",
			processorType:   models.Daily,
			aggregationType: models.NormalUsageAggregation,
		},
		{
			name:            "ProcessMessage for a Normal Usage Aggregation Monthly Rollup",
			processorType:   models.Monthly,
			aggregationType: models.NormalUsageAggregation,
		},
		{
			name:            "ProcessMessage for a Normal Usage Aggregation Yearly Rollup",
			processorType:   models.Yearly,
			aggregationType: models.NormalUsageAggregation,
		},
		{
			name:            "ProcessMessage for a Discount Usage Aggregation Daily Rollup",
			processorType:   models.Daily,
			aggregationType: models.DiscountUsageAggregation,
		},
		{
			name:            "ProcessMessage for a Discount Usage Aggregation Monthly Rollup",
			processorType:   models.Monthly,
			aggregationType: models.DiscountUsageAggregation,
		},
		{
			name:            "ProcessMessage for a Discount Usage Aggregation Yearly Rollup",
			processorType:   models.Yearly,
			aggregationType: models.DiscountUsageAggregation,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			handler, _, _, _, _ := setupTestHandler(t)
			var payload []byte
			if tt.payload != nil {
				payload = tt.payload
			} else {
				payload = createPayload(tt.processorType, tt.aggregationType)
			}
			err := handler.ProcessMessage(context.Background(), log.NewNullLogger(), aqueduct.ReceiveResult{
				Job: aqueduct.Job{
					Payload: payload,
				},
				ValidPayload: true,
			})
			if tt.expectedError != "" {
				assert.ErrorContains(t, err, tt.expectedError)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}
