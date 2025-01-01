package handlers

import (
	"bytes"
	"context"
	"errors"
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
	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/github/feature-management-client-go/vexi/adapter/fake"
	"github.com/github/github-telemetry-go/log"
	hydro_schemas_hydro_v1 "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	protobuf "google.golang.org/protobuf/proto"
)

func TestUsageHandler_ProcessMessage_InvalidLoadItem(t *testing.T) {
	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			Payload: []byte(`{"id": "123"}`),
		},
	}
	logger, handlerParams, _, _ := mocksWithBasicCostCenter(t)
	handler := NewUsageHandler(handlerParams, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil)

	err := handler.ProcessMessage(context.Background(), logger, rr)
	assert.ErrorContains(t, err, "cannot parse invalid wire-format data")
}

func TestUsageHandler_ProcessMessage_CustomerIdZero(t *testing.T) {
	now := models.UTCNow()
	rr := setupRecvPayload("sku1", 100, 0, 0, 0, "", now)
	logger, mdb, _, handler, _ := setupHandler(t, mockWithStaticCostCenterPricingCustomerIdZero, "resourceLookup:enterprise:0", "sku1", "customer")
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
	rr := setupRecvPayload("actions_storage", 100, 15, 0, 0, "uuid", now)
	logger, mdb, fakeContainer, handler, fakeAdapter := setupHandler(t, emptyMock, "", "", "")
	fakeAdapter.AddFeatureFlag(featureflags.IdempotentKeyForUsageHandlerRerun, false) // disable feature flag

	pricingResponse := helpers.TestCustomPricing(t, "actions", "actions_storage", 100, time.Now().Add(-time.Hour).Unix())
	mockReadItemWith(fakeContainer, "", "actions_storage", pricingResponse, nil)

	customerResponse := helpers.TestCustomerReadItemResponse(t, customerId, 0, "actions", false)
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

func TestUsageHandler_ProcessMessage_IdempotentKeyRead(t *testing.T) {
	type IdempotentKeyTestData struct {
		name                 string
		readResponse         azcosmos.ItemResponse
		readError            error
		returnsError         bool
		upsertsIdempotentKey bool
	}

	params := []IdempotentKeyTestData{
		{
			name:                 "When IdempotentKey read fails with 429 - return error and don't upsert idempotent key",
			readResponse:         helpers.MockAzureItemResponseWith404(t),
			readError:            &azcore.ResponseError{StatusCode: 429}, // this is slow test due to the reties. To be improved
			returnsError:         true,
			upsertsIdempotentKey: false,
		},
		{
			name:                 "When IdempotentKey read succeeds and item is completed - return no error and don't upsert idempotent key",
			readResponse:         helpers.TestIdempotentKeyReadItemResponse(t, true),
			readError:            nil,
			returnsError:         false,
			upsertsIdempotentKey: false,
		},
		{
			name:                 "When IdempotentKey read succeeds but item is NOT completed - return no error and upsert idempotent key",
			readResponse:         helpers.TestIdempotentKeyReadItemResponse(t, false),
			readError:            nil,
			returnsError:         false,
			upsertsIdempotentKey: true,
		},
		{
			name:                 "When IdempotentKey read not found with 404 - return no error and upsert idempotent key",
			readResponse:         helpers.MockAzureItemResponseWith404(t),
			readError:            &azcore.ResponseError{StatusCode: 404},
			returnsError:         false,
			upsertsIdempotentKey: true,
		},
	}

	for _, param := range params {
		t.Run(param.name, func(t *testing.T) {
			rr := setupRecvPayload("actions_storage", 100, 15, 0, 0, "uuid", models.UTCNow())
			logger, mdb, fakeContainer, handler, fakeAdapter := setupHandler(t, mockWithStaticCostCenterPricingCustomer, "", "actions_storage", "customer")
			fakeAdapter.AddFeatureFlag(featureflags.IdempotentKeyForUsageHandlerRerun, true) // enable feature flag

			mockReadItemWith(fakeContainer, "", "billable", param.readResponse, param.readError)

			err := handler.ProcessMessage(context.Background(), logger, rr)

			if param.upsertsIdempotentKey {
				_, _, idempotentKey, option := mdb.VerifyWasCalled(pegomock.Once()).UpsertWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[*models.IdempotentKey](),
					pegomock.Any[*interfaces.QueryOptions]()).GetCapturedArguments()
				assert.Equal(t, "billable", idempotentKey.GetKey().Id)
				assert.Equal(t, "uuid", idempotentKey.GetKey().PartitionKey)
				assert.Equal(t, true, idempotentKey.(*models.IdempotentKey).Completed)
				assert.Equal(t, option.RetryCount, 10)
			} else {
				mdb.VerifyWasCalled(pegomock.Never()).UpsertWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[*models.IdempotentKey](),
					pegomock.Any[*interfaces.QueryOptions]())
			}

			if param.returnsError {
				assert.Error(t, err)
				assert.Equal(t, err, param.readError)
			} else {
				assert.NoError(t, err)
				assert.NoError(t, handler.ProcessJobError)
			}
		})
	}
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
	retryFlagEnabled  bool
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
			name:              "Budget is not yet fully funded",
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
		{
			name:              "Budget is funded past plan discount for applicable sku when retry flag is enabled",
			discountAmount:    400,
			quantity:          409, // $400 to plan discount + 9 billed usage
			product:           "actions",
			sku:               "actions_linux", // sku with plan discount
			skuPrice:          1.0,
			fullyFunded:       false,
			expectedAmount:    9,
			budgetTarget:      10,
			thresholdMetUsage: 90,
			retryFlagEnabled:  true,
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

	// Currently these are types of budgets we support
	// i.e enterprise, owning_entity, repository, and cost_center
	budgetTargets := []struct {
		targetId   int64
		targetType models.ResourceType
	}{
		{
			targetId:   int64(stubs.GetRandomId()),
			targetType: models.CustomerResource,
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
			targetType: models.CostCenterResource,
		},
		// This is commented out becuase we don't currently support any budget types other than enterprise, owning entity, and repository
		//
		// {
		//	targetId:   int64(stubs.GetRandomId()),
		//	targetType: models.User,
		// },
		//
	}

	for _, budgetTarget := range budgetTargets {
		t.Run(fmt.Sprintf("%s_%s", tt.name, budgetTarget.targetType), func(t *testing.T) {
			testBudget(t, tt, int64(stubs.GetRandomId()), budgetTarget.targetId, budgetTarget.targetType)
		})
	}
}

