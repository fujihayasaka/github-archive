package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	//nolint:staticcheck

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/helpers"
	stats "github.com/github/go-stats"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func TestAzureEmissionHandler_ProcessMessage_HighWatermarkEvent_WithDeletedEnterprise(t *testing.T) {
	// set up mocks
	customerId := "455"
	highWatermarkPayload := setupHighWaterMarkAzureEmissionPayload("sku1", 100, customerId)
	fakeContainer, telem, mockedStatter, mockedLogger, mockedDatabase := helpers.SetupMocks(t)

	pegomock.When(mockedDatabase.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(mockedDatabase.GetConnection()).ThenReturn(fakeContainer)
	pegomock.When(mockedDatabase.GetGatewayConnection()).ThenReturn(fakeContainer)
	pegomock.When(mockedDatabase.GetStatter()).ThenReturn(mockedStatter)

	// This mocks the query to get enterprise to return an error
	pegomock.When(
		fakeContainer.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Eq("customer"),
			pegomock.Any[*azcosmos.ItemOptions]())).ThenReturn(
		helpers.MockAzureItemResponse(t, &models.Customer{}),
		&azcore.ResponseError{StatusCode: http.StatusNotFound},
	)

	// Test
	handler := NewAzureEmissionHandler(&HandlerParams{statter: mockedStatter}, nil, engines.NewCustomerEngine(engines.NewEngineParams(nil, nil, mockedDatabase, nil, nil, nil, telem.Tracer.Tracer)), nil, nil, nil, nil, nil)
	err := handler.ProcessMessage(context.Background(), mockedLogger, highWatermarkPayload)

	// Assert
	assert.NoError(t, err)

	mockedStatter.AssertCalled(t, "Counter", "azure-emission-error", stats.Tags{"origin": "customer.enterpriseDeletedForHighWatermarkItem"}, int64(1))
	mockedStatter.AssertCalled(t, "Counter", "azure-emission-handler", stats.Tags{"success": "false"}, int64(1))
}

func setupHighWaterMarkAzureEmissionPayload(sku string, qty int64, cId string) aqueduct.ReceiveResult {
	item := &models.Item{
		Key:          models.Key{Id: "billable", PartitionKey: "uuidpk"},
		Amounts:      &models.Amounts{Quantity: qty},
		Pricing:      &models.Pricing{Sku: sku, MeterType: models.PricingMeterDailyUnitCharge},
		EntityDetail: &models.EntityDetail{CustomerId: cId, CostCenterDetail: &models.CostCenterDetail{EnterpriseCustomerId: cId}},
	}

	payload, _ := json.Marshal(item)
	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			Payload: payload,
		},
	}
	return rr
}
