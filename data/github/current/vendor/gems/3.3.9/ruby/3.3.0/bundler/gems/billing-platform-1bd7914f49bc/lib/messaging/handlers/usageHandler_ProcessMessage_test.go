package handlers

import (
	"bytes"
	"context"
	"fmt"
	stdlog "log"
	"net/http"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	azRuntime "github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydro_schemas_billingplatform_v1 "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydro_schemas_billingplatform_v1_entities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/github/github-telemetry-go/log"
	hydro_schemas_hydro_v1 "github.com/github/hydro-client-go/v5/generated/hydro/schemas/hydro/v1"
	"github.com/github/hydro-client-go/v5/pkg/hydro"
	protobuf "github.com/golang/protobuf/proto" //nolint:staticcheck
	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func TestUsageHandler_ProcessMessage_InvalidLoadItem(t *testing.T) {
	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			Payload: []byte(`{"id": "123"}`),
		},
	}
	logger, handlerParams, _ := mocksWithBasicCostCenter(t)
	handler := NewUsageHandler(handlerParams, nil, nil, nil, nil, nil, nil, nil, nil)

	err := handler.ProcessMessage(context.Background(), logger, rr)
	assert.ErrorContains(t, err, "cannot parse invalid wire-format data")
}

func TestUsageHandler_ProcessMessage_CustomerIdZero(t *testing.T) {
	now := models.UTCNow()
	rr := setupRecvPayload("sku1", 100, 0, "", now)
	logger, mdb, _, handler := setupHandler(t, mockWithStaticCostCenterPricingCustomerIdZero, "resourceLookup:enterprise:0", "sku1", "customer")
	CreateWithOptionsDelay(mdb, 200*time.Millisecond, nil)

	// Test
	err := handler.ProcessMessage(context.Background(), logger, rr)

	// Assert
	assert.NoError(t, err)
	assert.NoError(t, handler.ProcessJobError)
	assert.NoError(t, handler.ProcessJobError)
}

func TestUsageHandler_ProcessMessage_UsageItemExists(t *testing.T) {
	now := models.UTCNow()
	customerId := int64(15)
	rr := setupRecvPayload("actions_storage", 100, 15, "uuid", now)
	logger, mdb, fakeContainer, handler := setupHandler(t, emptyMock, "", "", "")

	pricingResponse := helpers.TestCustomPricing(t, "actions", "actions_storage", 100, time.Now().Add(-time.Hour).Unix())
	mockReadItemWith(fakeContainer, "", "actions_storage", pricingResponse, nil)

	customerResponse := helpers.TestCustomerReadItemResponse(t, customerId, "actions")
	mockReadItemWith(fakeContainer, fmt.Sprintf("customer:%d", customerId), "customer", customerResponse, nil)

	tooManyRequestsErr := &azcore.ResponseError{StatusCode: 429}
	key := &models.Key{
		PartitionKey: "uuid",
		Id:           "billable",
	}
	pegomock.When(mdb.Exists(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq[models.ItemKey](key),
		pegomock.Any[*interfaces.QueryOptions]())).
		ThenReturn(
			true, tooManyRequestsErr,
		)

	err := handler.ProcessMessage(context.Background(), logger, rr)

	assert.Error(t, err)
	assert.Equal(t, err, tooManyRequestsErr)
}

type BudgetTestData struct {
	name              string
	discountAmount    float64
	quantity          float64
	product           string
	sku               string
	skuPrice          float64
	fullyFunded       bool
	expectedAmount    float64
	budgetTarget      float64
	thresholdMetUsage float64
}

