package api

import (
	"context"
	"testing"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func Test_GetAllCostCenters_Cache(t *testing.T) {
	_, telem, _, logger, _ := helpers.SetupMocks(t)
	mocker := pegomock.WithT(t)

	tests := []struct {
		name       string
		customerId string
		useCache   bool
	}{
		{
			name:       "use cache",
			customerId: "1",
			useCache:   true,
		},
		{
			name:       "do not use cache",
			customerId: "1",
			useCache:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockCostCenterEngine := fakes.NewMockCostCenterEngineInterface(mocker)
			customerAPI := NewCostCenterAPI(mockCostCenterEngine, nil, logger, telem.Tracer.Tracer)

			response, err := customerAPI.GetAllCostCenters(context.Background(), &proto.GetAllCostCentersRequest{
				CustomerId: tt.customerId,
				UseCache:   tt.useCache,
			})

			if tt.useCache {
				mockCostCenterEngine.VerifyWasCalledOnce().GetAllCostCentersFromCache(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.Customer]())
			} else {
				mockCostCenterEngine.VerifyWasCalledOnce().GetAllCostCenters(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.Customer]())
			}

			assert.Equal(t, 0, len(response.CostCenters))
			assert.Nil(t, err)
		})
	}
}
