package handlers

import (
	"bytes"
	"context"
	"fmt"
	stdlog "log"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydro_schemas_billingplatform_v1 "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	hydro_schemas_billingplatform_v1_entities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	billingProto "github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/billing-platform/testing/mocks"
	"github.com/github/feature-management-client-go/vexi/adapter/fake"
	"github.com/github/github-telemetry-go/log"
	hydro_schemas_hydro_v1 "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/google/uuid"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	protobuf "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestNewUsageHandler(t *testing.T) {
	params := &HandlerParams{}
	costCenterEngine := &engines.CostCenterEngine{}
	customerEngine := &engines.CustomerEngine{}
	invoiceEngine := &engines.InvoiceEngine{}
	pricingEngine := &engines.PricingEngine{}
	hydroPublisher := &hydro.Publisher{}
	subscriptionEngine := &engines.SubscriptionsEngine{}
	productEngine := &engines.ProductEngine{}
	usageEngine := &engines.UsageEngine{}
	discountEngine := &engines.DiscountEngine{}
	budgetEngine := &engines.BudgetEngine{}

	handler := NewUsageHandler(params, costCenterEngine, customerEngine, invoiceEngine, pricingEngine, hydroPublisher, subscriptionEngine, productEngine, usageEngine, discountEngine, budgetEngine)

	assert.NotNil(t, handler)
	assert.Equal(t, params, handler.Handler.HandlerParams)
	assert.Equal(t, costCenterEngine, handler.costCenterEngine)
	assert.Equal(t, customerEngine, handler.customerEngine)
	assert.Equal(t, invoiceEngine, handler.invoiceEngine)
	assert.Equal(t, pricingEngine, handler.pricingEngine)
	assert.Equal(t, hydroPublisher, handler.hydroPublisher)
	assert.Equal(t, subscriptionEngine, handler.subscriptionEngine)
	assert.Equal(t, "hydro_billingplatform_v1_usage", handler.queueName)
}

func mocksWithBasicCostCenter(t *testing.T) (log.Logger, *HandlerParams, *fakes.MockDatabase, *fake.Adapter) {
	items := make([]*models.Item, 0)
	now := time.Now().UTC()
	modelItem := &models.Item{
		Key:          models.Key{Id: "1", PartitionKey: "123:actions_storage:events"},
		Amounts:      &models.Amounts{Quantity: 3},
		Pricing:      &models.Pricing{Sku: "sku1", Price: 5.0},
		EntityDetail: &models.EntityDetail{CustomerId: "123"},
		SourceUri:    "backfill",
		UsageAt:      *models.NewUsageTimeFromTime(now),
	}
	items = append(items, modelItem)

	pager := helpers.MakePagerWithData(t, items)
	pegomock.RegisterMockTestingT(t)
	fakeContainer, telem, statter, logger, db := helpers.SetupMocks(t)
	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(fakeContainer)
	pegomock.When(db.GetStatter()).ThenReturn(statter)
	// This mocks any query where we expect it to return some item data
	pegomock.When(
		fakeContainer.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[*azcosmos.QueryOptions]())).
		ThenReturn(pager)
	// This mocks the query ReadItem for a cost center
	pegomock.When(
		fakeContainer.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[string](),
			pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.StaticTestCostCenter(t),
			nil,
		)
	vexiClient, vexiAdapter := helpers.NewFeatureFlagClient(context.Background(), t, false)
	handlerParams := &HandlerParams{
		statter: statter,
		tracer:  telem.Tracer.Tracer,
		flagger: vexiClient,
	}
	return logger, handlerParams, db, vexiAdapter
}

func mocksWithBasicPricing(t *testing.T) (log.Logger, *HandlerParams, *fakes.MockDatabase, *fake.Adapter) {
	pegomock.RegisterMockTestingT(t)
	fakeContainer, telem, statter, logger, db := helpers.SetupMocks(t)
	vexiClient, vexiAdapter := helpers.NewFeatureFlagClient(context.Background(), t, false)
	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(fakeContainer)
	pegomock.When(db.GetStatter()).ThenReturn(statter)
	// This mocks the query ReadItem for a cost center
	pegomock.When(
		fakeContainer.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Eq("resourceLookup:enterprise:456"),
			pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.StaticTestCostCenter(t),
			nil,
		)
	// This mocks the query ReadItem for a pricing
	pegomock.When(
		fakeContainer.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Eq("sku1"),
			pegomock.Any[*azcosmos.ItemOptions]())).
		ThenReturn(
			helpers.StaticTestPricing(t),
			nil,
		)
	handlerParams := &HandlerParams{
		statter: statter,
		tracer:  telem.Tracer.Tracer,
		flagger: vexiClient,
	}
	return logger, handlerParams, db, vexiAdapter
}