func testBudget(t *testing.T, params BudgetTestData, customerId int64, targetId int64, targetType models.ResourceType) {
	now := models.UTCNow()

	logger, db, fakeContainer, handler, fakeAdapter := setupHandler(t, emptyMock, "", "", "")

	var rr aqueduct.ReceiveResult
	var repoId int64

	// mock the cost center read items based on the target type
	switch targetType {
	case models.OwningEntity:
		rr = setupRecvPayload(params.sku, params.quantity, customerId, targetId, 0, "", now)
		pegomock.When(
			fakeContainer.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Eq(azcosmos.NewPartitionKeyString(fmt.Sprintf("customer:%d:costCenters", customerId))),
				pegomock.Eq(fmt.Sprintf("resourceLookup:owning_entity:%d", targetId)),
				pegomock.Any[*azcosmos.ItemOptions]())).ThenReturn(helpers.MockAzureItemResponse(t, &models.CostCenterKey{}), nil)
	case models.Repository:
		rr = setupRecvPayload(params.sku, params.quantity, customerId, 0, targetId, "", now)
		pegomock.When(
			fakeContainer.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Eq(azcosmos.NewPartitionKeyString(fmt.Sprintf("customer:%d:costCenters", customerId))),
				pegomock.Eq(fmt.Sprintf("resourceLookup:repository:%d", targetId)),
				pegomock.Any[*azcosmos.ItemOptions]())).ThenReturn(helpers.MockAzureItemResponse(t, &models.CostCenterKey{}), nil)
		repoId = targetId
	case models.CostCenterResource:
		rr = setupRecvPayload(params.sku, params.quantity, customerId, targetId, 0, "", now)
		pegomock.When(
			fakeContainer.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Eq(azcosmos.NewPartitionKeyString(fmt.Sprintf("customer:%d:costCenters", customerId))),
				pegomock.Eq(fmt.Sprintf("resourceLookup:owning_entity:%d", targetId)),
				pegomock.Any[*azcosmos.ItemOptions]())).ThenReturn(helpers.MockAzureItemResponse(t,
			&models.CostCenterKey{
				UUID:       fmt.Sprintf("%d", targetId),
				TargetType: models.AzureSubscription,
				TargetId:   fmt.Sprintf("%d", targetId),
				Customer: &models.Customer{
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: fmt.Sprintf("%d", targetId),
						IsCostCenterProxy:    true,
						CostCenterState:      models.CostCenterActive,
					},
				},
			}), nil)
	default:
		rr = setupRecvPayload(params.sku, params.quantity, customerId, 0, 0, "", now)

	}

	repo := &models.Repo{
		RepoKey: &models.RepoKey{
			Key: &models.Key{
				Id:           "0",
				PartitionKey: "repo:0",
			},
			RepoId: repoId,
		},
		IsPublic: false,
	}

	mockReadItemWith(fakeContainer, fmt.Sprintf("repo:%d", repoId), fmt.Sprintf("%d", repoId), helpers.MockAzureItemResponse(t, repo), nil)

	pricingResponse := helpers.TestCustomPricing(t, params.product, params.sku, params.skuPrice, time.Now().Add(-time.Hour).Unix())
	mockReadItemWith(fakeContainer, "", params.sku, pricingResponse, nil)

	var enterpriseId int64
	if targetType == models.CostCenterResource {
		enterpriseId = targetId
		c := helpers.TestCustomerReadItemResponse(t, enterpriseId, enterpriseId, params.product, true)
		mockReadItemWith(fakeContainer, fmt.Sprintf("customer:%d", enterpriseId), "customer", c, nil)
	}

	customerResponse := helpers.TestCustomerReadItemResponse(t, customerId, enterpriseId, params.product, targetType == models.CostCenterResource)
	mockReadItemWith(fakeContainer, fmt.Sprintf("customer:%d", customerId), "customer", customerResponse, nil)

	discountState, discountStateResponse := helpers.TestDiscountStateReadItemResponse(t, customerId, params.discountAmount, "123")
	mockReadItemWith(fakeContainer, "", discountState.PartitionKey, discountStateResponse, nil)

	var budgets []*models.Budget

	budgets = append(budgets, &models.Budget{
		BudgetKey: &models.BudgetKey{
			Key: &models.Key{
				Id:           fmt.Sprintf("customer:%d:budgets:%s:%d:product:actions", customerId, targetType, targetId),
				PartitionKey: fmt.Sprintf("customer:%d:budgets", customerId),
			},
			TargetType: targetType,
			TargetId:   fmt.Sprintf("%d", targetId),
		},
		TargetAmount:   models.ToWholeAmount[uint64](params.budgetTarget),
		BudgetAlerting: &models.BudgetAlerting{},
	})

	pager := helpers.MakePagerWithData(t, budgets)

	pegomock.When(
		fakeContainer.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

	pegomock.When(fakeContainer.ReadItem(
		pegomock.Any[context.Context](),
		helpers.Contains(azcosmos.NewPartitionKeyString(fmt.Sprintf("customer:%d:budgets:%s:%d:product:actions", customerId, targetType, targetId))),
		pegomock.Eq("budgetState"),
		pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(helpers.MockAzureItemResponse(t, &models.BudgetState{
			TargetAmount:  models.ToWholeAmount[uint64](params.budgetTarget),
			IsFullyFunded: params.fullyFunded,
		}), nil)

	if params.retryFlagEnabled {
		idempotentKeyNotFound := helpers.MockAzureItemResponseWith404(t)
		mockReadItemWith(fakeContainer, "", "billable", idempotentKeyNotFound, &azcore.ResponseError{StatusCode: 404})
	}

	fakeAdapter.AddFeatureFlag(featureflags.IdempotentKeyForUsageHandlerRerun, params.retryFlagEnabled)

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

	if params.retryFlagEnabled {
		_, _, idempotentKey, _ := db.VerifyWasCalled(pegomock.Once()).UpsertWithOptions(
			pegomock.Any[context.Context](),
			pegomock.Any[log.Logger](),
			pegomock.Any[*models.IdempotentKey](),
			pegomock.Any[*interfaces.QueryOptions]()).GetCapturedArguments()
		assert.Equal(t, "billable", idempotentKey.GetKey().Id)
		assert.Equal(t, true, idempotentKey.(*models.IdempotentKey).Completed)
	} else {
		db.VerifyWasCalled(pegomock.Never()).UpsertWithOptions(
			pegomock.Any[context.Context](),
			pegomock.Any[log.Logger](),
			pegomock.Any[*models.IdempotentKey](),
			pegomock.Any[*interfaces.QueryOptions]())
	}
}

func TestUsageHandler_ProcessMessage_NonWatermarkEvent_WithoutPricing_RerunFlagDisabled(t *testing.T) {
	rr := setupRecvPayload("", 0, 451, 0, 0, "", models.UTCNow())
	logger, mdb, _, handler, fakeAdapter := setupHandler(
		t,
		mockWithStaticCostCenterPricingCustomer,
		"resourceLookup:enterprise:451", "sku1", "customer")

	CreateWithOptionsDelay(mdb, 200*time.Millisecond, nil)

	fakeAdapter.AddFeatureFlag(featureflags.IdempotentKeyForUsageHandlerRerun, false)

	// Test
	err := handler.ProcessMessage(context.Background(), logger, rr)

	// Assert
	assert.NoError(t, err)
	assert.NoError(t, handler.ProcessJobError)
	mdb.VerifyWasCalled(pegomock.Never()).UpsertWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.IdempotentKey](),
		pegomock.Any[*interfaces.QueryOptions]())

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

func TestUsageHandler_ProcessMessage_NonWatermarkEvent_WithoutPricing_RerunFlagEnabled(t *testing.T) {
	rr := setupRecvPayload("", 0, 451, 0, 0, "", models.UTCNow())
	logger, mdb, fakeContainer, handler, fakeAdapter := setupHandler(
		t,
		mockWithStaticCostCenterPricingCustomer,
		"resourceLookup:enterprise:451", "sku1", "customer")

	idempotentKeyNotFound := helpers.MockAzureItemResponseWith404(t)
	mockReadItemWith(fakeContainer, "", "billable", idempotentKeyNotFound, &azcore.ResponseError{StatusCode: 404})

	CreateWithOptionsDelay(mdb, 200*time.Millisecond, nil)

	fakeAdapter.AddFeatureFlag(featureflags.IdempotentKeyForUsageHandlerRerun, true)

	// Test
	err := handler.ProcessMessage(context.Background(), logger, rr)

	// Assert
	assert.NoError(t, err)
	assert.NoError(t, handler.ProcessJobError)

	_, _, actualItem, _ := mdb.VerifyWasCalled(pegomock.Once()).UpsertWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.IdempotentKey](),
		pegomock.Any[*interfaces.QueryOptions]()).GetCapturedArguments()
	assert.Equal(t, "billable", actualItem.GetKey().Id)
	assert.Equal(t, true, actualItem.(*models.IdempotentKey).Completed)

	mdb.VerifyWasCalled(pegomock.Never()).CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey](),
		pegomock.Any[*interfaces.QueryOptions]())

	_, _, nopricingItemKey := mdb.VerifyWasCalledOnce().CreateIfNotExists(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey]()).GetCapturedArguments()
	assert.Equal(t, "no-pricing", nopricingItemKey.GetKey().Id)
}