func TestUsageHandler_ProcessMessage_BudgetState(t *testing.T) {
	t.Parallel()

	tests := []BudgetTestData{
		{
			name:              "Budget is fully funded",
			quantity:          10,
			product:           "actions",
			sku:               "actions_macos_xl", // sku without plan discount
			skuPrice:          1,
			fullyFunded:       true,
			expectedAmount:    10,
			budgetTarget:      10,
			thresholdMetUsage: 100,
		},
		{
			name:              "Budget is fully not yet fully funded",
			quantity:          1,
			product:           "actions",
			sku:               "actions_macos_xl", // sku without plan discount
			skuPrice:          1,
			fullyFunded:       false,
			expectedAmount:    1,
			budgetTarget:      10,
			thresholdMetUsage: 0,
		},
		{
			name:              "Budget is funded and usage continues",
			quantity:          25,
			product:           "actions",
			sku:               "actions_macos_xl", // sku without plan discount
			skuPrice:          1,
			fullyFunded:       true,
			expectedAmount:    25,
			budgetTarget:      10,
			thresholdMetUsage: 100,
		},
		{
			name:              "Budget is accurate with decimal usage",
			quantity:          4.56735,
			product:           "actions",
			sku:               "actions_macos_xl", // sku without plan discount
			skuPrice:          13.7464,
			fullyFunded:       true,
			expectedAmount:    62.78462004,
			budgetTarget:      10,
			thresholdMetUsage: 100,
		},
		{
			name:              "Budget is over 75% used",
			quantity:          78,
			product:           "actions",
			sku:               "actions_macos_xl", // sku without plan discount
			skuPrice:          1,
			fullyFunded:       false,
			expectedAmount:    78,
			budgetTarget:      100,
			thresholdMetUsage: 75,
		},
		{
			name:              "Budget is over 90% used",
			quantity:          93,
			product:           "actions",
			sku:               "actions_macos_xl", // sku without plan discount
			skuPrice:          1,
			fullyFunded:       false,
			expectedAmount:    93,
			budgetTarget:      100,
			thresholdMetUsage: 90,
		},
		{
			name:              "Budget is not funded while entitlement is applied for applicable sku",
			discountAmount:    400,
			quantity:          400, // $400 goes to plan discount
			product:           "actions",
			sku:               "actions_linux", // sku with plan discount
			skuPrice:          1,
			fullyFunded:       false,
			expectedAmount:    0,
			budgetTarget:      10,
			thresholdMetUsage: 0,
		},
		{
			name:              "Budget is funded past plan discount for applicable sku",
			discountAmount:    400,
			quantity:          409, // $400 to plan discount + 9 billed usage
			product:           "actions",
			sku:               "actions_linux", // sku with plan discount
			skuPrice:          1.0,
			fullyFunded:       false,
			expectedAmount:    9,
			budgetTarget:      10,
			thresholdMetUsage: 90,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			testBudget(t, tt, 451, 451, models.CustomerResource)
		})
	}
}

func TestUsageHandler_ProcessMessage_BudgetType_State(t *testing.T) {
	tt := BudgetTestData{
		name:              "Budget is fully funded",
		quantity:          10,
		product:           "actions",
		sku:               "actions_linux_32_core", // sku without plan discount
		skuPrice:          1,
		fullyFunded:       true,
		expectedAmount:    10,
		budgetTarget:      10,
		thresholdMetUsage: 100,
	}

	budgetTargets := []struct {
		targetId   int64
		targetType models.ResourceType
	}{
		{
			targetId:   int64(stubs.GetRandomId()),
			targetType: models.Enterprise,
		},
		{
			targetId:   int64(stubs.GetRandomId()),
			targetType: models.OwningEntity,
		},
		{
			targetId:   int64(stubs.GetRandomId()),
			targetType: models.Repository,
		},
		{
			targetId:   int64(stubs.GetRandomId()),
			targetType: models.User,
		},
	}

	for _, budgetTarget := range budgetTargets {
		t.Run(fmt.Sprintf("%s_%s", tt.name, budgetTarget.targetType), func(t *testing.T) {
			testBudget(t, tt, int64(stubs.GetRandomId()), budgetTarget.targetId, budgetTarget.targetType)
		})
	}
}