func TestUsageHandler_loadItem(t *testing.T) {
	tests := []struct {
		name                  string
		payload               []byte
		mocks                 func() (log.Logger, *HandlerParams, *fakes.MockDatabase, *fake.Adapter)
		expectedModelItem     *models.Item
		expectedFoundPricing  bool
		expectedCostCenterKey *models.CostCenterKey
		expectedCustomerID    string
		expectedError         string
	}{
		{
			name:    "Invalid protobuf message",
			payload: []byte("This is not a valid protobuf message"),
			mocks: func() (log.Logger, *HandlerParams, *fakes.MockDatabase, *fake.Adapter) {
				return mocksWithBasicCostCenter(t)
			},
			expectedError: "cannot parse invalid wire-format data",
		},
		{
			name: "Invalid envelope message",
			payload: func() []byte {
				env := &hydro_schemas_hydro_v1.Envelope{
					Message: []byte("This is not a valid protobuf message"),
				}
				e, _ := protobuf.Marshal(env)
				return e
			}(),
			mocks: func() (log.Logger, *HandlerParams, *fakes.MockDatabase, *fake.Adapter) {
				return mocksWithBasicCostCenter(t)
			},
			expectedError: "cannot parse invalid wire-format data",
		},
		{
			name: "happy path with no pricing found",
			payload: func() []byte {
				env := &hydro_schemas_hydro_v1.Envelope{
					Message: func() []byte {
						um := hydro_schemas_billingplatform_v1.Usage{
							Entity: &hydro_schemas_billingplatform_v1_entities.EntityDetail{
								CustomerId: 456,
							},
							RepositoryVisibility: hydro_schemas_billingplatform_v1_entities.RepositoryVisibility_PRIVATE,
						}
						m, _ := protobuf.Marshal(&um)
						return m
					}(),
				}
				e, _ := protobuf.Marshal(env)
				return e
			}(),
			mocks: func() (log.Logger, *HandlerParams, *fakes.MockDatabase, *fake.Adapter) {
				return mocksWithBasicCostCenter(t)
			},
			expectedCostCenterKey: &models.CostCenterKey{
				Customer: &models.Customer{
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			expectedCustomerID: "456",
			expectedModelItem: &models.Item{
				Key: models.Key{
					Id: "billable",
				},
				Amounts: &models.Amounts{},
				Pricing: &models.Pricing{
					Price: 0,
				},
			},
		},
		{
			name: "happy path with pricing found",
			payload: func() []byte {
				env := &hydro_schemas_hydro_v1.Envelope{
					Message: func() []byte {
						um := hydro_schemas_billingplatform_v1.Usage{
							Sku:      "sku1",
							Quantity: 10,
							Entity: &hydro_schemas_billingplatform_v1_entities.EntityDetail{
								CustomerId: 456,
							},
							RepositoryVisibility: hydro_schemas_billingplatform_v1_entities.RepositoryVisibility_PRIVATE,
						}
						m, _ := protobuf.Marshal(&um)
						return m
					}(),
				}
				e, _ := protobuf.Marshal(env)
				return e
			}(),
			mocks: func() (log.Logger, *HandlerParams, *fakes.MockDatabase, *fake.Adapter) {
				return mocksWithBasicPricing(t)
			},
			expectedFoundPricing: true,
			expectedCostCenterKey: &models.CostCenterKey{
				Customer: &models.Customer{
					BillingTarget: models.Azure,

					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			expectedCustomerID: "456",
			expectedModelItem: &models.Item{
				Key: models.Key{
					Id: "billable",
				},
				Amounts: &models.Amounts{
					BilledAmount:           50.0,
					FullQuantity:           10000000000,
					Quantity:               10000000000,
					AppliedCostPerQuantity: 5,
				},
				Pricing: &models.Pricing{
					Sku:   "sku1",
					Price: 5.0,
				},
			},
		},
		// Add more test cases here
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup
			pegomock.RegisterMockTestingT(t)

			cfg := &config.Config{
				Environment: "test",
			}
			logger, handlerParams, db, _ := tt.mocks()
			engineParams := engines.NewEngineParams(nil, cfg, db, nil, handlerParams.statter, nil, handlerParams.tracer)

			pricing := engines.NewPricingEngine(engineParams)
			customer := engines.NewCustomerEngine(engineParams)
			costCenter := engines.NewCostCenterEngine(engineParams, pricing, customer)
			handler := NewUsageHandler(handlerParams, costCenter, nil, nil, pricing, nil, nil, nil, nil, nil, nil)
			aItem, foundPricing, cId, repoVisibility, err := handler.loadItem(context.Background(), logger, aqueduct.ReceiveResult{Job: aqueduct.Job{Payload: tt.payload}})
			if tt.expectedError != "" {
				assert.ErrorContains(t, err, tt.expectedError)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, hydro_schemas_billingplatform_v1_entities.RepositoryVisibility_PRIVATE, repoVisibility)
			}
			assert.Equal(t, tt.expectedFoundPricing, foundPricing)
			if tt.expectedCostCenterKey != nil {
				assert.Equal(t, tt.expectedCostCenterKey.Customer.EnterpriseCustomerId, aItem.EntityDetail.CostCenterDetail.EnterpriseCustomerId)
			}

			assert.Equal(t, tt.expectedCustomerID, cId)
			if tt.expectedModelItem != nil {
				assert.Equal(t, tt.expectedModelItem.Key.Id, aItem.Key.Id)
				assert.Equal(t, tt.expectedModelItem.Amounts.BilledAmount, aItem.Amounts.BilledAmount)
				assert.Equal(t, tt.expectedModelItem.Amounts.FullQuantity, aItem.Amounts.FullQuantity)
				assert.Equal(t, tt.expectedModelItem.Amounts.Quantity, aItem.Amounts.Quantity)
				assert.Equal(t, tt.expectedModelItem.Amounts.AppliedCostPerQuantity, aItem.Amounts.AppliedCostPerQuantity)
				assert.Equal(t, tt.expectedModelItem.GetSku(), aItem.GetSku())
				assert.Equal(t, tt.expectedModelItem.GetPrice(), aItem.GetPrice())
			}
		})
	}
}

func TestUsageHandler_createRollupJobs(t *testing.T) {
	usageAtNow := *models.NewUsageTimeFromTime(time.Now().UTC())
	remainingDays := usageAtNow.RemainingDaysInMonth()

	tests := []struct {
		name               string
		item               *models.Item
		costCenterKey      *models.CostCenterKey
		highWatermarkEvent *models.HighWatermarkEvent
		enterpriseInfo     *models.EnterpriseInfo
		readItemResponse   azcosmos.ItemResponse
		expectedRollupJobs int
	}{
		{
			name: "HighWatermarkEvent is nil schedules default number of rollup jobs - 3",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			readItemResponse:   helpers.StaticTestCustomerReadItemResponse(t),
			expectedRollupJobs: 3,
		},
		{
			name: "EnterpriseInfo is nil schedules default number of rollup jobs - 3",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			enterpriseInfo:     nil,
			readItemResponse:   helpers.StaticTestCustomerReadItemResponse(t),
			expectedRollupJobs: 3,
		},
		{
			name: "HighWatermarkEvent is not nil and BillingTarget is Azure gets remaining days in month and schedules rollup jobs for those days",
			item: &models.Item{
				UsageAt: usageAtNow,
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				Pricing: &models.Pricing{
					Price: 100,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						CostCenterUUID:       uuid.New().String(),
						EnterpriseCustomerId: "456",
					},
				},
			},
			highWatermarkEvent: &models.HighWatermarkEvent{
				Quantity: 30,
				UsageAt:  usageAtNow,
			},
			enterpriseInfo:     &models.EnterpriseInfo{BillingTarget: models.Azure},
			readItemResponse:   helpers.StaticTestCustomerReadItemWithAzureBillingResponse(t),
			expectedRollupJobs: remainingDays + 3, // default 3 jobs + azure emission jobs for remaining days
		},
		{
			name: "HighWatermarkEvent is not nil and BillingTarget is Zuora schedules rollup jobs for remaining days in month",
			item: &models.Item{
				UsageAt: usageAtNow,
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				Pricing: &models.Pricing{
					Price: 100,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						CostCenterUUID:       uuid.New().String(),
						EnterpriseCustomerId: "456",
					},
				},
			},
			highWatermarkEvent: &models.HighWatermarkEvent{
				Quantity: 30,
				UsageAt:  usageAtNow,
			},
			enterpriseInfo:     &models.EnterpriseInfo{BillingTarget: models.Zuora},
			readItemResponse:   helpers.StaticTestCustomerReadItemResponse(t),
			expectedRollupJobs: remainingDays + 3, // default 3 jobs + zuora emission jobs for remaining days
		},
		{
			name: "HighWatermarkEvent is nil and BillingTarget is Azure schedules 4 rollup jobs",
			item: &models.Item{
				UsageAt: usageAtNow,
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				Pricing: &models.Pricing{
					Price: 100,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						CostCenterUUID:       uuid.New().String(),
						EnterpriseCustomerId: "456",
					},
				},
			},
			highWatermarkEvent: nil,
			enterpriseInfo:     &models.EnterpriseInfo{BillingTarget: models.Azure},
			readItemResponse:   helpers.StaticTestCustomerReadItemWithAzureBillingResponse(t),
			expectedRollupJobs: 4, // default 3 jobs + 1 azure emission job
		},
		{
			name: "HighWatermarkEvent is nil and BillingTarget is Zuora schedules 4 rollup jobs",
			item: &models.Item{
				UsageAt: usageAtNow,
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				Pricing: &models.Pricing{
					Price: 100,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						CostCenterUUID:       uuid.New().String(),
						EnterpriseCustomerId: "456",
					},
				},
			},
			highWatermarkEvent: nil,
			enterpriseInfo:     &models.EnterpriseInfo{BillingTarget: models.Zuora},
			readItemResponse:   helpers.StaticTestCustomerReadItemResponse(t),
			expectedRollupJobs: 4, // default 3 jobs + 1 zuora emission job
		},
		// Add more test cases here
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup mocks
			pegomock.RegisterMockTestingT(t)
			c, telem, stats, l, db := helpers.SetupMocks(t)
			cfg := &config.Config{
				Environment: "test",
			}
			pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(db.GetConnection()).ThenReturn(c)
			pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
			pegomock.When(db.GetStatter()).ThenReturn(stats)
			// This mocks the query ReadItem for a cost center
			pegomock.When(
				c.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Any[azcosmos.PartitionKey](),
					pegomock.Any[string](),
					pegomock.Any[*azcosmos.ItemOptions]())).
				ThenReturn(
					tt.readItemResponse,
					nil,
				)
			customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)

			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
			handler := &UsageHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer:  telem.Tracer.Tracer,
						statter: stats,
						flagger: vexiClient,
					},
				},
				customerEngine: engines.NewCustomerEngine(customerEngineParams),
			}
			result := handler.createRollupJobs(context.Background(), l, tt.item, tt.highWatermarkEvent, tt.enterpriseInfo)
			assert.Equal(t, tt.expectedRollupJobs, len(result))
		})
	}
}

func TestUsageHandler_writeInvoiceItems(t *testing.T) {
	pegomock.RegisterMockTestingT(t)
	c, telem, stats, l, db := helpers.SetupMocks(t)
	now := time.Now().UTC()
	nowUsageAt := *models.NewUsageTimeFromTime(now)
	month := nowUsageAt.Month()
	year := nowUsageAt.Year()
	tests := []struct {
		name               string
		item               *models.Item
		activeInvoice      *models.ActiveInvoicesItem
		expectedError      error
		expectedDbUpsert   bool
		expectedReadItemId string
	}{
		{
			name: "valid item with active invoice no error",
			item: &models.Item{
				Pricing: &models.Pricing{
					Sku:     "sku1",
					Product: "product1",
				},
				UsageAt: nowUsageAt,
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			activeInvoice: &models.ActiveInvoicesItem{
				Key: &models.Key{
					PartitionKey: "invoices:active:2023:12",
					Id:           fmt.Sprintf("customer:456:invoices:%d:%d", year, month),
				},
				ProcessedAt: &now,
			},
			expectedReadItemId: fmt.Sprintf("customer:456:invoices:%d:%d", year, month),
			expectedError:      nil,
		},
		{
			name: "valid item with no active invoice",
			item: &models.Item{
				Pricing: &models.Pricing{
					Sku:     "sku1",
					Product: "product1",
				},
				UsageAt: nowUsageAt,
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			activeInvoice:      nil,
			expectedReadItemId: fmt.Sprintf("customer:456:invoices:%d:%d", year, month),
			expectedError:      nil,
			expectedDbUpsert:   true,
		},
		// Add more test cases here
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup mocks
			cfg := &config.Config{
				Environment: "test",
			}
			pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(db.GetConnection()).ThenReturn(c)
			pegomock.When(db.GetStatter()).ThenReturn(stats)
			customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)
			pegomock.When(c.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Any[azcosmos.PartitionKey](),
				// Expect this to be the partition key for the active invoice
				pegomock.Eq(tt.expectedReadItemId),
				pegomock.Any[*azcosmos.ItemOptions]())).
				ThenReturn(
					helpers.MockAzureItemResponse(t, tt.activeInvoice), nil)
			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
			handler := &UsageHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer:  telem.Tracer.Tracer,
						statter: stats,
						flagger: vexiClient,
					},
				},
				invoiceEngine: engines.NewInvoiceEngine(customerEngineParams),
			}
			err := handler.writeInvoiceItems(context.Background(), l, tt.item)
			assert.Equal(t, tt.expectedError, err)
			if tt.expectedDbUpsert {
				db.VerifyWasCalled(
					pegomock.Once()).
					UpsertWithOptions(
						pegomock.Any[context.Context](),
						pegomock.Any[log.Logger](),
						pegomock.Any[*models.ActiveInvoicesItem](),
						pegomock.Any[*interfaces.QueryOptions]())
			}
		})
	}
}

