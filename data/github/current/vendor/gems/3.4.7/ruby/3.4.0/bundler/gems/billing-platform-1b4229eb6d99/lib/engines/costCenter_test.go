package engines

import (
	"context"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

// const testCostCenterDabaseName = "cost-center-engine-test"

type ResourceLookUpDocumentMockData struct {
	inputResource     *models.Key
	outputResourceKey *models.CostCenterKey
	outputError       error
}

type CostCenterLookupMockData struct {
	inputCostCenterKey *models.CostCenterKey
	inputCostCenter    *models.CostCenter
	outputCostCenter   *models.CostCenter
	outputError        error
}

func setupStubs(mockData []ResourceLookUpDocumentMockData, mockKeyQuerier *fakes.MockModelQuerier[*models.CostCenterKey]) {
	for _, mockDatum := range mockData {
		pegomock.When(
			mockKeyQuerier.ReadItemWithRetries(
				pegomock.Any[context.Context](),
				pegomock.Any[log.Logger](),
				pegomock.Eq(mockDatum.inputResource),
			),
		).ThenReturn(mockDatum.outputResourceKey, mockDatum.outputError)
	}
}

func setupCostCenterStubs(mockData CostCenterLookupMockData, mockModelQuerier *fakes.MockModelQuerier[*models.CostCenter], mockDb *fakes.MockDatabase) {
	pegomock.When(
		mockModelQuerier.ReadItemWithRetries(
			pegomock.Any[context.Context](),
			pegomock.Any[log.Logger](),
			pegomock.Eq(mockData.inputCostCenter.CostCenterKey),
		),
	).ThenReturn(mockData.outputCostCenter, mockData.outputError)

	pegomock.When(
		mockDb.Batch(
			pegomock.Any[context.Context](),
			pegomock.Any[models.ItemKey](),
			pegomock.Any[*interfaces.QueryOptions](),
			pegomock.Any[func(*azcosmos.TransactionalBatch) error](),
		),
	).ThenReturn(true, nil, nil)
}

func Test_FindCostCenterFor(t *testing.T) {
	testInputs := []struct {
		name             string
		entity           *models.EntityDetail
		sku              string
		mockData         []ResourceLookUpDocumentMockData
		expectedResultId string
	}{
		{ // test case 1
			name: "for any non-licensed based usage we find costcenter associated with org first",
			entity: &models.EntityDetail{
				CustomerId:     "1",
				OrganizationId: 4,
				RepositoryId:   5,
				ActorId:        123,
			},
			sku: "sku",
			mockData: []ResourceLookUpDocumentMockData{{
				inputResource: models.ToResourceLookUpKey("1", models.NewResourceWithNumericId(4, models.OwningEntity)), // org key
				outputResourceKey: &models.CostCenterKey{
					Key: &models.Key{
						PartitionKey: "customer:1:costCenters",
						Id:           "resourceLookup:owning_enity:4"},
					UUID: "uuid of cost center",
					Customer: &models.Customer{Key: &models.Key{PartitionKey: "customer:uuid_of_cost_center", Id: "customer"},
						CostCenterDetail: &models.CostCenterDetail{
							CostCenterUUID:    "uuid_of_cost_center",
							IsCostCenterProxy: true,
							CostCenterState:   models.CostCenterActive,
						}}},
				outputError: nil}},
			expectedResultId: "resourceLookup:owning_enity:4",
		},
		{ // test case 2
			name: "for any non-licensed based usage we find repo costcenter if there is no org cost center",
			entity: &models.EntityDetail{
				CustomerId:     "1",
				OrganizationId: 4,
				RepositoryId:   5,
				ActorId:        123,
			},
			sku: "sku",
			mockData: []ResourceLookUpDocumentMockData{
				{inputResource: models.ToResourceLookUpKey("1", models.NewResourceWithNumericId(4, models.OwningEntity)), // org key
					outputResourceKey: nil,
					outputError:       nil},
				{inputResource: models.ToResourceLookUpKey("1", models.NewResourceWithNumericId(5, models.Repository)), // repo key
					outputResourceKey: &models.CostCenterKey{
						Key: &models.Key{
							PartitionKey: "customer:1:costCenters",
							Id:           "resourceLookup:repository:5"},
						UUID: "uuid of cost center",
						Customer: &models.Customer{Key: &models.Key{PartitionKey: "customer:uuid_of_cost_center", Id: "customer"},
							CostCenterDetail: &models.CostCenterDetail{
								CostCenterUUID:    "uuid_of_cost_center",
								IsCostCenterProxy: true,
								CostCenterState:   models.CostCenterActive,
							}}},
					outputError: nil},
			},
			expectedResultId: "resourceLookup:repository:5",
		},
		{ // test case 3
			name: "for any licensed based usage we find costcenter associated with user",
			entity: &models.EntityDetail{
				CustomerId:     "1",
				OrganizationId: 4,
				RepositoryId:   5,
				ActorId:        123,
			},
			sku: "ghec_licenses",
			mockData: []ResourceLookUpDocumentMockData{{
				inputResource: models.ToResourceLookUpKey("1", models.NewResourceWithNumericId(4, models.OwningEntity)), // org key
				outputResourceKey: &models.CostCenterKey{
					Key: &models.Key{
						PartitionKey: "customer:1:costCenters",
						Id:           "resourceLookup:user:123"},
					UUID: "uuid of cost center",
					Customer: &models.Customer{Key: &models.Key{PartitionKey: "customer:uuid_of_cost_center", Id: "customer"},
						CostCenterDetail: &models.CostCenterDetail{
							CostCenterUUID:    "uuid_of_cost_center",
							IsCostCenterProxy: true,
							CostCenterState:   models.CostCenterActive,
						}}},
				outputError: nil}},
			expectedResultId: "resourceLookup:user:123",
		},
		{ // test case 4
			name: "for any usage do not find archived costcenter",
			entity: &models.EntityDetail{
				CustomerId:     "1",
				OrganizationId: 4,
				RepositoryId:   5,
				ActorId:        123,
			},
			sku: "sku",
			mockData: []ResourceLookUpDocumentMockData{{
				inputResource: models.ToResourceLookUpKey("1", models.NewResourceWithNumericId(4, models.OwningEntity)), // org key
				outputResourceKey: &models.CostCenterKey{
					Key: &models.Key{
						PartitionKey: "customer:1:costCenters",
						Id:           "resourceLookup:owning_enity:4"},
					UUID: "uuid of cost center",
					Customer: &models.Customer{Key: &models.Key{PartitionKey: "customer:uuid_of_cost_center", Id: "customer"},
						CostCenterDetail: &models.CostCenterDetail{
							CostCenterUUID:    "uuid_of_cost_center",
							IsCostCenterProxy: true,
							CostCenterState:   models.CostCenterArchived,
						}}},
				outputError: nil}},
			expectedResultId: "",
		},
	}

	for _, testInput := range testInputs {
		t.Run(testInput.name, func(t *testing.T) {
			// setup
			ctx := context.TODO()
			telem, _ := telemetry.NewFromEnv()

			// setup mocks
			mocker := pegomock.WithT(t)
			mockDb := fakes.NewMockDatabase(mocker)
			mockKeyQuerier := fakes.NewMockModelQuerier[*models.CostCenterKey](mocker)
			mockModelQuerier := fakes.NewMockModelQuerier[*models.CostCenter](mocker)
			pegomock.When(mockDb.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			mockPricingEngine := fakes.NewMockPricingEngineInterface()
			mockCustomerEngine := fakes.NewMockCustomerEngineInterface()
			costCenterEngine := newCostCenterEngineWithQuerier(&EngineParams{db: mockDb, tracer: telem.Tracer.Tracer}, mockKeyQuerier, mockModelQuerier, mockPricingEngine, mockCustomerEngine)

			// setup mock database
			setupStubs(testInput.mockData, mockKeyQuerier)

			skipCache := true
			pegomock.When(mockPricingEngine.IsUnitTypeUserMonths(
				ctx, telem.Logger, "ghec_licenses", skipCache,
			)).ThenReturn(true, nil)
			pegomock.When(mockPricingEngine.IsUnitTypeUserMonths(
				ctx, telem.Logger, "sku", skipCache,
			)).ThenReturn(false, nil)

			foundCostCenter, err := costCenterEngine.FindCostCenterFor(ctx, telem.Logger, testInput.entity, testInput.sku)
			assert.NoError(t, err)

			// Verification:
			inOrderContext := new(pegomock.InOrderContext)
			for _, mockDatum := range testInput.mockData {
				mockKeyQuerier.VerifyWasCalledInOrder(pegomock.Once(), inOrderContext).ReadItemWithRetries(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Eq(mockDatum.inputResource))
				if testInput.expectedResultId == "" {
					assert.Nil(t, foundCostCenter)
				} else {
					assert.Equal(t, testInput.expectedResultId, foundCostCenter.Id)
				}
			}
		})
	}
}

////////////////////////////////////////////////////
//						CostCenterEngine#Create							//
////////////////////////////////////////////////////

func Test_CostCenterEngine_Create_CreatesCostCenterWithResources(t *testing.T) {
}

func Test_CostCenterEngine_Create_WhenCostCenterInvalidReturnsError(t *testing.T) {
}

////////////////////////////////////////////////////
//						CostCenterEngine#Update							//
////////////////////////////////////////////////////

func Test_CostCenterEngine_Update_UpdatesCostCenterWithResources(t *testing.T) {
	costCenterKey := &models.CostCenterKey{
		Key: &models.Key{
			PartitionKey: "customer:1:costCenters",
			Id:           "12345"},
		UUID:     "12345",
		TargetId: "existing targetId",
		Customer: &models.Customer{Key: &models.Key{PartitionKey: "customer:1", Id: "customer"},
			CostCenterDetail: &models.CostCenterDetail{
				CostCenterUUID:    "12345",
				IsCostCenterProxy: true,
				CostCenterState:   models.CostCenterActive,
			}},
	}

	resources := []*models.Resource{{Id: "5", Type: models.User}}

	testInputs := []struct {
		testName          string
		name              string
		targetId          string
		key               *models.CostCenterKey
		resourcesToAdd    []*models.Resource
		resourcesToRemove []*models.Resource
		mockData          CostCenterLookupMockData
		expectedResult    string
	}{ // test case 1
		{
			testName:          "simple cost center update",
			name:              "updated cost center",
			targetId:          "updated targetId",
			key:               costCenterKey,
			resourcesToAdd:    resources,
			resourcesToRemove: []*models.Resource{},
			mockData: CostCenterLookupMockData{
				inputCostCenterKey: costCenterKey,
				inputCostCenter: &models.CostCenter{
					CostCenterKey: costCenterKey,
					Name:          "existing cost center",
					Resources:     []*models.Resource{},
				},
				outputCostCenter: &models.CostCenter{
					CostCenterKey: &models.CostCenterKey{
						UUID: "12345",
						Key: &models.Key{
							Id:           "12345",
							PartitionKey: "customer:1:costCenters",
						},
						TargetId: "updated targetId",
						Customer: &models.Customer{Key: &models.Key{PartitionKey: "customer:1", Id: "customer"},
							CostCenterDetail: &models.CostCenterDetail{
								CostCenterUUID:    "12345",
								IsCostCenterProxy: true,
								CostCenterState:   models.CostCenterActive,
							}},
					},
					Name:      "updated cost center",
					Resources: resources,
				},
			},
			expectedResult: "updated cost center",
		},
	}

	for _, testInput := range testInputs {
		t.Run(testInput.testName, func(t *testing.T) {
			// setup
			ctx := context.TODO()
			telem, _ := telemetry.NewFromEnv()

			// setup mocks
			mocker := pegomock.WithT(t)
			mockDb := fakes.NewMockDatabase(mocker)
			mockKeyQuerier := fakes.NewMockModelQuerier[*models.CostCenterKey](mocker)
			mockModelQuerier := fakes.NewMockModelQuerier[*models.CostCenter](mocker)
			pegomock.When(mockDb.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			mockPricingEngine := fakes.NewMockPricingEngineInterface()
			mockCustomerEngine := fakes.NewMockCustomerEngineInterface()
			costCenterEngine := newCostCenterEngineWithQuerier(&EngineParams{db: mockDb, tracer: telem.Tracer.Tracer}, mockKeyQuerier, mockModelQuerier, mockPricingEngine, mockCustomerEngine)

			// setup mock database
			setupCostCenterStubs(testInput.mockData, mockModelQuerier, mockDb)

			updatedCostCenter, err := costCenterEngine.Update(ctx, telem.Logger, testInput.key, testInput.name, testInput.targetId, testInput.resourcesToAdd, testInput.resourcesToRemove, false)
			assert.NoError(t, err)

			// Verification:
			inOrderContext := new(pegomock.InOrderContext)
			mockModelQuerier.VerifyWasCalledInOrder(pegomock.Once(), inOrderContext).ReadItemWithRetries(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Eq(testInput.mockData.inputCostCenterKey))
			assert.Equal(t, testInput.expectedResult, updatedCostCenter.Name)
			assert.Equal(t, updatedCostCenter.Resources[0].Id, "5")
		})
	}
}

func Test_CostCenterEngine_Update_WhenCostCenterInvalidReturnsError(t *testing.T) {
}

//////////////////////////////////////////////////////////////////////
//						CostCenterEngine#updateCostCenterBillingTarget				//
//////////////////////////////////////////////////////////////////////

func Test_CostCenterEngine_updateCostCenterBillingTarget(t *testing.T) {

	ctx := context.TODO()
	telem, _ := telemetry.NewFromEnv()

	// setup mocks
	mocker := pegomock.WithT(t)
	mockDb := fakes.NewMockDatabase(mocker)
	mockKeyQuerier := fakes.NewMockModelQuerier[*models.CostCenterKey](mocker)
	mockModelQuerier := fakes.NewMockModelQuerier[*models.CostCenter](mocker)
	pegomock.When(mockDb.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	mockPricingEngine := fakes.NewMockPricingEngineInterface()
	mockCustomerEngine := fakes.NewMockCustomerEngineInterface()
	costCenterEngine := &CostCenterEngine{&EngineParams{db: mockDb, tracer: telem.Tracer.Tracer}, mockKeyQuerier, mockModelQuerier, mockPricingEngine, mockCustomerEngine}

	costCenter := &models.CostCenter{
		CostCenterKey: &models.CostCenterKey{
			Key: &models.Key{
				PartitionKey: "customer:1:costCenters",
				Id:           "12345"},
			UUID:       "CC12345",
			TargetType: models.AzureSubscription,
			TargetId:   "an azure targetId",
		},
		Name: "cost center 1",
	}

	enterprise := &models.Customer{
		Key:           &models.Key{PartitionKey: "customer:1", Id: "customer"},
		BillingTarget: models.Zuora,
	}

	expectedPatchOperations := azcosmos.PatchOperations{}
	expectedPatchOperations.AppendAdd("/TargetType", models.ZuoraSubscription)
	expectedPatchOperations.AppendAdd("/TargetId", "")
	expectedPatchOperations.AppendAdd("/Customer/BillingTarget", models.Zuora)

	pegomock.When(mockDb.PatchWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey](),
		pegomock.Any[azcosmos.PatchOperations](),
		pegomock.Any[*interfaces.QueryOptions](),
	)).ThenReturn(nil)

	err := costCenterEngine.updateCostCenterBillingTarget(ctx, telem.Logger, costCenter, enterprise)
	assert.NoError(t, err)

	// Verify
	mockDb.VerifyWasCalledOnce().PatchWithOptions(
		ctx,
		telem.Logger,
		costCenter,
		expectedPatchOperations,
		nil,
	)

}

func Test_CostCenterEngine_updateCostCenterCustomerBillingTarget(t *testing.T) {

	ctx := context.TODO()
	telem, _ := telemetry.NewFromEnv()

	// setup mocks
	mocker := pegomock.WithT(t)
	mockDb := fakes.NewMockDatabase(mocker)
	mockKeyQuerier := fakes.NewMockModelQuerier[*models.CostCenterKey](mocker)
	mockModelQuerier := fakes.NewMockModelQuerier[*models.CostCenter](mocker)
	pegomock.When(mockDb.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	mockPricingEngine := fakes.NewMockPricingEngineInterface()
	mockCustomerEngine := fakes.NewMockCustomerEngineInterface()
	costCenterEngine := &CostCenterEngine{&EngineParams{db: mockDb, tracer: telem.Tracer.Tracer}, mockKeyQuerier, mockModelQuerier, mockPricingEngine, mockCustomerEngine}

	costCenter := &models.CostCenter{
		CostCenterKey: &models.CostCenterKey{
			Key: &models.Key{
				PartitionKey: "customer:1:costCenters",
				Id:           "CC12345"},
			UUID:       "CC12345",
			TargetType: models.AzureSubscription,
			TargetId:   "an azure targetId",
		},
		Name: "cost center 1",
	}

	costCenterCustomer := &models.Customer{
		Key:           &models.Key{PartitionKey: "customer:CC12345", Id: "customer"},
		BillingTarget: models.Azure,
		CostCenterDetail: &models.CostCenterDetail{
			IsCostCenterProxy: true,
		},
	}

	enterprise := &models.Customer{
		Key:           &models.Key{PartitionKey: "customer:1", Id: "customer"},
		BillingTarget: models.Zuora,
	}

	pegomock.When(mockCustomerEngine.Get(ctx, telem.Logger, "CC12345", false)).ThenReturn(costCenterCustomer, nil)
	pegomock.When(mockDb.PatchWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey](),
		pegomock.Any[azcosmos.PatchOperations](),
		pegomock.Any[*interfaces.QueryOptions](),
	)).ThenReturn(nil)
	err := costCenterEngine.updateCostCenterCustomerBillingTarget(ctx, telem.Logger, costCenter, enterprise)
	assert.NoError(t, err)

	expectedPatchOperations := azcosmos.PatchOperations{}
	expectedPatchOperations.AppendAdd("/BillingTarget", models.Zuora)
	// Verify
	mockDb.VerifyWasCalledOnce().PatchWithOptions(
		ctx,
		telem.Logger,
		costCenterCustomer,
		expectedPatchOperations,
		nil,
	)

}

func Test_CostCenterEngine_updateCostCenterResourcesTarget(t *testing.T) {
	ctx := context.TODO()
	telem, _ := telemetry.NewFromEnv()

	// setup mocks
	mocker := pegomock.WithT(t)
	mockDb := fakes.NewMockDatabase(mocker)
	mockKeyQuerier := fakes.NewMockModelQuerier[*models.CostCenterKey](mocker)
	mockModelQuerier := fakes.NewMockModelQuerier[*models.CostCenter](mocker)
	pegomock.When(mockDb.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	mockPricingEngine := fakes.NewMockPricingEngineInterface()
	mockCustomerEngine := fakes.NewMockCustomerEngineInterface()
	costCenterEngine := &CostCenterEngine{&EngineParams{db: mockDb, tracer: telem.Tracer.Tracer}, mockKeyQuerier, mockModelQuerier, mockPricingEngine, mockCustomerEngine}

	enterprise := &models.Customer{
		Key:           &models.Key{PartitionKey: "customer:1", Id: "customer"},
		BillingTarget: models.Zuora,
	}

	repoResource := &models.Resource{
		Id:   "1",
		Type: models.Repository,
	}

	orgResource := &models.Resource{
		Id:   "2",
		Type: models.OwningEntity,
	}

	costCenter := &models.CostCenter{
		CostCenterKey: &models.CostCenterKey{
			Key: &models.Key{
				PartitionKey: "customer:1:costCenters",
				Id:           "CC12345"},
			Customer: &models.Customer{
				Key: &models.Key{
					PartitionKey: "customer:1",
					Id:           "customer",
				},
				CostCenterDetail: &models.CostCenterDetail{
					IsCostCenterProxy:    false,
					EnterpriseCustomerId: "1",
					CostCenterState:      models.CostCenterActive,
				},
				BillingTarget: models.Zuora,
			},
			UUID:       "CC12345",
			TargetType: models.AzureSubscription,
			TargetId:   "an azure targetId",
		},
		Name: "cost center 1",
		Resources: []*models.Resource{
			repoResource,
			orgResource,
		},
	}

	err := costCenterEngine.updateCostCenterResourcesTarget(ctx, telem.Logger, costCenter, enterprise)
	assert.NoError(t, err)

	expectedPatchOperations := azcosmos.PatchOperations{}
	expectedPatchOperations.AppendAdd("/TargetType", models.ZuoraSubscription)
	expectedPatchOperations.AppendAdd("/TargetId", "")
	expectedPatchOperations.AppendAdd("/Customer/BillingTarget", models.Zuora)

	// Verify

	mockDb.VerifyWasCalledOnce().PatchWithOptions(
		ctx,
		telem.Logger,
		costCenter.AsResourceLookup(repoResource),
		expectedPatchOperations,
		nil,
	)

	mockDb.VerifyWasCalledOnce().PatchWithOptions(
		ctx,
		telem.Logger,
		costCenter.AsResourceLookup(orgResource),
		expectedPatchOperations,
		nil,
	)

}
