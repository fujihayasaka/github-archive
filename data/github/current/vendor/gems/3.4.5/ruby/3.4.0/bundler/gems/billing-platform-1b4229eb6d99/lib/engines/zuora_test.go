package engines

import (
	"context"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/zuora"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
)

type TestEmissionObject struct {
	ZuoraEngine           *ZuoraEngine
	mocker                pegomock.Option
	zuoraClient           *zuora.Client
	emissionQuerier       *fakes.MockQuerier[*models.Emission]
	CostCenterEngine      CostCenterEngineInterface
	InvoiceEngine         *InvoiceEngine
	ProductEngine         ProductEngineInterface
	emissionStatusQuerier *fakes.MockQuerier[*models.ZuoraEmissionBatchStatus]
	emissionBatchQuerier  *fakes.MockQuerier[*models.ZuoraEmissionBatch]
	db                    *fakes.MockDatabase
}

func InitializeEmissionTestObject(t *testing.T) TestEmissionObject {
	t.Helper()
	mocker := pegomock.WithT(t)
	zuoraClient := &zuora.Client{}
	emissionQuerier := fakes.NewMockQuerier[*models.Emission](mocker)
	pricingQuerier := fakes.NewMockQuerier[*models.Pricing](mocker)
	gatewayPricingQuerier := fakes.NewMockQuerier[*models.Pricing](mocker)
	emissionStatusQuerier := fakes.NewMockQuerier[*models.ZuoraEmissionBatchStatus](mocker)
	emissionBatchQuerier := fakes.NewMockQuerier[*models.ZuoraEmissionBatch](mocker)

	mockDB := fakes.NewMockDatabase(mocker)
	aqueductClient := &fakes.MockAqueductClient{}
	_, _, stats, _, _ := helpers.SetupMocks(t)

	cfg := &config.Config{
		Environment: "test",
	}

	engineParams := &EngineParams{
		db:             mockDB,
		cfg:            cfg,
		aqueductClient: aqueductClient,
		statter:        stats,
	}

	pricingEngine := NewPricingEngineWithQuerier(engineParams, pricingQuerier, gatewayPricingQuerier)
	customerEngine := NewCustomerEngine(engineParams)

	costCenterEngine := NewCostCenterEngine(engineParams, pricingEngine, customerEngine)

	testObject := newZuoraEngineWithQuerier(engineParams,
		zuoraClient,
		costCenterEngine,
		&InvoiceEngine{},
		&ProductEngine{},
		emissionQuerier,
		emissionStatusQuerier,
		emissionBatchQuerier,
	)
	return TestEmissionObject{
		ZuoraEngine:           testObject,
		mocker:                mocker,
		zuoraClient:           zuoraClient,
		emissionQuerier:       emissionQuerier,
		CostCenterEngine:      costCenterEngine,
		InvoiceEngine:         &InvoiceEngine{},
		ProductEngine:         &ProductEngine{},
		emissionStatusQuerier: emissionStatusQuerier,
		emissionBatchQuerier:  emissionBatchQuerier,
		db:                    mockDB,
	}
}

func TestCreateZuoraBatch(t *testing.T) {
	pegomock.RegisterMockTestingT(t)

	TestEmissionObject := InitializeEmissionTestObject(t)
	customer := createMockCustomer("100", models.Zuora)

	mockUploadUsageRecords, mockBatchStatusRecords := setupMockDataCreateZuoraBatch()

	testCases := []struct {
		name          string
		setupMocks    func()
		expectedError bool
	}{
		{
			name: "Successfully creates zuora batch",
			setupMocks: func() {
				// Setup successful query
				pegomock.When(TestEmissionObject.emissionStatusQuerier.QueryItems(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[string](),
					pegomock.Any[string](),
				)).ThenReturn(mockBatchStatusRecords, nil)

				// Setup successful creates
				pegomock.When(TestEmissionObject.db.CreateWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Any[*interfaces.QueryOptions](),
				)).ThenReturn(nil)

				// Setup successful patches
				pegomock.When(TestEmissionObject.db.PatchWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Any[azcosmos.PatchOperations](),
					pegomock.Any[*interfaces.QueryOptions](),
				)).ThenReturn(nil)
			},
			expectedError: false,
		},
		{
			name: "Returns error when database operation fails",
			setupMocks: func() {
				pegomock.When(TestEmissionObject.emissionStatusQuerier.QueryItems(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[string](),
					pegomock.Any[string](),
				)).ThenReturn(nil, errors.New("database error"))
			},
			expectedError: true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Register test context for each test case
			pegomock.RegisterMockTestingT(t)

			// Create fresh test object with new mocks for each test
			TestEmissionObject = InitializeEmissionTestObject(t)

			tc.setupMocks()

			testTime := models.NewUsageTime().
				WithYear(2024).
				WithMonthInt(1).
				WithDay(1)

			err := TestEmissionObject.ZuoraEngine.createZuoraBatch(
				context.Background(),
				log.NewNullLogger(),
				*testTime,
				customer,
				mockUploadUsageRecords,
			)

			if tc.expectedError {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func createMockCustomer(customerId string, target models.BillingTarget) *models.Customer {
	customer := models.NewCustomer(customerId)
	customer.BillingTarget = target
	customer.ZuoraAccountNumber = stubs.GetRandomId64AsString()
	customer.EnabledProducts = []string{"copilot, actions, ghec"}
	return customer
}

func setupMockDataCreateZuoraBatch() ([]zuora.UploadUsageRecord, []*models.ZuoraEmissionBatchStatus) {
	mockUploadUsageRecords := []zuora.UploadUsageRecord{
		{
			CustomerId:      "100",
			UsageIdentifier: "GHES",
			UsageDate:       zuora.ZuoraUsageDateTime{},
			Amount:          999.00,
			CostCenter:      "100",
		},
		{
			CustomerId:      "100",
			UsageIdentifier: "XGHES",
			UsageDate:       zuora.ZuoraUsageDateTime{},
			Amount:          1999.00,
			CostCenter:      "100",
		},
	}

	mockBatchStatusRecords := []*models.ZuoraEmissionBatchStatus{
		{
			Key: &models.Key{
				PartitionKey: "zuoraEmissionBatchStatus:2024:8:2",
				Id:           "zuoraEmissionBatchStatus:2024:8:2:1",
			},
			BatchNumber:      1,
			Status:           models.BatchStatusBuilding,
			PayloadSize:      233,
			TotalRecordCount: 30400,
		},
		{
			Key: &models.Key{
				PartitionKey: "zuoraEmissionBatchStatus:2024:8:2",
				Id:           "zuoraEmissionBatchStatus:2024:8:2:2",
			},
			BatchNumber:      2,
			Status:           models.BatchStatusReadyToSubmit,
			PayloadSize:      234,
			TotalRecordCount: 30500,
		},
		{
			Key: &models.Key{
				PartitionKey: "zuoraEmissionBatchStatus:2024:8:2",
				Id:           "zuoraEmissionBatchStatus:2024:8:2:3",
			},
			BatchNumber:      3,
			Status:           models.BatchStatusReadyToSubmit,
			PayloadSize:      235,
			TotalRecordCount: 30600,
		},
	}

	return mockUploadUsageRecords, mockBatchStatusRecords
}