func TestUsageHandler_getFreePublicRepDiscount(t *testing.T) {
	now := time.Now().UTC()
	nowUsageAt := *models.NewUsageTimeFromTime(now)
	tests := []struct {
		name                         string
		item                         *models.Item
		customerId                   string
		enterpriseInfo               *models.EnterpriseInfo
		usageTime                    *models.UsageTime
		mockPricing                  *models.Pricing
		mockRepo                     *models.Repo
		expectedError                error
		expectedDiscountTargetAmount int64
		expectedDiscountPercentage   float64
	}{
		{
			name:       "item with no pricing returns no discounts",
			customerId: "123",
			usageTime:  &nowUsageAt,
			item: &models.Item{
				Pricing: &models.Pricing{
					Sku: "sku1",
				},
				UsageAt: nowUsageAt,
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					RepositoryId: 789,
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			enterpriseInfo: &models.EnterpriseInfo{
				BillForPublicRepoUsage: true,
			},
			expectedDiscountPercentage:   0,
			expectedDiscountTargetAmount: 0,
		},
		{
			name:       "item with pricing for public repos should have 100% discount applied if enterprise don't bill for public repos",
			customerId: "123",
			usageTime:  &nowUsageAt,
			item: &models.Item{
				Pricing: &models.Pricing{
					Sku: "sku1",
				},
				UsageAt: nowUsageAt,
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					RepositoryId: 789,
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			enterpriseInfo: &models.EnterpriseInfo{
				BillForPublicRepoUsage: false,
			},
			mockPricing: &models.Pricing{
				Key: &models.Key{
					PartitionKey: "pricing:456:sku1",
					Id:           "sku1",
				},
				FreeForPublicRepos: true,
			},
			mockRepo: &models.Repo{
				RepoKey: &models.RepoKey{
					RepoId: 789,
				},
				IsPublic: true,
			},
			expectedDiscountPercentage:   100,
			expectedDiscountTargetAmount: 0,
		},
		{
			name:       "item with pricing for public repos should have 0 discount if enterprise is billed for public repos",
			customerId: "123",
			usageTime:  &nowUsageAt,
			item: &models.Item{
				Pricing: &models.Pricing{
					Sku: "sku1",
				},
				UsageAt: nowUsageAt,
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					RepositoryId: 789,
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			enterpriseInfo: &models.EnterpriseInfo{
				BillForPublicRepoUsage: true,
			},
			mockPricing: &models.Pricing{
				Key: &models.Key{
					PartitionKey: "pricing:456:sku1",
					Id:           "sku1",
				},
				FreeForPublicRepos: true,
			},
			mockRepo: &models.Repo{
				RepoKey: &models.RepoKey{
					RepoId: 789,
				},
				IsPublic: true,
			},
			expectedDiscountPercentage:   0,
			expectedDiscountTargetAmount: 0,
		},
		// Add more test cases here
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pegomock.RegisterMockTestingT(t)
			c, telem, stats, l, db := helpers.SetupMocks(t)
			cfg := &config.Config{
				Environment: "test",
			}
			pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(db.GetConnection()).ThenReturn(c)
			pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
			pegomock.When(db.GetStatter()).ThenReturn(stats)
			pegomock.When(c.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Any[azcosmos.PartitionKey](),
				pegomock.Eq("customer"), // This checks that we return mocks for the right k.Id
				pegomock.Any[*azcosmos.ItemOptions]())).
				ThenReturn(
					helpers.StaticEnterpriseInfo(t), nil)
			if tt.mockPricing != nil {
				pegomock.When(c.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Any[azcosmos.PartitionKey](),
					pegomock.Eq(tt.mockPricing.Key.Id),
					pegomock.Any[*azcosmos.ItemOptions]())).
					ThenReturn(
						helpers.MockAzureItemResponse(t, tt.mockPricing), nil)
			}
			if tt.mockRepo != nil {
				pegomock.When(c.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Any[azcosmos.PartitionKey](),
					pegomock.Eq(fmt.Sprintf("%d", tt.mockRepo.RepoId)),
					pegomock.Any[*azcosmos.ItemOptions]())).
					ThenReturn(
						helpers.MockAzureItemResponse(t, tt.mockRepo), nil)
			}

			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)

			engineParams := engines.NewEngineParams(nil, cfg, db, vexiClient, stats, nil, telem.Tracer.Tracer)
			customerEngine := engines.NewCustomerEngine(engineParams)
			pricingEngine := engines.NewPricingEngine(engineParams)

			handler := &UsageHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer:  telem.Tracer.Tracer,
						statter: stats,
						flagger: vexiClient,
					},
				},
				customerEngine: customerEngine,
				invoiceEngine:  engines.NewInvoiceEngine(engineParams),
				discountEngine: engines.NewDiscountEngine(engineParams, pricingEngine, nil),
			}

			// Test
			actualDiscount, err := handler.getFreePublicRepoDiscount(context.Background(), l, tt.item, tt.customerId, tt.enterpriseInfo, hydroSchemaEntities.RepositoryVisibility_PUBLIC, tt.usageTime)

			// Assert
			assert.Equal(t, tt.expectedError, err)
			assert.Equal(t, tt.expectedDiscountTargetAmount, actualDiscount.TargetAmount)
			assert.Equal(t, tt.expectedDiscountPercentage, actualDiscount.Percentage)
			if actualDiscount.Targets != nil {
				assert.Equal(t, 1, len(actualDiscount.Targets))
				assert.Equal(t, "sku1", actualDiscount.Targets[0].Id)
			}
		})
	}

}