func TestUsageHandler_ProcessMessage_NonWatermarkEvent_WithPricing_RerunFlagDisabled(t *testing.T) {
	rr := setupRecvPayload("sku1", 100, 452, 0, 0, "", models.UTCNow())
	logger, mdb, _, handler, fakeAdapter := setupHandler(t, mockWithStaticCostCenterPricingCustomer, "resourceLookup:enterprise:452", "sku1", "customer")

	fakeAdapter.AddFeatureFlag(featureflags.IdempotentKeyForUsageHandlerRerun, false)

	// Test
	err := handler.ProcessMessage(context.Background(), logger, rr)

	// Assert
	assert.NoError(t, err)
	assert.NoError(t, handler.ProcessJobError)
	mdb.VerifyWasCalled(pegomock.Never()).UpsertWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.IdempotentKey](),
		pegomock.Any[*interfaces.QueryOptions]())

	_, _, actualItem, _ := mdb.VerifyWasCalled(pegomock.Once()).CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey](),
		pegomock.Any[*interfaces.QueryOptions]()).GetCapturedArguments()
	assert.Equal(t, "billable", actualItem.GetKey().Id)

	mdb.VerifyWasCalled(pegomock.Never()).CreateIfNotExists(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey]())
}

func TestUsageHandler_ProcessMessage_WithPricing_RerunFlagEnabled(t *testing.T) {
	type HandlerCompletionData struct {
		name                         string
		withFailedGoroutine          bool
		withFailedRollup             bool
		failedIdempotentKeyUpsert    bool
		expectIdempotentKeyCompleted bool
		expectReturnedError          bool
		isWatermark                  bool
	}

	params := []HandlerCompletionData{
		{
			name:                         "With no failures - completed and no error",
			expectIdempotentKeyCompleted: true,
			expectReturnedError:          false,
		},
		{
			name:                         "With a failed goroutine - not completed, return error",
			withFailedGoroutine:          true,
			expectIdempotentKeyCompleted: false,
			expectReturnedError:          true,
		},
		{
			name:                         "With failed idempotent key upsert - completed, no error",
			failedIdempotentKeyUpsert:    true,
			expectIdempotentKeyCompleted: true,
			expectReturnedError:          false,
		},
		{
			name:                         "With failed rollups aqueduct send - not completed, return error",
			withFailedRollup:             true,
			expectIdempotentKeyCompleted: false,
			expectReturnedError:          true,
		},
		{
			name:                         "Watermark delta - With not failure - completed and no error",
			isWatermark:                  true,
			expectIdempotentKeyCompleted: true,
			expectReturnedError:          false,
		},
		{
			name:                         "Watermark delta - With a failed goroutine - not completed, return error",
			isWatermark:                  true,
			withFailedGoroutine:          true,
			expectIdempotentKeyCompleted: false,
			expectReturnedError:          true,
		},
		{
			name:                         "Watermark delta - With a failed idempotent key upsert - completed, no error",
			isWatermark:                  true,
			failedIdempotentKeyUpsert:    true,
			expectIdempotentKeyCompleted: true,
			expectReturnedError:          false,
		},
		{
			name:                         "Watermark delta - With a failed goroutine and failed key storage - not completed, no error",
			isWatermark:                  true,
			withFailedGoroutine:          true,
			failedIdempotentKeyUpsert:    true,
			expectIdempotentKeyCompleted: false,
			expectReturnedError:          false,
		},
	}

	for _, param := range params {
		t.Run(param.name, func(t *testing.T) {
			// Setup
			rr := setupRecvPayload("sku1", 100, 452, 0, 0, "uuid", models.UTCNow())
			logger, mdb, fakeContainer, handler, fakeAdapter := setupHandler(t, mockWithStaticCostCenterWatermarkPricingCustomer, "", "sku1", "452")

			fakeAdapter.AddFeatureFlag(featureflags.IdempotentKeyForUsageHandlerRerun, true)
			fakeAdapter.AddFeatureFlag(featureflags.UseHighCardinalEventsPartitionKey, true)

			itemKeyId := "billable"
			if param.isWatermark {
				itemKeyId = "events"
			}
			idempotentKeyNotFound := helpers.MockAzureItemResponseWith404(t)
			mockReadItemWith(fakeContainer, "", itemKeyId, idempotentKeyNotFound, &azcore.ResponseError{StatusCode: 404})

			customerResponse := helpers.TestCustomerReadItemResponse(t, 452, 452, "", false)
			mockReadItemWith(fakeContainer, fmt.Sprintf("customer:%d", 452), "customer", customerResponse, nil)

			pricingResponse := helpers.TestCustomPricing(t, "", "sku1", 10, time.Now().Add(-time.Hour).Unix())
			if param.isWatermark {
				pricingResponse = helpers.StaticTestWatermarkPricing(t)
			}
			mockReadItemWith(fakeContainer, "", "sku1", pricingResponse, nil)

			// pager for GetAllBudgets mocking
			pager := helpers.MakePagerWithData(t, []*models.Budget{})
			pegomock.When(
				fakeContainer.NewQueryItemsPager(
					pegomock.Any[string](),
					pegomock.Any[azcosmos.PartitionKey](),
					pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)

			if param.withFailedGoroutine {
				// Mocking the CreateIfNotExists to return an error
				pegomock.When(mdb.CreateIfNotExists(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
				)).ThenReturn(
					false,
					&azcore.ResponseError{StatusCode: 429},
				)
			}

			if param.withFailedRollup {
				// this slows down the test because of the 10 throttled retries
				// TODO: Improve this. Perhaps mock the handler.sendRollupJobs method instead or fix the throttling during testing
				pegomock.When(handler.aqueductClient.SendBatch(
					pegomock.Any[context.Context](),
					pegomock.Any[[]aqueduct.BatchItem](),
				)).ThenReturn(
					&aqueduct.SendBatchResult{},
					errors.New("failed to send rollup jobs"),
				)
			}

			if param.failedIdempotentKeyUpsert {
				// Mocking the UpsertWithOptions to return an error
				pegomock.When(mdb.UpsertWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[*models.IdempotentKey](),
					pegomock.Any[*interfaces.QueryOptions](),
				)).ThenReturn(
					&azcore.ResponseError{StatusCode: 429},
				)
			}

			// Test
			err := handler.ProcessMessage(context.Background(), logger, rr)

			// Assert
			if param.expectReturnedError {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
			_, _, idempotentItem, _ := mdb.VerifyWasCalled(pegomock.Once()).UpsertWithOptions(
				pegomock.Any[context.Context](),
				pegomock.Any[log.Logger](),
				pegomock.Any[*models.IdempotentKey](),
				pegomock.Any[*interfaces.QueryOptions]()).GetCapturedArguments()
			assert.Equal(t, param.expectIdempotentKeyCompleted, idempotentItem.(*models.IdempotentKey).Completed)

			_, _, createIfNotExistItem := mdb.VerifyWasCalled(pegomock.Once()).CreateIfNotExists(
				pegomock.Any[context.Context](),
				pegomock.Any[log.Logger](),
				pegomock.Any[models.ItemKey]()).GetCapturedArguments()

			if param.isWatermark {
				assert.Equal(t, "events", idempotentItem.GetKey().Id)
				assert.Equal(t, "452", createIfNotExistItem.GetKey().Id)
				assert.Equal(t, "active:sku1:events", createIfNotExistItem.GetKey().PartitionKey)
			} else {
				assert.Equal(t, "billable", idempotentItem.GetKey().Id)
				assert.Equal(t, idempotentItem.GetKey().PartitionKey, createIfNotExistItem.GetKey().Id)
				assert.Contains(t, createIfNotExistItem.GetKey().PartitionKey, "byOrgRepoProductSku", "452")
			}
		})
	}
}

func TestUsageHandler_ProcessMessage_HighWatermarkEvent_WithPricingNotEnabledForEmission(t *testing.T) {
	rr := setupRecvPayload("ghas_seats", 100, 453, 0, 0, "", models.UTCNow())
	// mockForHighWaterMark only has ghas enabled
	logger, _, _, handler, _ := setupHandler(t, mockForHighWaterMarkWithNoProduct, "resourceLookup:enterprise:453", "ghas_seats", "customer")

	// Test
	err := handler.ProcessMessage(context.Background(), logger, rr)

	// Assert
	assert.Error(t, err)
	assert.ErrorContains(t, err, "error processing high watermark event. product is not enabled for customer 453")
}

func TestUsageHandler_ProcessMessage_HighWatermarkEvent_WithErrorWithSubscription(t *testing.T) {
	rr := setupRecvPayload("ghas_seats", 100, 454, 0, 0, "", models.UTCNow())
	logger, mdb, _, handler, _ := setupHandler(t, mockForHighWaterMarkWithSubscriptionError, "resourceLookup:enterprise:454", "ghas_seats", "customer")

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
	rr := setupRecvPayload("ghas_seats", 10, 455, 0, 0, "", usageAt)
	logger, mdb, fakeContainer, handler, _ := setupHandler(t, mockForHighWaterMark, "resourceLookup:enterprise:455", "ghas_seats", "customer")

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
		Key:                    models.Key{PartitionKey: "455:highWatermark:ghas_seats:2024:6", Id: "455:highWatermark:ghas_seats:2024:6"},
		FullQuantity:           10000000000,
		Quantity:               10000000000,
		BilledAmount:           50,
		AppliedCostPerQuantity: 5,
		DailyDiscountQuantity:  0,
		Product:                "ghas",
		Sku:                    "ghas_seats",
		CustomerID:             "455",
		UsageAt:                *usageAt,
	}

	mdb.VerifyWasCalledOnce().CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(expHighWaterMarkItemDbCreated),
		pegomock.Any[*interfaces.QueryOptions]())

	mdb.VerifyWasCalled(pegomock.Times(3)).CreateWithOptions(
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

func TestUsageHandler_ProcessMessage_WatermarkEvent(t *testing.T) {
	now := models.UTCNow()

	rr := setupRecvPayload("sku1", 0, 451, 0, 0, "uuid", now)
	logger, mdb, _, handler, fakeAdapter := setupHandler(
		t,
		mockWithStaticCostCenterWatermarkPricingCustomer,
		"resourceLookup:enterprise:451", "sku1", "customer")

	CreateWithOptionsDelay(mdb, 200*time.Millisecond, nil)

	expectedRollupTotalId := fmt.Sprintf("451:sku1:events:rollups:%d:%d", 0, 0)
	expectedPartitionKey := "451:sku1:events:rollups"

	fakeAdapter.AddFeatureFlag(featureflags.IdempotentKeyForUsageHandlerRerun, false)

	// Test
	err := handler.ProcessMessage(context.Background(), logger, rr)

	// Assert
	assert.NoError(t, err)
	assert.NoError(t, handler.ProcessJobError)

	// called once for totals and once for regular rollup
	_, _, actualPatchItem, _ := mdb.VerifyWasCalled(pegomock.Times(2)).CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[models.ItemKey](),
		pegomock.Any[*interfaces.QueryOptions]()).GetCapturedArguments()
	assert.Equal(t, expectedPartitionKey, actualPatchItem.GetKey().PartitionKey)

	_, _, actualPatchTotalItem, _ := mdb.VerifyWasCalledOnce().CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.WatermarkTotalItem](),
		pegomock.Any[*interfaces.QueryOptions]()).GetCapturedArguments()
	assert.Equal(t, expectedRollupTotalId, actualPatchTotalItem.GetKey().Id)
}