func testBudget(t *testing.T, params BudgetTestData, customerId int64, targetId int64, targetType models.ResourceType) {
	now := models.UTCNow()
	rr := setupRecvPayload(params.sku, params.quantity, customerId, "", now)

	pegomock.RegisterMockTestingT(t)

	logger, db, fakeContainer, handler := setupHandler(t, emptyMock, "", "", "")

	mockCommonEntities(t, fakeContainer, customerId)

	pricingResponse := helpers.TestCustomPricing(t, params.product, params.sku, params.skuPrice, time.Now().Add(-time.Hour).Unix())
	mockReadItemWith(fakeContainer, "", params.sku, pricingResponse, nil)

	customerResponse := helpers.TestCustomerReadItemResponse(t, customerId, params.product)
	mockReadItemWith(fakeContainer, fmt.Sprintf("customer:%d", customerId), "customer", customerResponse, nil)

	discountState, discountStateResponse := helpers.TestDiscountStateReadItemResponse(t, customerId, params.discountAmount, "123")
	mockReadItemWith(fakeContainer, "", discountState.PartitionKey, discountStateResponse, nil)

	budget, budgetResponse := helpers.TestBudgetReadItemResponse(t, customerId, params.product, targetId, targetType, params.budgetTarget, "12345")
	mockReadItemWith(fakeContainer, budget.PartitionKey, budget.Id, budgetResponse, nil)

	budgetState, budgetStateResponse := helpers.TestBudgetStateReadItemResponse(t, customerId, now, params.budgetTarget)
	mockReadItemWith(fakeContainer, budgetState.PartitionKey, "budgetState", budgetStateResponse, nil)

	// make fake budget data
	pager := helpers.MakePagerWithData(t, []*models.Budget{budget})

	pegomock.When(
		fakeContainer.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	err := handler.ProcessMessage(context.Background(), logger, rr)
	assert.NoError(t, err)

	_, _, budgetStateInterface, _ := db.VerifyWasCalledOnce().UpsertWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.BudgetState](),
		pegomock.Any[*interfaces.QueryOptions]()).GetCapturedArguments()
	budgetStateActual := budgetStateInterface.(*models.BudgetState)

	assert.Equal(t, params.fullyFunded, budgetStateActual.IsFullyFunded)
	assert.Equal(t, models.ToWholeAmount[uint64](params.expectedAmount), budgetStateActual.CurrentAmount)
	assert.Equal(t, uint64(params.thresholdMetUsage), budgetStateActual.ThresholdMet.MinimumUsagePercentage)
}

func TestUsageHandler_ProcessMessage_NonWatermarkEvent(t *testing.T) {
	rr := setupRecvPayload("", 0, 451, "", models.UTCNow())
	logger, mdb, _, handler := setupHandler(
		t,
		mockWithStaticCostCenterPricingCustomer,
		"resourceLookup:enterprise:451", "sku1", "customer")

	CreateWithOptionsDelay(mdb, 200*time.Millisecond, nil)

	// Test
	err := handler.ProcessMessage(context.Background(), logger, rr)

	// Assert
	assert.NoError(t, err)
	assert.NoError(t, handler.ProcessJobError)
	_, _, actualItem, _ := mdb.VerifyWasCalledOnce().CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey](),
		pegomock.Any[*interfaces.QueryOptions]()).GetCapturedArguments()
	assert.Equal(t, "billable", actualItem.GetKey().Id)

	_, _, nopricingItemKey := mdb.VerifyWasCalledOnce().CreateIfNotExists(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey]()).GetCapturedArguments()
	assert.Equal(t, "no-pricing", nopricingItemKey.GetKey().Id)
}

func TestUsageHandler_ProcessMessage_NonWatermarkEvent_WithPricing(t *testing.T) {
	rr := setupRecvPayload("sku1", 100, 452, "", models.UTCNow())
	logger, mdb, _, handler := setupHandler(t, mockWithStaticCostCenterPricingCustomer, "resourceLookup:enterprise:452", "sku1", "customer")

	// Test
	err := handler.ProcessMessage(context.Background(), logger, rr)

	// Assert
	assert.NoError(t, err)
	assert.NoError(t, handler.ProcessJobError)
	_, _, actualItem, _ := mdb.VerifyWasCalled(pegomock.Once()).CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey](),
		pegomock.Any[*interfaces.QueryOptions]()).GetCapturedArguments()
	assert.Equal(t, "billable", actualItem.GetKey().Id)
	assert.Equal(t, int64(500), actualItem.(*models.Item).BilledAmount)
	assert.Equal(t, int64(5), actualItem.(*models.Item).AppliedCostPerQuantity)
	assert.Equal(t, int64(5), actualItem.(*models.Item).GetPrice())
	mdb.VerifyWasCalled(pegomock.Never()).CreateIfNotExists(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey]())
}