func TestUsageHandler_handleDiscount(t *testing.T) {
	now := time.Now().UTC()
	nowUsageAt := *models.NewUsageTimeFromTime(now)
	tests := []struct {
		name                               string
		item                               *models.Item
		customer                           *models.Customer
		enterpriseInfo                     *models.EnterpriseInfo
		expectedError                      error
		mockPricing                        *models.Pricing
		mockRepo                           *models.Repo
		mockDiscountState                  *models.DiscountState
		expectedDiscountItem               *models.DiscountItem
		expectedDiscountStatePayloadLength int
	}{
		{
			name: "item with no discount state returns no discount Item and publishes a line item",
			customer: &models.Customer{
				// Add other necessary fields here
				CostCenterDetail: &models.CostCenterDetail{
					EnterpriseCustomerId: "456",
				},
				DiscountPlanName:       "enterprise",
				BillForPublicRepoUsage: false,
			},
			enterpriseInfo: &models.EnterpriseInfo{},
			item: &models.Item{
				Pricing: &models.Pricing{
					Sku: "sku1",
				},
				UsageAt: nowUsageAt,
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					RepositoryId: 789,
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			mockPricing: &models.Pricing{
				Key: &models.Key{
					PartitionKey: "pricing:456:sku1",
					Id:           "sku1",
				},
				FreeForPublicRepos: true,
			},
			mockRepo: &models.Repo{
				RepoKey: &models.RepoKey{
					RepoId: 789,
				},
				IsPublic: true,
			},
			mockDiscountState: &models.DiscountState{
				CurrentAmount: 100,
				TargetAmount:  200,
				Customer: &models.Customer{
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
					DiscountPlanName:       "testDiscountPlan",
					BillForPublicRepoUsage: false,
				},
			},
			expectedError:                      nil,
			expectedDiscountItem:               nil,
			expectedDiscountStatePayloadLength: 0,
		},
		{
			name: "item with discount state returns a discount Item and publishes a line item",
			customer: &models.Customer{
				// Add other necessary fields here
				CostCenterDetail: &models.CostCenterDetail{
					EnterpriseCustomerId: "456",
				},
				DiscountPlanName:       "enterprise",
				BillForPublicRepoUsage: false,
			},
			enterpriseInfo: &models.EnterpriseInfo{
				BillForPublicRepoUsage: false,
				DiscountPlanName:       "enterprise",
			},
			item: &models.Item{
				Pricing: &models.Pricing{
					Sku: "actions_linux",
				},
				UsageAt: nowUsageAt,
				Amounts: &models.Amounts{
					Quantity:               10,
					BilledAmount:           50,
					AppliedCostPerQuantity: 2,
				},
				EntityDetail: &models.EntityDetail{
					RepositoryId: 789,
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			mockPricing: &models.Pricing{
				Key: &models.Key{
					PartitionKey: "pricing:456:sku1",
					Id:           "sku1",
				},
				FreeForPublicRepos: true,
			},
			mockRepo: &models.Repo{
				RepoKey: &models.RepoKey{
					RepoId: 789,
				},
				IsPublic: false,
			},
			mockDiscountState: &models.DiscountState{
				CurrentAmount: 0,
				TargetAmount:  2,
				Customer: &models.Customer{
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
					DiscountPlanName:       "testDiscountPlan",
					BillForPublicRepoUsage: false,
				},
			},
			expectedError: nil,
			expectedDiscountItem: &models.DiscountItem{
				DiscountAmount: 2,
				Quantity:       1000000000,
			},
			expectedDiscountStatePayloadLength: 1,
		},
		// Add more test cases here
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pegomock.RegisterMockTestingT(t)
			c, telem, stats, l, db := helpers.SetupMocks(t)
			cfg := &config.Config{
				Environment: "test",
			}
			pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(db.GetConnection()).ThenReturn(c)
			pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
			pegomock.When(db.GetStatter()).ThenReturn(stats)

			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)

			engineParams := engines.NewEngineParams(nil, cfg, db, vexiClient, stats, nil, telem.Tracer.Tracer)
			customerEngine := engines.NewCustomerEngine(engineParams)
			pricingEngine := engines.NewPricingEngine(engineParams)

			// use this to inspect hydro logs if needed
			var hydroLogs []byte
			stdLogger := stdlog.New(bytes.NewBuffer(hydroLogs), "", 0)
			loghydroPublisher, hErr := hydro.NewPublisher(hydro.NewLogSink(stdLogger))
			assert.NoError(t, hErr)

			handler := &UsageHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer:  telem.Tracer.Tracer,
						statter: stats,
						flagger: vexiClient,
						cfg:     cfg,
						DB:      db,
					},
				},
				customerEngine: customerEngine,
				invoiceEngine:  engines.NewInvoiceEngine(engineParams),
				discountEngine: engines.NewDiscountEngine(engineParams, pricingEngine, nil),
				hydroPublisher: loghydroPublisher,
			}

			if tt.mockPricing != nil {
				pegomock.When(c.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Any[azcosmos.PartitionKey](),
					pegomock.Eq(tt.mockPricing.Key.Id),
					pegomock.Any[*azcosmos.ItemOptions]())).
					ThenReturn(
						helpers.MockAzureItemResponse(t, tt.mockPricing), nil)
			}
			if tt.mockRepo != nil {
				pegomock.When(c.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Any[azcosmos.PartitionKey](),
					pegomock.Eq(fmt.Sprintf("%d", tt.mockRepo.RepoId)),
					pegomock.Any[*azcosmos.ItemOptions]())).
					ThenReturn(
						helpers.MockAzureItemResponse(t, tt.mockRepo), nil)
			}
			if tt.mockDiscountState != nil {
				pegomock.When(c.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Any[azcosmos.PartitionKey](),
					pegomock.Eq("discountState"),
					pegomock.Any[*azcosmos.ItemOptions]())).
					ThenReturn(
						helpers.MockAzureItemResponse(t, tt.mockDiscountState), nil)
			}

			// mock db batch upserts
			pegomock.When(db.Batch(
				pegomock.Any[context.Context](),
				pegomock.Any[models.ItemKey](),
				pegomock.Any[*interfaces.QueryOptions](),
				pegomock.Any[func(batch *azcosmos.TransactionalBatch) error](),
			)).ThenReturn(
				true, nil, nil)
			// Test
			actualDiscountItem, discountStateUpdatePayloads, err := handler.handleDiscount(context.Background(), l, tt.item, tt.customer, tt.enterpriseInfo, hydro_schemas_billingplatform_v1_entities.RepositoryVisibility_PRIVATE)

			// Assert
			assert.Equal(t, tt.expectedError, err)
			assert.Equal(t, tt.expectedDiscountStatePayloadLength, len(discountStateUpdatePayloads))
			if tt.expectedDiscountItem != nil {
				assert.NotNil(t, actualDiscountItem)
				assert.Equal(t, tt.expectedDiscountItem.DiscountAmount, actualDiscountItem.DiscountAmount)
				assert.Equal(t, tt.expectedDiscountItem.Quantity, actualDiscountItem.Quantity)
			}
		})
	}
}

func TestUsageHandler_applyFreePublicRepoDiscount(t *testing.T) {
	mocker := pegomock.WithT(t)
	c, telem, stats, logger, db := helpers.SetupMocks(t)
	cfg := &config.Config{
		Environment: "test",
	}
	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(c)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
	pegomock.When(db.GetStatter()).ThenReturn(stats)

	engineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)
	customerEngine := engines.NewCustomerEngine(engineParams)

	mockHydroPublisher := fakes.NewMockHydroPublisher(mocker)
	mockDiscountEngine := fakes.NewMockDiscountEngineInterface(mocker)

	tests := []struct {
		name       string
		customerId string
	}{
		{
			name:       "a new discount state update payload is added for a testing customer",
			customerId: "1",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
			handler := &UsageHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer:  telem.Tracer.Tracer,
						statter: stats,
						flagger: vexiClient,
						cfg:     cfg,
						DB:      db,
					},
				},
				customerEngine: customerEngine,
				invoiceEngine:  engines.NewInvoiceEngine(engineParams),
				discountEngine: mockDiscountEngine,
				hydroPublisher: mockHydroPublisher,
			}

			// mock true return for PublicRepoDiscountApplicable
			pegomock.When(mockDiscountEngine.PublicRepoDiscountApplicable(
				pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[string](), pegomock.Any[string](), pegomock.Any[int64](), pegomock.Any[billingProto.RepositoryVisibility](), pegomock.Any[bool](),
			)).ThenReturn(true, nil)

			applied, amountAfterDiscount, newDiscountStateUpdate, err := handler.applyFreePublicRepoDiscount(
				context.Background(),
				logger,
				&models.Item{
					Amounts: &models.Amounts{
						BilledAmount: 100,
					},
					EntityDetail: &models.EntityDetail{
						RepositoryId: 123,
						CostCenterDetail: &models.CostCenterDetail{
							EnterpriseCustomerId: tt.customerId,
						},
					},
				},
				&models.Customer{
					CostCenterDetail: &models.CostCenterDetail{EnterpriseCustomerId: tt.customerId},
				},
				&models.EnterpriseInfo{EnterpriseCustomerId: tt.customerId},
				&models.UsageTime{},
				hydro_schemas_billingplatform_v1_entities.RepositoryVisibility_PRIVATE,
			)

			assert.True(t, applied)
			assert.Equal(t, int64(0), amountAfterDiscount)
			assert.Equal(t, int64(100), newDiscountStateUpdate.Amount)
			assert.Equal(t, "1", newDiscountStateUpdate.CustomerId)
			assert.NoError(t, err)
		})
	}
}

func TestUsageHandler_applyPlanDiscount(t *testing.T) {
	mocker := pegomock.WithT(t)
	c, telem, stats, logger, db := helpers.SetupMocks(t)
	cfg := &config.Config{
		Environment: "test",
	}
	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(c)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
	pegomock.When(db.GetStatter()).ThenReturn(stats)

	engineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)
	customerEngine := engines.NewCustomerEngine(engineParams)

	mockHydroPublisher := fakes.NewMockHydroPublisher(mocker)
	mockDiscountEngine := fakes.NewMockDiscountEngineInterface(mocker)

	tests := []struct {
		name       string
		customerId string
	}{
		{
			name:       "a new discount state update payload is added for a testing customer",
			customerId: "1",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
			handler := &UsageHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer:  telem.Tracer.Tracer,
						statter: stats,
						flagger: vexiClient,
						cfg:     cfg,
						DB:      db,
					},
				},
				customerEngine: customerEngine,
				invoiceEngine:  engines.NewInvoiceEngine(engineParams),
				discountEngine: mockDiscountEngine,
				hydroPublisher: mockHydroPublisher,
			}

			// mock return for GetLargestPlanDiscount
			pegomock.When(mockDiscountEngine.GetLargestPlanDiscount(
				pegomock.Any[context.Context](),
				pegomock.Any[log.Logger](),
				pegomock.Any[string](),
				pegomock.Any[*models.Item](),
				pegomock.Any[*models.EnterpriseInfo](),
				pegomock.Any[*models.UsageTime](),
			)).ThenReturn(&models.Discount{
				DiscountKey: &models.DiscountKey{
					Key: &models.Key{
						Id: "12345",
					},
					Uuid: uuid.NewString(),
				},
				TargetAmount: 100,
				Percentage:   100,
			}, nil)

			// mock return for CalculateAmountExceedingDiscountState
			pegomock.When(mockDiscountEngine.CalculateAmountExceedingDiscountState(
				pegomock.Any[context.Context](),
				pegomock.Any[log.Logger](),
				pegomock.Any[string](),
				pegomock.Any[*models.Discount](),
				pegomock.Any[int64](),
				pegomock.Any[int64](),
				pegomock.Any[int64](),
			)).ThenReturn(int64(0), nil)

			applied, amountAfterDiscount, newDiscountStateUpdate, err := handler.applyPlanDiscount(
				context.Background(),
				logger,
				&models.Item{
					Amounts: &models.Amounts{
						BilledAmount:           100,
						AppliedCostPerQuantity: 100,
					},
					EntityDetail: &models.EntityDetail{
						RepositoryId: 123,
						CostCenterDetail: &models.CostCenterDetail{
							EnterpriseCustomerId: tt.customerId,
						},
					},
				},
				&models.Customer{
					CostCenterDetail: &models.CostCenterDetail{EnterpriseCustomerId: tt.customerId},
				},
				&models.EnterpriseInfo{EnterpriseCustomerId: tt.customerId},
				&models.UsageTime{},
			)

			assert.True(t, applied)
			assert.Equal(t, int64(0), amountAfterDiscount)
			assert.Equal(t, int64(100), newDiscountStateUpdate.Amount)
			assert.Equal(t, "1", newDiscountStateUpdate.CustomerId)
			assert.NoError(t, err)
		})
	}
}

