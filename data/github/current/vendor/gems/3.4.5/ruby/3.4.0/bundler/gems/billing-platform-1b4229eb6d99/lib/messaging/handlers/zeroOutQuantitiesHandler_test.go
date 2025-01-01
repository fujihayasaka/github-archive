package handlers

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydro_schemas_billingplatform_v1 "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydro_schemas_billingplatform_v1_entities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	schemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	protobuf "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestNewZeroOutQuantitiesHandler_InitializedWithCorrectQueueName(t *testing.T) {
	handlerParams := &HandlerParams{}
	zoQh := NewZeroOutQuantitiesHandler(handlerParams, nil)
	assert.NotNil(t, zoQh)
	assert.Equal(t, zoQh.queueName, "zero-out-quantities-handler")
}

func TestZeroOutQuantitiesHandler_ProcessMessage_ErrorOnEmptyPayload(t *testing.T) {
	zoQh := NewZeroOutQuantitiesHandler(&HandlerParams{}, nil)
	err := zoQh.ProcessMessage(context.Background(), nil, aqueduct.ReceiveResult{})
	assert.Error(t, err)
	assert.Equal(t, err.Error(), "failed to unmarshal zero-out-quanities job run: unexpected end of JSON input")
}

func TestZeroOutQuantitiesHandler_ProcessMessage_ErrorOnInvalidPayload(t *testing.T) {
	zoQh := NewZeroOutQuantitiesHandler(&HandlerParams{}, nil)
	err := zoQh.ProcessMessage(context.Background(), nil, aqueduct.ReceiveResult{Job: aqueduct.Job{Payload: []byte("invalid json")}})
	assert.Error(t, err)
	assert.Equal(t, err.Error(), "failed to unmarshal zero-out-quanities job run: invalid character 'i' looking for beginning of value")
}