func TestUsageHandler_ProcessMessage_HighWatermarkEvent_WithPricingNotEnabledForEmission(t *testing.T) {
	rr := setupRecvPayload("ghec_seats", 100, 453, "", models.UTCNow())
	// mockForHighWaterMark only has ghec enabled
	logger, _, _, handler := setupHandler(t, mockForHighWaterMark, "resourceLookup:enterprise:453", "ghec_seats", "customer")

	// Test
	err := handler.ProcessMessage(context.Background(), logger, rr)

	// Assert
	assert.Error(t, err)
	assert.ErrorContains(t, err, "error processing high watermark event. product is not enabled for customer 453")
}

func TestUsageHandler_ProcessMessage_HighWatermarkEvent_WithErrorWithSubscription(t *testing.T) {
	rr := setupRecvPayload("ghec_seats", 100, 454, "", models.UTCNow())
	logger, mdb, _, handler := setupHandler(t, mockForHighWaterMarkWithSubscriptionError, "resourceLookup:enterprise:454", "sku1", "customer")

	CreateWithOptionsDelay(mdb, 200*time.Millisecond, nil)

	// Test
	err := handler.ProcessMessage(context.Background(), logger, rr)

	// Assert
	assert.ErrorContains(t, err, "failed to create even though there wasn't one. TODO handle this")
	mdb.VerifyWasCalled(pegomock.Never()).CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey](),
		pegomock.Any[*interfaces.QueryOptions]())
}

func TestUsageHandler_ProcessMessage_HighWatermarkEvent_WithNoError(t *testing.T) {
	usageAt := models.NewUsageTimeFromTime(time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC))
	rr := setupRecvPayload("ghec_seats", 10, 455, "", usageAt)
	logger, mdb, fakeContainer, handler := setupHandler(t, mockForHighWaterMark, "resourceLookup:enterprise:455", "sku1", "customer")

	mockCommonEntities(t, fakeContainer, 455)
	// pager for GetAllBudgets mocking
	pager := helpers.MakePagerWithData(t, []*models.Budget{})
	pegomock.When(
		fakeContainer.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	// Test
	err := handler.ProcessMessage(context.Background(), logger, rr)

	// Assert
	assert.NoError(t, err)
	assert.NoError(t, handler.ProcessJobError)

	expHighWaterMarkItemDbCreated := &models.HighWatermarkEvent{
		Key:                    models.Key{PartitionKey: "455:highWatermark:ghec_seats:2024:6", Id: "455:highWatermark:ghec_seats:2024:6"},
		FullQuantity:           10000000000,
		Quantity:               10000000000,
		BilledAmount:           210000000000,
		AppliedCostPerQuantity: 21000000000,
		DailyDiscountQuantity:  0,
		Product:                "ghec",
		Sku:                    "ghec_seats",
		CustomerID:             "455",
		UsageAt:                *usageAt,
	}

	mdb.VerifyWasCalledOnce().CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(expHighWaterMarkItemDbCreated),
		pegomock.Any[*interfaces.QueryOptions]())

	mdb.VerifyWasCalled(pegomock.Times(4)).CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey](),
		pegomock.Any[*interfaces.QueryOptions]())

	mdb.VerifyWasCalledOnce().PatchWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey](),
		pegomock.Any[interfaces.PatchOps](),
		pegomock.Any[*interfaces.QueryOptions]())
}

// Test helper functions and mocks
type mockFn func(t *testing.T, fakeContainer *fakes.MockCosmosConnection, resourceLookup string, sku string, customer string)

func setupHandler(t *testing.T, m mockFn, r, sku, c string) (log.Logger, *fakes.MockDatabase, *fakes.MockCosmosConnection, *UsageHandler) {
	fakeContainer, telem, statter, logger, db := helpers.SetupMocks(t)

	cfg := &config.Config{
		Environment: "test",
	}

	m(t, fakeContainer, r, sku, c)

	pegomock.RegisterMockTestingT(t)

	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(fakeContainer)
	pegomock.When(db.GetStatter()).ThenReturn(statter)

	engineParams := engines.NewEngineParams(nil, cfg, db, nil, statter, nil, telem.Tracer.Tracer)

	costCenterEngine := engines.NewCostCenterEngine(engineParams)
	pricingEngine := engines.NewPricingEngine(engineParams)
	customerEngine := engines.NewCustomerEngine(engineParams)
	totalsPatching := engines.NewTotalPatchingEngine(engineParams)
	invoiceEngine := engines.NewInvoiceEngine(engineParams)
	subsEngine := engines.NewSubscriptionsEngine(engineParams, totalsPatching, logger)
	productEngine := engines.NewProductEngine(engineParams)
	usageEngine := engines.NewUsageEngine(engineParams)

	handlerParams := &HandlerParams{
		statter:        statter,
		tracer:         telem.Tracer.Tracer,
		aqueductClient: &fakes.MockAqueductClient{},
		DB:             db,
		TotalsPatching: totalsPatching,
	}

	// use this to inspect hydro logs if needed
	var hydroLogs []byte
	stdLogger := stdlog.New(bytes.NewBuffer(hydroLogs), "", 0)
	loghydroPublisher, hErr := hydro.NewPublisher(hydro.NewLogSink(stdLogger))
	assert.NoError(t, hErr)

	// Build the handler
	handler := NewUsageHandler(
		handlerParams,
		costCenterEngine,
		customerEngine,
		invoiceEngine,
		pricingEngine,
		loghydroPublisher,
		subsEngine,
		productEngine,
		usageEngine,
	)
	return logger, db, fakeContainer, handler
}