func TestUsageHandler_applyConfiguredDiscount(t *testing.T) {
	mocker := pegomock.WithT(t)
	c, telem, stats, logger, db := helpers.SetupMocks(t)
	cfg := &config.Config{
		Environment: "test",
	}
	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(c)
	pegomock.When(db.GetGatewayConnection()).ThenReturn(c)
	pegomock.When(db.GetStatter()).ThenReturn(stats)

	engineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)
	customerEngine := engines.NewCustomerEngine(engineParams)

	mockHydroPublisher := fakes.NewMockHydroPublisher(mocker)
	mockDiscountEngine := fakes.NewMockDiscountEngineInterface(mocker)

	tests := []struct {
		name         string
		customerId   string
		discountType models.DiscountType
	}{
		{
			name:         "a new discount state update payload is added for a testing customer when discount type is dollar discount",
			customerId:   "1",
			discountType: models.DollarDiscountType,
		},
		{
			name:         "a new discount state update payload is added for a testing customer when discount type is percentage discount",
			customerId:   "1",
			discountType: models.PercentageDiscountType,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
			handler := &UsageHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer:  telem.Tracer.Tracer,
						statter: stats,
						flagger: vexiClient,
						cfg:     cfg,
						DB:      db,
					},
				},
				customerEngine: customerEngine,
				invoiceEngine:  engines.NewInvoiceEngine(engineParams),
				discountEngine: mockDiscountEngine,
				hydroPublisher: mockHydroPublisher,
			}

			pegomock.When(mockDiscountEngine.GetLargestConfiguredDiscount(
				pegomock.Any[context.Context](),
				pegomock.Any[log.Logger](),
				pegomock.Any[string](),
				pegomock.Any[*models.Item](),
				pegomock.Any[*models.UsageTime](),
			)).ThenReturn(&models.Discount{
				DiscountKey: &models.DiscountKey{
					Key: &models.Key{
						Id: "12345",
					},
					Uuid: uuid.NewString(),
				},
				TargetAmount: 100,
				Percentage:   100,
			}, tt.discountType, nil)

			applied, amountAfterDiscount, newDiscountStateUpdate, err := handler.applyConfiguredDiscount(
				context.Background(),
				logger,
				&models.Item{
					Amounts: &models.Amounts{
						BilledAmount:           100,
						AppliedCostPerQuantity: 100,
					},
					EntityDetail: &models.EntityDetail{
						RepositoryId: 123,
						CostCenterDetail: &models.CostCenterDetail{
							EnterpriseCustomerId: tt.customerId,
						},
					},
				},
				&models.Customer{
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: tt.customerId,
					},
				},
				&models.UsageTime{},
				int64(100),
			)

			assert.True(t, applied)
			assert.Equal(t, int64(0), amountAfterDiscount)
			assert.Equal(t, int64(100), newDiscountStateUpdate.Amount)
			assert.Equal(t, tt.customerId, newDiscountStateUpdate.CustomerId)
			assert.NoError(t, err)
		})
	}
}

func TestUsageHandler_updateBudgetStates(t *testing.T) {
	tests := []struct {
		name               string
		item               *models.Item
		discountItem       *models.DiscountItem
		budget             *models.Budget
		budgetId           string
		budgetState        *models.BudgetState
		budgetStateId      string
		numDBCalls         int
		preConditionFailed bool
	}{
		{
			name: "Creates budget state when it doesn't exist and usage is for a cost center",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "456", // this is a cost center id
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123", // this is the parent customer id
						CostCenterUUID:       "456",
						IsCostCenterProxy:    true,
					},
				},
			},
			budget: &models.Budget{
				BudgetKey: &models.BudgetKey{
					Key: &models.Key{
						Id:           "budgetId-123",
						PartitionKey: "customer:123:budgets", // budgets are stored using the parent customer id
					},
				},
				BudgetAlerting: &models.BudgetAlerting{
					WillAlert: true,
				},
				Uuid: uuid.NewString(),
			},
			budgetId:           "customer:123:budgets:customer:123",
			budgetState:        nil,
			budgetStateId:      "budgetState",
			numDBCalls:         1,
			preConditionFailed: false,
		},
		{
			name: "Creates budget state when it doesn't exist and usage is not for a cost center",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123",
						IsCostCenterProxy:    false,
					},
				},
			},
			budget: &models.Budget{
				BudgetKey: &models.BudgetKey{
					Key: &models.Key{
						Id:           "budgetId-123",
						PartitionKey: "customer:123:budgets",
					},
				},
				BudgetAlerting: &models.BudgetAlerting{
					WillAlert: true,
				},
				Uuid: uuid.NewString(),
			},
			budgetId:           "customer:123:budgets:customer:123",
			budgetState:        nil,
			budgetStateId:      "budgetState",
			numDBCalls:         1,
			preConditionFailed: false,
		},
		{
			name: "Updates budget state when it does exist and usage is for a cost center",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "456",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123",
						IsCostCenterProxy:    true,
					},
				},
			},
			budget: &models.Budget{
				BudgetKey: &models.BudgetKey{
					Key: &models.Key{
						Id:           "budgetId-123",
						PartitionKey: "customer:123:budgets",
					},
				},
				BudgetAlerting: &models.BudgetAlerting{
					WillAlert: true,
				},
				Uuid: uuid.NewString(),
			},
			budgetId: "customer:123:budgets:customer:123",
			budgetState: &models.BudgetState{
				Key: &models.Key{
					Id:           "budgetId-123:2024:1",
					PartitionKey: "budgetState-pk",
				},
				Quantity:      10,
				CurrentAmount: 10,
				IsFullyFunded: false,
			},
			budgetStateId:      "budgetState",
			numDBCalls:         1,
			preConditionFailed: false,
		},
		{
			name: "Updates budget state when it does exist and usage is not for a cost center",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123",
						IsCostCenterProxy:    false,
					},
				},
			},
			budget: &models.Budget{
				BudgetKey: &models.BudgetKey{
					Key: &models.Key{
						Id:           "budgetId-123",
						PartitionKey: "customer:123:budgets",
					},
				},
				BudgetAlerting: &models.BudgetAlerting{
					WillAlert: true,
				},
				Uuid: uuid.NewString(),
			},
			budgetId: "customer:123:budgets:customer:123",
			budgetState: &models.BudgetState{
				Key: &models.Key{
					Id:           "budgetId-123:2024:1",
					PartitionKey: "budgetState-pk",
				},
				Quantity:      10,
				CurrentAmount: 10,
				IsFullyFunded: false,
			},
			budgetStateId:      "budgetState",
			numDBCalls:         1,
			preConditionFailed: false,
		},
		{
			name: "Updates budget state when it does exist and first pre-condition fails and usage is for a cost center",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "456",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123",
						IsCostCenterProxy:    true,
					},
				},
			},
			budget: &models.Budget{
				BudgetKey: &models.BudgetKey{
					Key: &models.Key{
						Id:           "budgetId-123",
						PartitionKey: "customer:123:budgets",
					},
				},
				BudgetAlerting: &models.BudgetAlerting{
					WillAlert: true,
				},
				Uuid: uuid.NewString(),
			},
			budgetId: "customer:123:budgets:customer:123",
			budgetState: &models.BudgetState{
				Key: &models.Key{
					Id:           "budgetId-123:2024:1",
					PartitionKey: "budgetState-pk",
				},
				Quantity:      10,
				CurrentAmount: 10,
				IsFullyFunded: false,
			},
			budgetStateId:      "budgetState",
			numDBCalls:         2,
			preConditionFailed: true,
		},
		{
			name: "Updates budget state when it does exist and first pre-condition fails and usage is not for a cost center",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123",
						IsCostCenterProxy:    false,
					},
				},
			},
			budget: &models.Budget{
				BudgetKey: &models.BudgetKey{
					Key: &models.Key{
						Id:           "budgetId-123",
						PartitionKey: "customer:123:budgets",
					},
				},
				BudgetAlerting: &models.BudgetAlerting{
					WillAlert: true,
				},
				Uuid: uuid.NewString(),
			},
			budgetId: "customer:123:budgets:customer:123",
			budgetState: &models.BudgetState{
				Key: &models.Key{
					Id:           "budgetId-123:2024:1",
					PartitionKey: "budgetState-pk",
				},
				Quantity:      10,
				CurrentAmount: 10,
				IsFullyFunded: false,
			},
			budgetStateId:      "budgetState",
			numDBCalls:         2,
			preConditionFailed: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup mocks
			pegomock.RegisterMockTestingT(t)
			fakeContainer, telem, stats, l, db := helpers.SetupMocks(t)
			pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
			pegomock.When(db.GetStatter()).ThenReturn(stats)
			cfg := &config.Config{
				Environment: "test",
			}
			engineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)
			events := make(chan hydro.Message, 100)
			sink, err := hydro.NewMemorySink(events)
			assert.Nil(t, err)
			hydroPublisher, err := hydro.NewPublisher(sink)
			assert.Nil(t, err)

			customerEngine := engines.NewCustomerEngine(engineParams)
			budgetEngine := engines.NewBudgetEngine(engineParams, customerEngine)

			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
			handler := &UsageHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer:  telem.Tracer.Tracer,
						statter: stats,
						flagger: vexiClient,
						DB:      db,
					},
				},
				customerEngine: customerEngine,
				budgetEngine:   budgetEngine,
				hydroPublisher: hydroPublisher,
			}

			// mock the the return for a specific budget
			pegomock.When(
				fakeContainer.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Any[azcosmos.PartitionKey](),
					pegomock.Eq(tt.budgetId),
					pegomock.Any[*azcosmos.ItemOptions]()),
			).ThenReturn(
				helpers.StaticTestBudget(t, tt.budget), nil,
			)

			// mock the the return for a specific budget state
			pegomock.When(
				fakeContainer.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Any[azcosmos.PartitionKey](),
					pegomock.Eq(tt.budgetStateId),
					pegomock.Any[*azcosmos.ItemOptions]()),
			).ThenReturn(
				helpers.StaticTestBudgetState(t, tt.budgetState), nil,
			)

			// mock the return as 404 for all other budgets
			pegomock.When(
				fakeContainer.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Eq(azcosmos.NewPartitionKeyString(tt.budget.PartitionKey)),
					pegomock.NotEq(tt.budgetId),
					pegomock.Any[*azcosmos.ItemOptions]()),
			).ThenReturn(
				helpers.StaticTestBudget(t, nil), &azcore.ResponseError{StatusCode: http.StatusNotFound},
			)

			// simulate a pre-condition failure on the first call (etag mismatch due to race condition)
			if tt.preConditionFailed {
				pegomock.When(db.UpsertWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Any[*interfaces.QueryOptions](),
				)).ThenReturn(
					&azcore.ResponseError{StatusCode: http.StatusPreconditionFailed},
				).ThenReturn(nil)
			}

			err = handler.updateBudgetStates(context.Background(), l, []*models.Budget{tt.budget}, tt.item.Amounts, 2010, 12, "sku")
			assert.Nil(t, err)

			if tt.budgetState == nil {
				db.VerifyWasCalled(pegomock.Times(tt.numDBCalls)).CreateWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Any[*interfaces.QueryOptions](),
				)
			} else {
				db.VerifyWasCalled(pegomock.Times(tt.numDBCalls)).UpsertWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Any[*interfaces.QueryOptions](),
				)
			}
		})
	}
}

