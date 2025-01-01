package api

import (
	"context"
	"testing"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func Test_Zuora_Emissions(t *testing.T) {
	pegomock.RegisterMockTestingT(t)
	mocker := pegomock.WithT(t)

	inputRequest := &proto.GetZuoraEmissionsRequest{
		CustomerId: "100",
		Year:       2021,
		Month:      12,
		Day:        25,
	}

	expectedEmissions := []*models.Emission{
		models.NewEmission(&models.EmissionPartitionDetail{
			CustomerId: inputRequest.CustomerId,
			Year:       inputRequest.Year,
			Month:      inputRequest.Month,
			Day:        inputRequest.Day,
		}, nil, nil, nil),
	}

	protoEmissions := make([]*proto.ZuoraEmission, len(expectedEmissions))
	for i, emission := range expectedEmissions {
		partitionDetail := &models.EmissionPartitionDetail{
			CustomerId: inputRequest.CustomerId,
			Year:       inputRequest.Year,
			Month:      inputRequest.Month,
			Day:        inputRequest.Day,
		}
		protoEmissions[i] = emission.ToProto(partitionDetail)
	}

	mockZuoraEngine := fakes.NewMockZuoraEngineInterface(mocker)
	mockEmissionQuerier := fakes.NewMockModelQuerier[*models.Emission](mocker)
	pegomock.When(mockEmissionQuerier.QueryItems(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[string](),
		pegomock.Any[string](),
	)).ThenReturn(expectedEmissions, nil)

	pegomock.When(mockZuoraEngine.GetZuoraEmissions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(inputRequest.CustomerId),
		pegomock.Eq(int64(inputRequest.Year)),
		pegomock.Eq(int64(inputRequest.Month)),
		pegomock.Eq(int64(inputRequest.Day)),
	)).ThenReturn(expectedEmissions, nil)

	api := NewZuoraEmissionAPI(mockZuoraEngine, log.NewNullLogger())

	response, err := api.GetZuoraEmissions(context.Background(), inputRequest)

	assert.Equal(t, protoEmissions, response.Emissions)
	assert.Equal(t, 1, len(response.Emissions))
	assert.Nil(t, err)
}