func TestUsageHandler_ProcessMessage_WatermarkEvent_GithubCustomer(t *testing.T) {
	usageAt := models.NewUsageTimeFromTime(time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC))

	rr := setupRecvPayload("sku1", 0, 5018891, 0, 0, "usageuuid", usageAt)
	logger, mdb, _, handler, _ := setupHandler(
		t,
		mockWithStaticCostCenterWatermarkPricingCustomer,
		"resourceLookup:enterprise:5018891", "sku1", "customer")

	CreateWithOptionsDelay(mdb, 200*time.Millisecond, nil)

	expectedPartitionKey := fmt.Sprintf("5018891:sku1:events:%d:%d", usageAt.Year(), usageAt.Month())
	key := models.Key{
		PartitionKey: expectedPartitionKey,
		Id:           "usageuuid",
	}

	item := &models.Item{
		Key:     key,
		UsageAt: *usageAt,
	}

	// Test
	err := handler.ProcessMessage(context.Background(), logger, rr)

	// Assert
	assert.NoError(t, err)
	assert.NoError(t, handler.ProcessJobError)

	_, _, actualItem := mdb.VerifyWasCalled(pegomock.Once()).CreateIfNotExists(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(item)).GetCapturedArguments()

	assert.Equal(t, key.PartitionKey, actualItem.GetKey().PartitionKey)
	assert.Empty(t, item.Pricing)
	assert.Empty(t, item.Amounts)
	assert.Empty(t, item.EntityDetail)
	assert.Empty(t, item.SourceUri)
}