func TestUsageHandler_getOverageAmounts(t *testing.T) {
	tests := []struct {
		name             string
		item             *models.Item
		maxOverageAmount int64
		expectedOverage  models.Amounts
		expectedToLog    bool
	}{
		{
			name: "Returns amount and logs overage when overage is greater than 0",
			item: &models.Item{
				Amounts: &models.Amounts{
					FullQuantity: 1000000000,  // 1 in nano
					Quantity:     1000000000,  // 1 in nano
					BilledAmount: 10000000000, // 10 in nano
				},
				Pricing: &models.Pricing{
					Sku:   "sku",
					Price: 10000000000, // 10 in nano
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			maxOverageAmount: 10000000000, // 10 in nano,
			expectedOverage: models.Amounts{
				Quantity:     1000000000,  // 1 in nano
				BilledAmount: 10000000000, // 10 in nano
			},
			expectedToLog: true,
		},
		{
			name: "Returns 0 amount and does not log overage when overage is 0",
			item: &models.Item{
				Amounts: &models.Amounts{
					FullQuantity: 1000000000,  // 1 in nano
					Quantity:     1000000000,  // 1 in nano
					BilledAmount: 10000000000, // 10 in nano
				},
				Pricing: &models.Pricing{
					Sku:   "sku",
					Price: 10000000000, // 10 in nano
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			maxOverageAmount: 0, // 0,
			expectedOverage: models.Amounts{
				Quantity:     0, // 0
				BilledAmount: 0, // 0
			},
			expectedToLog: false,
		},
		{
			name: "Returns 0 amount and does not log overage when overage is less than 0",
			item: &models.Item{
				Amounts: &models.Amounts{
					FullQuantity: 1000000000,  // 1 in nano
					Quantity:     1000000000,  // 1 in nano
					BilledAmount: 10000000000, // 10 in nano
				},
				Pricing: &models.Pricing{
					Sku:   "sku",
					Price: 10000000000, // 10 in nano
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			maxOverageAmount: -1, // -1,
			expectedOverage: models.Amounts{
				Quantity:     0, // 0
				BilledAmount: 0, // 0
			},
			expectedToLog: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup mocks
			pegomock.RegisterMockTestingT(t)
			fakeContainer, telem, stats, _, db := helpers.SetupMocks(t)
			pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
			pegomock.When(db.GetStatter()).ThenReturn(stats)
			cfg := &config.Config{
				Environment: "test",
			}
			customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)
			events := make(chan hydro.Message, 100)
			sink, err := hydro.NewMemorySink(events)
			assert.Nil(t, err)
			hydroPublisher, err := hydro.NewPublisher(sink)
			assert.Nil(t, err)
			// get logger that we can assert against
			logger, buffer := helpers.NewTestLogger(t)

			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
			handler := &UsageHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer:  telem.Tracer.Tracer,
						statter: stats,
						flagger: vexiClient,
						DB:      db,
					},
				},
				customerEngine: engines.NewCustomerEngine(customerEngineParams),
				hydroPublisher: hydroPublisher,
			}

			overageAmount := handler.getOverageAmounts(logger, tt.item, tt.maxOverageAmount)
			assert.Equal(t, tt.expectedOverage.BilledAmount, overageAmount.BilledAmount)
			assert.Equal(t, tt.expectedOverage.Quantity, overageAmount.Quantity)
			if tt.expectedToLog {
				assert.Contains(t, buffer.String(), "Overage detected")
			} else {
				assert.NotContains(t, buffer.String(), "Overage detected")
			}
		})
	}
}

func TestUsageHandler_logOverages(t *testing.T) {
	tests := []struct {
		name                    string
		item                    *models.Item
		maxOverageAmount        int64
		overageQuantity         int64
		expectedOverageAmount   int64
		expectedOverageQuantity int64
	}{
		{
			name: "Logs overage",
			item: &models.Item{
				Amounts: &models.Amounts{
					FullQuantity: 1000000000,  // 1 in nano
					Quantity:     1000000000,  // 1 in nano
					BilledAmount: 10000000000, // 10 in nano
				},
				Pricing: &models.Pricing{
					Sku:   "sku",
					Price: 10000000000, // 10 in nano
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			maxOverageAmount:        765000000000, // 765 in nano,
			overageQuantity:         22000000000,  // 22 in nano,
			expectedOverageAmount:   765,
			expectedOverageQuantity: 22,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup mocks
			pegomock.RegisterMockTestingT(t)
			fakeContainer, telem, stats, _, db := helpers.SetupMocks(t)
			pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
			pegomock.When(db.GetStatter()).ThenReturn(stats)
			cfg := &config.Config{
				Environment: "test",
			}
			customerEngineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)
			events := make(chan hydro.Message, 100)
			sink, err := hydro.NewMemorySink(events)
			assert.Nil(t, err)
			hydroPublisher, err := hydro.NewPublisher(sink)
			assert.Nil(t, err)
			// get logger that we can assert against
			logger, buffer := helpers.NewTestLogger(t)

			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
			handler := &UsageHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer:  telem.Tracer.Tracer,
						statter: stats,
						flagger: vexiClient,
						DB:      db,
					},
				},
				customerEngine: engines.NewCustomerEngine(customerEngineParams),
				hydroPublisher: hydroPublisher,
			}

			handler.logOverages(logger, tt.item, tt.maxOverageAmount, tt.overageQuantity)
			assert.Contains(t, buffer.String(), "Overage detected")
			assert.Contains(t, buffer.String(), strconv.FormatInt(int64(tt.expectedOverageQuantity), 10))
			assert.Contains(t, buffer.String(), strconv.FormatInt(int64(tt.expectedOverageAmount), 10))
		})
	}

}