// setupRecvPayload creates a ReceiveResult with a payload that contains a Usage message
// Add more fields here as needed to extend the payload for testing
func setupRecvPayload(sku string, qty float64, cId int64, usageUuid string, usageAt *models.UsageTime) aqueduct.ReceiveResult {
	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			Payload: func() []byte {
				env := &hydro_schemas_hydro_v1.Envelope{
					Message: func() []byte {
						um := hydro_schemas_billingplatform_v1.Usage{
							Sku:      sku,
							Quantity: qty,
							Entity: &hydro_schemas_billingplatform_v1_entities.EntityDetail{
								CustomerId: cId,
							},
							UsageUuid: usageUuid,
							UsageAt: &timestamp.Timestamp{
								Seconds: usageAt.Unix(),
							},
						}
						m, _ := protobuf.Marshal(&um)
						return m
					}(),
				}
				e, _ := protobuf.Marshal(env)
				return e
			}(),
		},
	}
	return rr
}

// CreateWithOptionsDelay adds a little delay to CreateWithOptions to simulate a real cosmosdb call
// Effectively this means any goroutines that use this call won't return quickly so we can indirectly
// test for goroutine completion
func CreateWithOptionsDelay(mdb *fakes.MockDatabase, delay time.Duration, err error) {
	pegomock.When(mdb.CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey](),
		pegomock.Any[*interfaces.QueryOptions]())).Then(func(params []pegomock.Param) pegomock.ReturnValues {
		time.Sleep(delay)
		return pegomock.ReturnValues{err}
	})
}

func emptyMock(t *testing.T, fakeContainer *fakes.MockCosmosConnection, costCenterKeyId, pricingSkuKeyId, customerKeyId string) {
}

func mockCommonEntities(t *testing.T, fakeContainer *fakes.MockCosmosConnection, customerId int64) {
	repo := &models.Repo{
		RepoKey: &models.RepoKey{
			Key: &models.Key{
				Id:           "0",
				PartitionKey: "repos",
			},
			RepoId: 0,
		},
		IsPublic: false,
	}

	mockReadItemWith(fakeContainer, "repos", "0", helpers.MockAzureItemResponse(t, repo), nil)

	pegomock.When(
		fakeContainer.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Eq(azcosmos.NewPartitionKeyString(fmt.Sprintf("customer:%d:budgets", customerId))),
			pegomock.Any[string](),
			pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.MockAzureItemResponse(t, &models.Budget{}),
			&azcore.ResponseError{StatusCode: http.StatusNotFound},
		)

}

// mocks readItem responses for CostCenter,Pricing,Customer
// These static mocks return for a specific costCenterKeyId, pricingSkuKeyId, customerKeyId
// e.g mockWithStaticCostCenterPricingCustomer(t, "resourceLookup:enterprise:<enterpriseId>", "<skuId>", "customer")
func mockWithStaticCostCenterPricingCustomer(t *testing.T, fakeContainer *fakes.MockCosmosConnection, costCenterKeyId, pricingSkuKeyId, customerKeyId string) {
	pegomock.RegisterMockTestingT(t)

	mockReadItemWith(fakeContainer, "", costCenterKeyId, helpers.StaticTestCostCenter(t), nil)
	mockReadItemWith(fakeContainer, "", pricingSkuKeyId, helpers.StaticTestPricing(t), nil)
	mockReadItemWith(fakeContainer, "", customerKeyId, helpers.StaticTestCustomerReadItemResponse(t), nil)
}

