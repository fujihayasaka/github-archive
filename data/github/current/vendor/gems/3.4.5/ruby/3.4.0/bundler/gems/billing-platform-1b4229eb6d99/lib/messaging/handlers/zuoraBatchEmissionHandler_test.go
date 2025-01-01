package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/zuora"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func TestZuoraBatchEmissionHandler_ProcessMessage(t *testing.T) {
	pegomock.RegisterMockTestingT(t)

	fakeContainer, telem, mockedStatter, mockedLogger, mockedDatabase := helpers.SetupMocks(t)

	pegomock.When(mockedDatabase.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(mockedDatabase.GetConnection()).ThenReturn(fakeContainer)
	pegomock.When(mockedDatabase.GetGatewayConnection()).ThenReturn(fakeContainer)
	pegomock.When(mockedDatabase.GetStatter()).ThenReturn(mockedStatter)

	mockedHydroPublisher := fakes.NewMockHydroPublisher()
	mockedProductEngine := fakes.NewMockProductEngineInterface()
	mockedCostCenterEngine := fakes.NewMockCostCenterEngineInterface()
	mockedDiscountEngine := fakes.NewMockDiscountEngineInterface()
	mockedCustomerEngine := fakes.NewMockCustomerEngineInterface()

	zuoraBatchPayload := setupBatchEmissionPayload()
	batchStatusItems := createMockZuoraEmissionBatchStatuses()
	batchStatusPager := helpers.MakePagerWithData(t, batchStatusItems)

	batchItems := createMockZuoraEmissionBatches("customer1")
	batchPager := helpers.MakePagerWithData(t, batchItems)

	// batchItems2 := createMockZuoraEmissionBatches("customer2")
	// batchPager2 := helpers.MakePagerWithData(t, batchItems2)

	emissionItems := createMockZuoraEmissions()
	emissionPager := helpers.MakePagerWithData(t, emissionItems)

	customerMock := createZuoraMockCustomer("customer1")

	pegomock.When(
		fakeContainer.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Eq(azcosmos.NewPartitionKeyString(batchStatusItems[0].PartitionKey)),
			pegomock.Any[*azcosmos.QueryOptions]())).
		ThenReturn(batchStatusPager)

	pegomock.When(
		fakeContainer.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Eq(azcosmos.NewPartitionKeyString(batchItems[0].PartitionKey)),
			pegomock.Any[*azcosmos.QueryOptions]())).
		ThenReturn(batchPager)

	pegomock.When(
		fakeContainer.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Eq(azcosmos.NewPartitionKeyString(emissionItems[0].PartitionKey)),
			pegomock.Any[*azcosmos.QueryOptions]())).
		ThenReturn(emissionPager)

	pegomock.When(
		fakeContainer.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Eq("customer"),
			pegomock.Any[*azcosmos.ItemOptions]())).ThenReturn(
		helpers.MockAzureItemResponse(t, customerMock), nil,
	)

	pegomock.When(mockedCustomerEngine.Get(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq("customer1"),
		pegomock.Eq(false),
	)).ThenReturn(customerMock, nil)

	// Allow upserts to succeed without writing
	pegomock.When(mockedDatabase.UpsertWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey](),
		pegomock.Any[*interfaces.QueryOptions]())).
		ThenReturn(nil)

	mockedUsageService := fakes.NewMockUsageServiceInterface()
	pegomock.When(mockedUsageService.UploadUsage(pegomock.Any[[]zuora.UploadUsageRecord]())).ThenReturn(&zuora.UploadUsageResponse{
		Success: true,
		Message: "OK",
	}, nil)

	cfg := &config.Config{}
	engineParams := engines.NewEngineParams(nil, cfg, mockedDatabase, nil, mockedStatter, nil, telem.Tracer.Tracer)

	handler := NewZuoraBatchEmissionHandler(
		&HandlerParams{
			statter: mockedStatter,
			cfg:     cfg,
		},
		engines.NewZuoraEngine(engineParams, &zuora.Client{
			UsageService: mockedUsageService,
		},
			mockedCostCenterEngine,
			nil, // Assuming InvoiceEngine is not needed, otherwise provide a mock for it
			mockedProductEngine),
		mockedHydroPublisher,
		mockedProductEngine,
		mockedCostCenterEngine,
		mockedDiscountEngine,
		mockedCustomerEngine,
	)
	// Act
	err := handler.ProcessMessage(context.Background(), mockedLogger, zuoraBatchPayload)
	assert.NoError(t, err)

}