// Test helper functions and mocks
type mockFn func(t *testing.T, fakeContainer *fakes.MockCosmosConnection, resourceLookup string, sku string, customer string)

func setupHandler(t *testing.T, m mockFn, r, sku, c string) (log.Logger, *fakes.MockDatabase, *fakes.MockCosmosConnection, *UsageHandler, *fake.Adapter) {
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

	vexiClient, vexiAdapter := helpers.NewFeatureFlagClient(context.Background(), t, false)

	engineParams := engines.NewEngineParams(nil, cfg, db, vexiClient, statter, nil, telem.Tracer.Tracer)
	pricingEngine := engines.NewPricingEngine(engineParams)
	customerEngine := engines.NewCustomerEngine(engineParams)
	costCenterEngine := engines.NewCostCenterEngine(engineParams, pricingEngine, customerEngine)
	totalsPatching := engines.NewTotalPatchingEngine(engineParams)
	invoiceEngine := engines.NewInvoiceEngine(engineParams)
	subsEngine := engines.NewSubscriptionsEngine(engineParams, totalsPatching, logger)
	productEngine := engines.NewProductEngine(engineParams)
	usageEngine := engines.NewUsageEngine(engineParams)
	budgetEngine := engines.NewBudgetEngine(engineParams, customerEngine)
	discountEngine := engines.NewDiscountEngine(engineParams, pricingEngine, subsEngine)

	handlerParams := &HandlerParams{
		statter:        statter,
		flagger:        vexiClient,
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
		discountEngine,
		budgetEngine,
	)
	return logger, db, fakeContainer, handler, vexiAdapter
}