func TestZeroOutQuantitiesHandler_ProcessMessage_PassWithNoResultsForCustomer(t *testing.T) {
	// Setup
	// Sets up the pager to return no results
	pager := helpers.MakePagerWithData(t, []*models.Item{})
	// Mocks
	fakeContainer, telem, statter, logger, db := helpers.SetupMocks(t)
	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
	pegomock.When(db.GetStatter()).ThenReturn(statter)
	pegomock.When(fakeContainer.NewQueryItemsPager(pegomock.Any[string](), pegomock.Any[azcosmos.PartitionKey](), pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	params := engines.NewEngineParams(nil, nil, db, nil, statter, nil, telem.Tracer.Tracer)
	usageEngine := engines.NewUsageEngine(params)

	// Test
	zoQh := NewZeroOutQuantitiesHandler(&HandlerParams{
		statter: statter,
	}, usageEngine)

	err := zoQh.ProcessMessage(context.Background(), logger, aqueduct.ReceiveResult{Job: aqueduct.Job{Payload: []byte(`{"customerId": "123"}`)}})
	assert.NoError(t, err)
}

func TestZeroOutQuantitiesHandler_ProcessMessage_WithResults(t *testing.T) {
	// Setup
	items := make([]*models.Item, 0)
	now := models.UTCNow()
	modelItem := &models.Item{
		Amounts:      &models.Amounts{Quantity: 3},
		Pricing:      &models.Pricing{Sku: "sku1"},
		EntityDetail: &models.EntityDetail{CustomerId: "123"},
		SourceUri:    "backfill",
	}
	items = append(items, modelItem)
	pager := helpers.MakePagerWithData(t, items)
	payloadWithMonthAndYear := []byte(`{"customerId": "123", "sku":"sku1", "year":"2023", "month":"12"}`)

	yesterday := now.WithDay(now.Day() - 1)
	expectedUsageId := fmt.Sprintf("123:0:0:%d:%d:%d:%d", yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour())
	expectedPartitionKey := azcosmos.NewPartitionKeyString("123:sku1:events:2023:12")
	expectededHydroEvent := &hydro_schemas_billingplatform_v1.Usage{
		Sku:       "sku1",
		Quantity:  -0.000000003,
		SourceUri: "backfill",
		UsageAt:   &timestamppb.Timestamp{Seconds: yesterday.Unix(), Nanos: int32(yesterday.Nanosecond())},
		Entity: &hydro_schemas_billingplatform_v1_entities.EntityDetail{
			CustomerId: 123,
		},
		UsageUuid: expectedUsageId,
	}

	// Mocks
	fakeContainer, telem, statter, logger, db := helpers.SetupMocks(t)

	aqueductClient := &fakes.MockAqueductClient{}

	pegomock.RegisterMockTestingT(t)
	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
	pegomock.When(db.GetStatter()).ThenReturn(statter)
	pegomock.When(fakeContainer.NewQueryItemsPager(pegomock.Any[string](), pegomock.Any[azcosmos.PartitionKey](), pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	cfg := &config.Config{
		Environment: "test",
	}
	params := engines.NewEngineParams(aqueductClient, cfg, db, nil, statter, nil, telem.Tracer.Tracer)
	usageEngine := engines.NewUsageEngine(params)

	// Test
	zoQh := NewZeroOutQuantitiesHandler(&HandlerParams{
		statter:        statter,
		cfg:            cfg,
		aqueductClient: aqueductClient,
	}, usageEngine)
	err := zoQh.ProcessMessage(context.Background(), logger, aqueduct.ReceiveResult{Job: aqueduct.Job{Payload: payloadWithMonthAndYear}})
	assert.NoError(t, err)

	// Inspect the hydro event that was sent to aqueduct
	_, actualPK, _ := fakeContainer.VerifyWasCalled(pegomock.Times(1)).NewQueryItemsPager(pegomock.Any[string](), pegomock.Any[azcosmos.PartitionKey](), pegomock.Any[*azcosmos.QueryOptions]()).GetCapturedArguments()
	assert.Equal(t, expectedPartitionKey, actualPK)

	InspectAqueductSend(t, aqueductClient, expectededHydroEvent)
}

func InspectAqueductSend(t *testing.T, acqueductClient *fakes.MockAqueductClient, expectedHydtoEvent *hydro_schemas_billingplatform_v1.Usage) {
	usageAsBytes, err := protobuf.Marshal(expectedHydtoEvent)
	assert.NoError(t, err)
	envelope := schemas.Envelope{
		Message: usageAsBytes,
	}
	envAsBytes, err := protobuf.Marshal(&envelope)
	assert.NoError(t, err)
	ExpectedJob := aqueduct.Job{
		Payload: envAsBytes,
		App:     "billing-platform-development",
		Queue:   "hydro_billingplatform_v1_usage",
	}

	_, actualJob, _ := acqueductClient.VerifyWasCalled(pegomock.Times(1)).Send(pegomock.Any[context.Context](), pegomock.Any[aqueduct.Job](), pegomock.Any[aqueduct.SendOption]()).GetCapturedArguments()

	var actualEnv schemas.Envelope
	err = protobuf.Unmarshal(actualJob.Payload, &actualEnv)
	assert.NoError(t, err)
	var actualJobBytes hydro_schemas_billingplatform_v1.Usage
	err = protobuf.Unmarshal(actualEnv.Message, &actualJobBytes)
	assert.NoError(t, err)

	assert.Equal(t, ExpectedJob.Queue, actualJob.Queue)
	assert.Equal(t, expectedHydtoEvent.Quantity, actualJobBytes.Quantity)
	assert.Equal(t, expectedHydtoEvent.Sku, actualJobBytes.Sku)
	assert.Equal(t, expectedHydtoEvent.UsageUuid, actualJobBytes.UsageUuid)
	assert.True(t, helpers.WithinTimeUsageAt(expectedHydtoEvent, &actualJobBytes, time.Second))
}