func setupBatchEmissionPayload() aqueduct.ReceiveResult {
	mockZuoraBatchPayload := &models.ZuoraBatchEmissionPayload{
		BatchNumber: 2,
		Year:        2024,
		Month:       1,
		Day:         1,
	}

	payload, err := json.Marshal(mockZuoraBatchPayload)
	if err != nil {
		panic(err) // Handle error appropriately in real code
	}

	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{Payload: payload},
	}
	return rr
}

func createMockZuoraEmissionBatchStatuses() []*models.ZuoraEmissionBatchStatus {
	status1 := models.NewZuoraEmissionBatchStatus(2024, 1, 1, 1)
	status1.PayloadSize = 100
	status1.TotalRecordCount = 50
	status1.Status = models.BatchStatusReadyToSubmit

	status2 := models.NewZuoraEmissionBatchStatus(2024, 1, 1, 2)
	status2.PayloadSize = 100
	status2.TotalRecordCount = 50
	status2.Status = models.BatchStatusBuilding

	return []*models.ZuoraEmissionBatchStatus{status1, status2}
}

func createMockZuoraEmissionBatches(customer string) []*models.ZuoraEmissionBatch {
	if customer == "" {
		return []*models.ZuoraEmissionBatch{}
	}

	if customer == "customer1" {

		batch1 := models.NewZuoraEmissionBatch(2024, 1, 1, 2, "customer1")
		var newUploadItem1 zuora.UploadUsageRecord
		newUploadItem1.CustomerId = "customer1"
		newUploadItem1.Amount = 10.0
		newUploadItem1.UsageIdentifier = "usage1"
		newUploadItem1.CostCenter = "costcenter1"
		batch1.UploadUsageRecords = append(batch1.UploadUsageRecords, newUploadItem1)

		newUploadItem1.CustomerId = "customer1"
		newUploadItem1.Amount = 13.0
		newUploadItem1.UsageIdentifier = "usage3"
		newUploadItem1.CostCenter = "costcenter1"
		batch1.UploadUsageRecords = append(batch1.UploadUsageRecords, newUploadItem1)
		return []*models.ZuoraEmissionBatch{batch1}

	}
	if customer == "customer2" {
		batch2 := models.NewZuoraEmissionBatch(2024, 1, 1, 2, "customer2")
		var newUploadItem2 zuora.UploadUsageRecord
		newUploadItem2.CustomerId = "customer2"
		newUploadItem2.Amount = 10.0
		newUploadItem2.UsageIdentifier = "usage1"
		newUploadItem2.CostCenter = "costcenter2"
		batch2.UploadUsageRecords = append(batch2.UploadUsageRecords, newUploadItem2)

		newUploadItem2.CustomerId = "customer2"
		newUploadItem2.Amount = 13.0
		newUploadItem2.UsageIdentifier = "usage3"
		newUploadItem2.CostCenter = "costcenter2"
		batch2.UploadUsageRecords = append(batch2.UploadUsageRecords, newUploadItem2)
		return []*models.ZuoraEmissionBatch{batch2}
	}
	return []*models.ZuoraEmissionBatch{}
}

func createMockZuoraEmissions() []*models.Emission {
	return []*models.Emission{
		models.NewEmission(&models.EmissionPartitionDetail{
			CustomerId: "customer1",
			Year:       2024,
			Month:      1,
			Day:        1,
		}, nil, nil, nil),
		models.NewEmission(&models.EmissionPartitionDetail{
			CustomerId: "customer2",
			Year:       2024,
			Month:      1,
			Day:        1,
		}, nil, nil, nil),
	}
}

func createZuoraMockCustomer(customerId string) *models.Customer {
	customer := models.NewCustomer(customerId)
	customer.BillingTarget = models.Azure
	customer.Id = customerId
	return customer
}