func TestUsageHandler_calculateOverages(t *testing.T) {
	tests := []struct {
		name            string
		item            *models.Item
		discountItem    *models.DiscountItem
		budgets         []*models.Budget
		budgetStates    []*models.BudgetState
		budgetStateId   string
		expectedOverage models.Amounts
		expectedError   string
	}{
		{
			name: "Calculates highest overage when there are multiple budgets",
			item: &models.Item{
				Amounts: &models.Amounts{
					FullQuantity: 1000000000,  // 1 in nano
					Quantity:     1000000000,  // 1 in nano
					BilledAmount: 10000000000, // 10 in nano
				},
				Pricing: &models.Pricing{
					Sku:   "sku",
					Price: 10000000000, // 10 in nano
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			budgets: []*models.Budget{
				{
					BudgetKey: &models.BudgetKey{
						Key: &models.Key{
							Id:           "budgetId-123",
							PartitionKey: "customer:123:budgets",
						},
					},
					BudgetLimitType: models.PreventFurtherUsage,
					BudgetAlerting: &models.BudgetAlerting{
						WillAlert: true,
					},
					Uuid: uuid.NewString(),
				},
				{
					BudgetKey: &models.BudgetKey{
						Key: &models.Key{
							Id:           "budgetId-456",
							PartitionKey: "customer:123:budgets",
						},
					},
					BudgetLimitType: models.PreventFurtherUsage,
					BudgetAlerting: &models.BudgetAlerting{
						WillAlert: true,
					},
					Uuid: uuid.NewString(),
				},
			},
			budgetStates: []*models.BudgetState{
				{
					Key: &models.Key{
						Id:           "budgetState",
						PartitionKey: "budgetId-123:2024:1",
					},
					Quantity:      500000000,   // 0.5 in nano
					CurrentAmount: 5000000000,  // 5 in nano
					TargetAmount:  10000000000, // 10 in nano
					IsFullyFunded: false,
				},
				{
					Key: &models.Key{
						Id:           "budgetState",
						PartitionKey: "budgetId-456:2024:1",
					},
					Quantity:      800000000,   // 0.8 in nano
					CurrentAmount: 8000000000,  // 8 in nano
					TargetAmount:  10000000000, // 10 in nano
					IsFullyFunded: false,
				},
			},
			budgetStateId: "budgetState",
			expectedOverage: models.Amounts{
				// usage is 10
				// budget 1 has 5/10 and budget 2 has 8/10
				// overage for budget 1 is 5 and for budget 2 is 8
				// overage of 8 is higher so we return that
				BilledAmount: 8000000000, // 8 in nano
				Quantity:     800000000,  // 0.8 in nano
			},
		},
		{
			name: "Has 0 overages for alerting only budgets",
			item: &models.Item{
				Amounts: &models.Amounts{
					FullQuantity: 10000000000, // 10 in nano
					Quantity:     10000000000, // 10 in nano
					BilledAmount: 10000000000, // 10 in nano
				},
				Pricing: &models.Pricing{
					Sku:   "sku",
					Price: 1000000000, // 1 in nano
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			budgets: []*models.Budget{
				{
					BudgetKey: &models.BudgetKey{
						Key: &models.Key{
							Id:           "budgetId-123",
							PartitionKey: "customer:123:budgets",
						},
					},
					BudgetLimitType: models.AlertingOnly,
					BudgetAlerting: &models.BudgetAlerting{
						WillAlert: true,
					},
					Uuid: uuid.NewString(),
				},
				{
					BudgetKey: &models.BudgetKey{
						Key: &models.Key{
							Id:           "budgetId-456",
							PartitionKey: "customer:123:budgets",
						},
					},
					BudgetLimitType: models.IgnoreLimit,
					BudgetAlerting: &models.BudgetAlerting{
						WillAlert: true,
					},
					Uuid: uuid.NewString(),
				},
			},
			budgetStates: []*models.BudgetState{
				{
					Key: &models.Key{
						Id:           "budgetState",
						PartitionKey: "budgetId-123:2024:1",
					},
					Quantity:      5000000000,  // 5 in nano
					CurrentAmount: 5000000000,  // 5 in nano
					TargetAmount:  10000000000, // 10 in nano
					IsFullyFunded: false,
				},
				{
					Key: &models.Key{
						Id:           "budgetState",
						PartitionKey: "budgetId-456:2024:1",
					},
					Quantity:      8000000000,  // 8 in nano
					CurrentAmount: 8000000000,  // 8 in nano
					TargetAmount:  10000000000, // 10 in nano
					IsFullyFunded: false,
				},
			},
			budgetStateId: "budgetState",
			expectedOverage: models.Amounts{
				BilledAmount: 0,
				Quantity:     0,
			},
		},
		{
			name: "Has 0 overages when there are no budgets",
			item: &models.Item{
				Amounts: &models.Amounts{
					FullQuantity: 10000000000, // 10 in nano
					Quantity:     10000000000, // 10 in nano
					BilledAmount: 10000000000, // 10 in nano
				},
				Pricing: &models.Pricing{
					Sku:   "sku",
					Price: 1000000000, // 1 in nano
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			budgets:       []*models.Budget{},
			budgetStates:  []*models.BudgetState{},
			budgetStateId: "budgetState",
			expectedOverage: models.Amounts{
				BilledAmount: 0,
				Quantity:     0,
			},
		},
		{
			name: "Returns error when there's an issue fetching budget state",
			item: &models.Item{
				Amounts: &models.Amounts{
					FullQuantity: 10000000000, // 10 in nano
					Quantity:     10000000000, // 10 in nano
					BilledAmount: 10000000000, // 10 in nano
				},
				Pricing: &models.Pricing{
					Sku:   "sku",
					Price: 1000000000, // 1 in nano

				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "456",
					},
				},
			},
			budgets: []*models.Budget{
				{
					BudgetKey: &models.BudgetKey{
						Key: &models.Key{
							Id:           "budgetId-123",
							PartitionKey: "customer:123:budgets",
						},
					},
					BudgetLimitType: models.AlertingOnly,
					BudgetAlerting: &models.BudgetAlerting{
						WillAlert: true,
					},
					Uuid: uuid.NewString(),
				},
			},
			budgetStates:  []*models.BudgetState{},
			budgetStateId: "budgetState",
			expectedOverage: models.Amounts{
				BilledAmount: 0,
				Quantity:     0,
			},
			expectedError: "failed to calculate overages: failed to get budget state",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup mocks
			pegomock.RegisterMockTestingT(t)
			fakeContainer, telem, stats, l, db := helpers.SetupMocks(t)
			pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
			pegomock.When(db.GetStatter()).ThenReturn(stats)
			cfg := &config.Config{
				Environment: "test",
			}
			engineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)
			events := make(chan hydro.Message, 100)
			sink, err := hydro.NewMemorySink(events)
			assert.Nil(t, err)
			hydroPublisher, err := hydro.NewPublisher(sink)
			assert.Nil(t, err)

			customerEngine := engines.NewCustomerEngine(engineParams)
			budgetEngine := engines.NewBudgetEngine(engineParams, customerEngine)

			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
			handler := &UsageHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer:  telem.Tracer.Tracer,
						statter: stats,
						flagger: vexiClient,
						DB:      db,
					},
				},
				customerEngine: customerEngine,
				budgetEngine:   budgetEngine,
				hydroPublisher: hydroPublisher,
			}

			for _, budgetState := range tt.budgetStates {
				pegomock.When(
					fakeContainer.ReadItem(
						pegomock.Any[context.Context](),
						pegomock.Eq(azcosmos.NewPartitionKeyString(budgetState.PartitionKey)),
						pegomock.Eq(tt.budgetStateId),
						pegomock.Any[*azcosmos.ItemOptions]()),
				).ThenReturn(
					helpers.StaticTestBudgetState(t, budgetState), nil,
				)
			}

			overageAmount, err := handler.calculateOverages(context.Background(), l, tt.budgets, tt.item.Amounts, tt.item, 2024, 1)
			if tt.expectedError != "" {
				assert.NotNil(t, err)
				assert.Contains(t, err.Error(), tt.expectedError)
			} else {
				assert.Nil(t, err)
				assert.Equal(t, tt.expectedOverage.BilledAmount, overageAmount.BilledAmount)
				assert.Equal(t, tt.expectedOverage.Quantity, overageAmount.Quantity)
			}
		})
	}
}

