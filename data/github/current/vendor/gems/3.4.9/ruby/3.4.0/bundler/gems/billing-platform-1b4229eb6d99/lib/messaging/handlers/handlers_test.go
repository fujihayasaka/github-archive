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
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func Test_GetAndPatchDiscount_QueryByOrgRepoProductSku_DiscountItem(t *testing.T) {
	fakeContainer, telem, stats, logger, db := helpers.SetupMocks(t)
	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
	pegomock.When(db.GetStatter()).ThenReturn(stats)

	// mock ReadItem to return a discount item
	pegomock.When(
		fakeContainer.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[string](),
			pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.StaticTestDiscountReadItemResponse(t),
			nil,
		)

	vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)

	handler := NewHandler(
		&HandlerParams{
			tracer:         telem.Tracer.Tracer,
			statter:        stats,
			DB:             db,
			flagger:        vexiClient,
			TotalsPatching: engines.NewTotalPatchingEngine(engines.NewEngineParams(nil, &config.Config{Environment: "test"}, db, nil, stats, nil, telem.Tracer.Tracer)),
		},
		models.WorkerTypeCustomerDailyRollup,
	)

	item := models.Item{
		Key: models.Key{
			PartitionKey: "1:2024:1:1:0",
			Id:           "f8f50dff-4b11-426f-8093-40191bb3ea3e",
		},
		EntityDetail: &models.EntityDetail{
			CostCenterDetail: &models.CostCenterDetail{
				EnterpriseCustomerId: "1",
			},
			CustomerId: "1",
		},
		UsageAt: *models.NewUsageTimeFromTime(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
	}

	err := handler.GetAndPatchDiscount(context.Background(), logger, item, models.Hourly, models.Daily, models.ByCustomer)
	assert.NoError(t, err)

	// verify that we end up querying the byOrgRepoProductSku hourly discount item
	fakeContainer.VerifyWasCalledOnce().ReadItem(
		pegomock.Any[context.Context](),
		pegomock.Eq(azcosmos.NewPartitionKeyString("1:2024:1:1:0:byOrgRepoProductSku:discount")),
		pegomock.Eq(item.Id),
		pegomock.Any[*azcosmos.ItemOptions]())
}

func Test_AddToDiscountStateUpdateQueue(t *testing.T) {
	mocker := pegomock.WithT(t)
	inputDiscountStatePayload := models.UpdateDiscountStatePayload{
		Amount: 100,
	}

	tests := []struct {
		name           string
		updatePayloads []models.UpdateDiscountStatePayload
	}{
		{
			name:           "single message payload",
			updatePayloads: []models.UpdateDiscountStatePayload{inputDiscountStatePayload},
		},
		{
			name:           "double message payload",
			updatePayloads: []models.UpdateDiscountStatePayload{inputDiscountStatePayload, inputDiscountStatePayload},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockAqueductClient := fakes.NewMockAqueductClient(mocker)
			_, telem, _, _, _ := helpers.SetupMocks(t)

			handler := NewHandler(
				&HandlerParams{
					aqueductClient: mockAqueductClient,
					appName:        "billing-platform",
					tracer:         telem.Tracer.Tracer,
				},
				models.WorkerTypeUsageIngestion,
			)

			handler.AddToDiscountStateUpdateQueue(
				context.Background(),
				log.NewNullLogger(),
				tt.updatePayloads,
				"actions_linux",
			)

			jobPayloadBytes, err := json.Marshal(&inputDiscountStatePayload)
			assert.NoError(t, err)

			// We should send one message for each payload
			mockAqueductClient.VerifyWasCalled(pegomock.Times(len(tt.updatePayloads))).Send(
				pegomock.Any[context.Context](),
				pegomock.Eq(
					aqueduct.Job{
						App:     "billing-platform",
						Queue:   "discount-state-update",
						Payload: jobPayloadBytes,
					},
				),
				pegomock.Any[aqueduct.SendOption](),
			)
		})
	}
}