// mocks readItem responses for CostCenter,Pricing,Customer
// These static mocks return for a specific costCenterKeyId, pricingSkuKeyId, customerKeyId
// e.g mockWithStaticCostCenterPricingCustomer(t, "resourceLookup:enterprise:<enterpriseId>", "<skuId>", "customer")
func mockWithStaticCostCenterPricingCustomerIdZero(t *testing.T, fakeContainer *fakes.MockCosmosConnection, costCenterKeyId, pricingSkuKeyId, customerKeyId string) {
	pegomock.RegisterMockTestingT(t)

	mockReadItemWith(fakeContainer, "", costCenterKeyId, helpers.StaticTestCostCenterCustomerIdZero(t), nil)
	mockReadItemWith(fakeContainer, "", pricingSkuKeyId, helpers.StaticTestPricing(t), nil)
	mockReadItemWith(fakeContainer, "", customerKeyId, helpers.StaticTestCustomerReadZeroResponse(t), nil)
}

// mocks readItem responses for CostCenter,Pricing,Customer, Subscription
// These static mocks return for a specific costCenterKeyId, pricingSkuKeyId, customerKeyId
// e.g mockForHighWaterMark(t, "resourceLookup:enterprise:<enterpriseId>", "<skuId>", "customer")
func mockForHighWaterMark(t *testing.T, fakeContainer *fakes.MockCosmosConnection, costCenterKeyId, pricingSkuKeyId, customerKeyId string) {
	pegomock.RegisterMockTestingT(t)

	mockReadItemWith(fakeContainer, "", costCenterKeyId, helpers.StaticTestCostCenter(t), nil)
	mockReadItemWith(fakeContainer, "", pricingSkuKeyId, helpers.TestPricingForHighWatermark(t), nil)
	mockReadItemWith(fakeContainer, "", customerKeyId, helpers.StaticTestCustomerWithEnabledProductsReadItemResponse(t), nil)

	subscribedItem := helpers.MockAzureItemResponse(t, &models.SubscribedItem{
		SubscriptionStatus: models.SubscriptionActive,
		UpdatedAt:          models.NewUsageTimeFromTime(time.Now().AddDate(-1, 0, 0)),
	})
	mockReadItemWith(fakeContainer, "", "subscription:0", subscribedItem, nil)
}

// mocks readItem responses for CostCenter,Pricing,Customer, Subscription with error
// These static mocks return for a specific costCenterKeyId, pricingSkuKeyId, customerKeyId
// e.g mockForHighWaterMark(t, "resourceLookup:enterprise:<enterpriseId>", "<skuId>", "customer")
func mockForHighWaterMarkWithSubscriptionError(t *testing.T, fakeContainer *fakes.MockCosmosConnection, costCenterKeyId, pricingSkuKeyId, customerKeyId string) {
	pegomock.RegisterMockTestingT(t)

	mockReadItemWith(fakeContainer, "", costCenterKeyId, helpers.StaticTestCostCenter(t), nil)
	mockReadItemWith(fakeContainer, "", pricingSkuKeyId, helpers.TestPricingForHighWatermark(t), nil)
	mockReadItemWith(fakeContainer, "", customerKeyId, helpers.StaticTestCustomerWithEnabledProductsReadItemResponse(t), nil)
	mockReadItemWith(fakeContainer, "", "subscription:0", helpers.MockAzureItemResponse(t, &models.SubscribedItem{}), azRuntime.NewResponseError(&http.Response{StatusCode: http.StatusNotFound}))
}

func mockReadItemWith(fakeContainer *fakes.MockCosmosConnection, partitionKey, id string, result azcosmos.ItemResponse, err error) {
	if partitionKey == "" {
		pegomock.When(
			fakeContainer.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Any[azcosmos.PartitionKey](),
				pegomock.Eq(id),
				pegomock.Any[*azcosmos.ItemOptions]())).
			ThenReturn(result, err)
	} else {
		pegomock.When(
			fakeContainer.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Eq(azcosmos.NewPartitionKeyString(partitionKey)),
				pegomock.Eq(id),
				pegomock.Any[*azcosmos.ItemOptions]())).
			ThenReturn(result, err)
	}
}