func TestUsageHandler_calculateOverages_NoBudgetStates(t *testing.T) {
	pegomock.RegisterMockTestingT(t)
	fakeContainer, telem, stats, l, db := helpers.SetupMocks(t)
	pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
	pegomock.When(db.GetStatter()).ThenReturn(stats)
	cfg := &config.Config{
		Environment: "test",
	}
	engineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)
	events := make(chan hydro.Message, 100)
	sink, err := hydro.NewMemorySink(events)
	assert.Nil(t, err)
	hydroPublisher, err := hydro.NewPublisher(sink)
	assert.Nil(t, err)

	customerEngine := engines.NewCustomerEngine(engineParams)
	budgetEngine := engines.NewBudgetEngine(engineParams, customerEngine)

	vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
	handler := &UsageHandler{
		Handler: &Handler{
			HandlerParams: &HandlerParams{
				tracer:  telem.Tracer.Tracer,
				statter: stats,
				flagger: vexiClient,
				DB:      db,
			},
		},
		customerEngine: customerEngine,
		budgetEngine:   budgetEngine,
		hydroPublisher: hydroPublisher,
	}

	budget := &models.Budget{
		BudgetKey: &models.BudgetKey{
			Key: &models.Key{
				Id:           "budgetId-123",
				PartitionKey: "customer:123:budgets",
			},
		},
		BudgetLimitType: models.AlertingOnly,
		BudgetAlerting: &models.BudgetAlerting{
			WillAlert: true,
		},
		Uuid: uuid.NewString(),
	}

	item := &models.Item{
		Amounts: &models.Amounts{
			FullQuantity: 10000000000, // 10 in nano
			Quantity:     10000000000, // 10 in nano
			BilledAmount: 10000000000, // 10 in nano
		},
		Pricing: &models.Pricing{
			Sku:   "sku",
			Price: 1000000000, // 1 in nano

		},
		EntityDetail: &models.EntityDetail{
			CustomerId: "123",
			CostCenterDetail: &models.CostCenterDetail{
				EnterpriseCustomerId: "456",
			},
		},
	}

	pegomock.When(
		fakeContainer.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Eq(azcosmos.NewPartitionKeyString(budget.Key.PartitionKey)),
			pegomock.Eq(budget.Key.Id),
			pegomock.Any[*azcosmos.ItemOptions]()),
	).ThenReturn(
		helpers.StaticTestBudget(t, budget), nil,
	)

	pegomock.When(
		fakeContainer.ReadItem(
			pegomock.Any[context.Context](),
			pegomock.Eq(azcosmos.NewPartitionKeyString(budget.ToBudgetStateKey(2024, 1, "budgetState").PartitionKey)),
			pegomock.Eq("budgetState"),
			pegomock.Any[*azcosmos.ItemOptions]()),
	).ThenReturn(
		azcosmos.ItemResponse{}, mocks.AzureNotFoundErr,
	)
	overageAmount, err := handler.calculateOverages(context.Background(), l, []*models.Budget{budget}, item.Amounts, item, 2024, 1)
	assert.Nil(t, err)
	assert.Equal(t, int64(0), overageAmount.BilledAmount)
	assert.Equal(t, int64(0), overageAmount.Quantity)
}

func TestUsageHandler_PublishLineItemMessage(t *testing.T) {
	tests := []struct {
		name           string
		item           *models.Item
		discountItem   *models.DiscountItem
		customer       *models.Customer
		enterpriseInfo *models.EnterpriseInfo
		overageAmount  *models.Amounts
	}{
		{
			name: "Publishes a line item message for Zuora",
			item: &models.Item{
				UsageAt: *models.NewUsageTimeFromTime(time.Now().UTC()),
				Key: models.Key{
					Id:           "billable",
					PartitionKey: "some-random-uuid",
				},
				Amounts: &models.Amounts{
					Quantity:     10,
					BilledAmount: 20,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId:     "123",
					OrganizationId: 6,
					RepositoryId:   5,
					ActorId:        4,
					CostCenterDetail: &models.CostCenterDetail{
						IsCostCenterProxy:    false,
						EnterpriseCustomerId: "123",
					},
				},
				Pricing: &models.Pricing{
					Product:  "actions",
					Sku:      "actions_storage",
					UnitType: models.UnitTypeGigabyteHours,
					Price:    2,
				},
			},
			customer: &models.Customer{
				BillingTarget: models.Zuora,
				CostCenterDetail: &models.CostCenterDetail{
					IsCostCenterProxy:    false,
					EnterpriseCustomerId: "123",
				},
			},
			discountItem: nil,
			enterpriseInfo: &models.EnterpriseInfo{
				ZuoraAccountNumber: "test-zuora-account-number",
			},
			overageAmount: &models.Amounts{
				Quantity:     0,
				BilledAmount: 0,
			},
		},
		{
			name: "Publishes a line item message for Azure",
			item: &models.Item{
				UsageAt: *models.NewUsageTimeFromTime(time.Now().UTC()),
				Key: models.Key{
					Id:           "billable",
					PartitionKey: "some-random-uuid",
				},
				Amounts: &models.Amounts{
					Quantity:     10,
					BilledAmount: 20,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId:     "123",
					OrganizationId: 6,
					RepositoryId:   5,
					ActorId:        4,
					CostCenterDetail: &models.CostCenterDetail{
						IsCostCenterProxy:    false,
						EnterpriseCustomerId: "123",
					},
				},
				Pricing: &models.Pricing{
					AzureMeterId: "some-azure-meter-id",
					Product:      "actions",
					Sku:          "actions_storage",
					UnitType:     models.UnitTypeGigabyteHours,
					Price:        2,
				},
			},
			customer: &models.Customer{
				BillingTarget: models.Azure,
				CostCenterDetail: &models.CostCenterDetail{
					IsCostCenterProxy:    false,
					EnterpriseCustomerId: "123",
				},
			},
			discountItem: nil,
			enterpriseInfo: &models.EnterpriseInfo{
				AzureAccountId: "test-azure-account-id",
			},
			overageAmount: &models.Amounts{
				Quantity:     0,
				BilledAmount: 0,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Mock the time since the handler uses time.Now() to get the current time
			currentTime := time.Now()
			now = func() time.Time {
				return currentTime
			}

			mockHydroPublisher := fakes.NewMockHydroPublisher(pegomock.WithT(t))

			// mock produce returns to test zuora usage identifiers as payment processor product ID
			mockProductEngine := fakes.NewMockProductEngineInterface(pegomock.WithT(t))
			mockProduct := &models.Product{
				ZuoraUsageIdentifier: "some-zuora-usage-identifier",
			}
			pegomock.When(mockProductEngine.Get(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[string](), pegomock.Any[bool]())).ThenReturn(mockProduct, nil)

			_, telem, _, _, db := helpers.SetupMocks(t)
			pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)

			handler := NewUsageHandler(&HandlerParams{tracer: db.GetTracer(), DB: db, flagger: vexiClient}, nil, nil, nil, nil, mockHydroPublisher, nil, mockProductEngine, nil, nil, nil)
			handler.PublishLineItemMessage(
				context.Background(),
				log.NewNullLogger(),
				tt.customer,
				tt.item,
				tt.discountItem,
				tt.enterpriseInfo,
				tt.overageAmount,
			)

			hydroMessage := hydro_schemas_billingplatform_v1.UsageLineItem{
				UsageUuid:              tt.item.PartitionKey,
				SourceUri:              tt.item.SourceUri,
				CustomerId:             tt.item.EntityDetail.CustomerId,
				Product:                tt.item.Pricing.Product,
				Sku:                    tt.item.Pricing.Sku,
				Quantity:               tt.item.Amounts.ToDecimal().Quantity,
				GrossAmount:            tt.item.Amounts.ToDecimal().BilledAmount,
				NetAmount:              tt.item.ToDecimal().BilledAmount,
				DiscountAmount:         0,
				AppliedCostPerQuantity: models.ToDecimalAmount(tt.item.Pricing.Price),
				ActorId:                tt.item.EntityDetail.ActorId,
				RepoId:                 tt.item.EntityDetail.RepositoryId,
				OrgId:                  tt.item.EntityDetail.OrganizationId,
				OverageQuantity:        tt.overageAmount.ToDecimal().Quantity,
				OverageAmount:          tt.overageAmount.ToDecimal().BilledAmount,
				UsageAt:                timestamppb.New(tt.item.UsageAt.Time),
				ProcessedAt:            timestamppb.New(currentTime.UTC()),
				Target:                 tt.customer.GetHydroBillingTarget(),
				UnitType:               tt.item.Pricing.UnitType.String(),
				CostCenter:             nil,
				BillingTargetId:        "",
				BillingTargetChargeId:  "",
			}

			if tt.customer.BillingTarget == models.Zuora {
				mockProductEngine.VerifyWasCalledOnce().Get(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[string](), pegomock.Any[bool]())

				hydroMessage.BillingTargetId = tt.enterpriseInfo.ZuoraAccountNumber
				hydroMessage.BillingTargetChargeId = mockProduct.ZuoraUsageIdentifier
			} else if tt.customer.BillingTarget == models.Azure {
				hydroMessage.BillingTargetId = tt.enterpriseInfo.AzureAccountId
				hydroMessage.BillingTargetChargeId = tt.item.Pricing.AzureMeterId
			}

			mockHydroPublisher.VerifyWasCalledOnce().Publish(&hydroMessage)
		})
	}
}