// setupRecvPayload creates a ReceiveResult with a payload that contains a Usage message
// Add more fields here as needed to extend the payload for testing
// cId, oId, rId are the customer, organization, and repo ids respectively
func setupRecvPayload(sku string, qty float64, cId, oId, rId int64, usageUuid string, usageAt *models.UsageTime) aqueduct.ReceiveResult {
	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			Payload: func() []byte {
				env := &hydro_schemas_hydro_v1.Envelope{
					Message: func() []byte {
						um := hydro_schemas_billingplatform_v1.Usage{
							Sku:      sku,
							Quantity: qty,
							Entity: &hydro_schemas_billingplatform_v1_entities.EntityDetail{
								CustomerId:     cId,
								OrganizationId: oId,
								RepoId:         rId,
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
				PartitionKey: "repo:0",
			},
			RepoId: 0,
		},
		IsPublic: false,
	}

	mockReadItemWith(fakeContainer, "repo:0", "0", helpers.MockAzureItemResponse(t, repo), nil)

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
// These static mocks return for a specific costCenterKeyId, watermark pricingSkuKeyId, customerKeyId
// e.g mockWithStaticCostCenterPricingCustomer(t, "resourceLookup:enterprise:<enterpriseId>", "<skuId>", "customer")
func mockWithStaticCostCenterWatermarkPricingCustomer(t *testing.T, fakeContainer *fakes.MockCosmosConnection, costCenterKeyId, pricingSkuKeyId, customerKeyId string) {
	pegomock.RegisterMockTestingT(t)

	mockReadItemWith(fakeContainer, "", costCenterKeyId, helpers.StaticTestCostCenter(t), nil)
	mockReadItemWith(fakeContainer, "", pricingSkuKeyId, helpers.StaticTestWatermarkPricing(t), nil)
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
	mockReadItemWith(fakeContainer, "", pricingSkuKeyId, helpers.TestPricingForHighWatermarkWithProduct(t), nil)
	mockReadItemWith(fakeContainer, "", customerKeyId, helpers.StaticTestCustomerWithEnabledProductsReadItemResponse(t), nil)

	subscribedItem := helpers.MockAzureItemResponse(t, &models.SubscribedItem{
		SubscriptionStatus: models.SubscriptionActive,
		UpdatedAt:          models.NewUsageTimeFromTime(time.Now().AddDate(-1, 0, 0)),
	})
	mockReadItemWith(fakeContainer, "", "subscription:0", subscribedItem, nil)
}

// mocks readItem responses for CostCenter,Pricing,Customer, Subscription
// These static mocks return for a specific costCenterKeyId, pricingSkuKeyId, customerKeyId
// e.g mockForHighWaterMark(t, "resourceLookup:enterprise:<enterpriseId>", "<skuId>", "customer")
func mockForHighWaterMarkWithNoProduct(t *testing.T, fakeContainer *fakes.MockCosmosConnection, costCenterKeyId, pricingSkuKeyId, customerKeyId string) {
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
	mockReadItemWith(fakeContainer, "", pricingSkuKeyId, helpers.TestPricingForHighWatermarkWithProduct(t), nil)
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
