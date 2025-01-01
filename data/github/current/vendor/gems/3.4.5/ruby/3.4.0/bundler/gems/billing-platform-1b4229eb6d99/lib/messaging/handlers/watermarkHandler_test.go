package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydro_schemas_billingplatform_v1 "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydro_schemas_billingplatform_v1_entities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/internal/monolith"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/billing-platform/testing/mocks"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	statsmocks "github.com/github/go-stats/mocks"
	schemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	repositories "github.com/github/monolith-twirp-billing/repositories/v1"
	"github.com/petergtz/pegomock/v4"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/twitchtv/twirp"
	protobuf "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestNewWatermarkHandler_InitializedWithCorrectQueueName(t *testing.T) {
	// Arrange
	params := &HandlerParams{}
	// Act
	handler := NewWatermarkHandler(params, nil, nil, nil, nil, nil)
	// Assert
	assert.NotNil(t, handler)
	assert.Equal(t, handler.queueName, "watermark-handler")
}

func TestNewWatermarkHandler_InitializedWithCorrectWorkerType(t *testing.T) {
	// Arrange
	params := &HandlerParams{}
	// Act
	handler := NewWatermarkHandler(params, nil, nil, nil, nil, nil)
	// Assert
	assert.NotNil(t, handler)
	assert.IsType(t, &models.WatermarkJob{}, handler.watermarkJob)
}

func TestWatermarkHandler_validateHandlerDetails_SendToDeadLetterQueue(t *testing.T) {
	tests := []struct {
		name          string
		payload       func() []byte
		statterReason stats.Tags
	}{
		{
			name:          "DeadLetterOnEmptyPayload",
			payload:       func() []byte { return nil },
			statterReason: stats.Tags{"origin": "unmarshal.err"},
		},
		{
			name:          "DeadLetterOnMalformedPayload",
			payload:       func() []byte { return []byte(`{this is not a valid json pagerData`) },
			statterReason: stats.Tags{"origin": "unmarshal.err"},
		},
		{
			name:          "DeadLetterOnMissingCustomerId",
			payload:       func() []byte { return []byte(`{"jobId": "1234"}`) },
			statterReason: stats.Tags{"origin": "customer.err"},
		},
		{
			name: "DeadLetterOnMissingPartitionDetail",
			payload: func() []byte {
				job := models.WatermarkJob{
					ActiveCustomer: &models.Key{
						PartitionKey: "123:actions:events",
						Id:           "123",
					},
				}
				payload, _ := json.Marshal(job)
				return payload
			},
			statterReason: stats.Tags{"origin": "partitionDetail.err"},
		},
		{
			name: "DeadLetterMissingWatermarkJob",
			payload: func() []byte {
				job := models.WatermarkJob{
					ActiveCustomer: &models.Key{
						PartitionKey: "123:actions:events",
						Id:           "123",
					},
					PartitionDetail: &models.UsagePartitionDetail{
						UsageEntityId: "123",
						Product:       "product1",
						Sku:           "sku1",
						RepoId:        123,
						OrgId:         123,
					}}

				payload, _ := json.Marshal(job)
				return payload
			},
			statterReason: stats.Tags{"origin": "jobRun.err"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Arrange
			mockClient := fakes.MockAqueductClient{}

			pegomock.RegisterMockTestingT(t)
			statter := statsmocks.Client{}
			statter.Mock.On("Timing", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("time.Duration")).Return(nil)
			statter.Mock.On("Counter", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Return(nil)
			telem, tErr := telemetry.NewFromEnv()
			assert.NoError(t, tErr)
			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
			handler := NewWatermarkHandler(&HandlerParams{
				statter:        &statter,
				tracer:         telem.Tracer.Tracer,
				aqueductClient: &mockClient,
				flagger:        vexiClient,
			},
				nil,
				nil,
				nil,
				nil,
				nil,
			)

			// Act
			err := handler.ProcessMessage(context.Background(), log.NewNullLogger(), aqueduct.ReceiveResult{Job: aqueduct.Job{Payload: tt.payload()}})

			// Assert
			assert.Nil(t, err)
			_, deadLetter, _ := mockClient.VerifyWasCalled(pegomock.Times(1)).Send(pegomock.Any[context.Context](), pegomock.Any[aqueduct.Job](), pegomock.Any[aqueduct.SendOption]()).GetCapturedArguments()
			assert.NotNil(t, deadLetter)
			assert.Equal(t, "dead-letter-watermark-handler", deadLetter.Queue)
			assert.Equal(t, tt.payload(), deadLetter.Payload)
			statter.AssertCalled(t, "Counter", "watermark_handler.error", tt.statterReason, int64(1))
		})
	}
}

func JobPayload1() []byte {
	job := models.WatermarkJob{
		ActiveCustomer: &models.Key{
			PartitionKey: "123:product1:sku1",
			Id:           "123",
		},
		PartitionDetail: &models.UsagePartitionDetail{
			UsageEntityId: "123",
			Product:       "product1",
			Sku:           "sku1",
			RepoId:        123,
			OrgId:         123,
		},
		JobRun: &models.WatermarkJobRun{
			CustomerId: "123",
			Sku:        "sku1",
		},
	}
	payload, _ := json.Marshal(job)
	return payload
}

func TestWatermarkHandler_ProcessMessage(t *testing.T) {

	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)
	tomorrow := now.AddDate(0, 0, 1)

	tests := []struct {
		name                 string
		receivedJob          []byte
		pagerData            []*models.Item
		statterCounterReason string
	}{
		{
			name:                 "No Rollups emits rollup error",
			pagerData:            []*models.Item{},
			receivedJob:          JobPayload1(),
			statterCounterReason: "customer.rollups",
		},
		{
			name: "Pricing effective in the future emits not enabled for emission error",
			pagerData: []*models.Item{
				{
					Key:          models.Key{Id: "1", PartitionKey: "123:sku1:events:rollups"},
					Amounts:      &models.Amounts{Quantity: 3, FractionalQuantity: 2},
					Pricing:      &models.Pricing{Sku: "sku1", Price: 5.0, EffectiveAt: models.NewUsageTimeFromTime(tomorrow).Unix()},
					EntityDetail: &models.EntityDetail{CustomerId: "123"},
					SourceUri:    "backfill",
					UsageAt:      *models.NewUsageTimeFromTime(now),
				},
			},
			receivedJob:          JobPayload1(),
			statterCounterReason: "rollup.is_enabled_for_emission",
		},
		{
			name: "Pricing effective yesterday has no errors",
			pagerData: []*models.Item{
				{
					Key:          models.Key{Id: "1", PartitionKey: "123:sku1:events:rollups"},
					Amounts:      &models.Amounts{Quantity: 3, FractionalQuantity: 2},
					Pricing:      &models.Pricing{Sku: "sku1", Price: 5.0, EffectiveAt: models.NewUsageTimeFromTime(yesterday).Unix()},
					EntityDetail: &models.EntityDetail{CustomerId: "123"},
					SourceUri:    "backfill",
					UsageAt:      *models.NewUsageTimeFromTime(now),
				},
			},
			receivedJob:          JobPayload1(),
			statterCounterReason: "",
		},
		{
			name: "Pricing effective now has no errors",
			pagerData: []*models.Item{
				{
					Key:          models.Key{Id: "1", PartitionKey: "123:sku1:events:rollups"},
					Amounts:      &models.Amounts{Quantity: 3, FractionalQuantity: 2},
					Pricing:      &models.Pricing{Sku: "sku1", Price: 5.0, EffectiveAt: models.NewUsageTimeFromTime(now).Unix()},
					EntityDetail: &models.EntityDetail{CustomerId: "123"},
					SourceUri:    "backfill",
					UsageAt:      *models.NewUsageTimeFromTime(now),
				},
			},
			receivedJob:          JobPayload1(),
			statterCounterReason: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Arrange
			ac := &fakes.MockAqueductClient{}
			pager := helpers.MakePagerWithData(t, tt.pagerData)
			pegomock.RegisterMockTestingT(t)
			fakeContainer, telem, statter, logger, db := helpers.SetupMocks(t)
			pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
			pegomock.When(db.GetStatter()).ThenReturn(statter)
			pegomock.When(fakeContainer.NewQueryItemsPager(pegomock.Any[string](), pegomock.Any[azcosmos.PartitionKey](), pegomock.Any[*azcosmos.QueryOptions]())).ThenReturn(pager)
			cfg := &config.Config{
				Environment: "test",
			}

			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
			params := &HandlerParams{
				statter:        statter,
				tracer:         telem.Tracer.Tracer,
				aqueductClient: ac,
				flagger:        vexiClient,
			}

			engineParams := engines.NewEngineParams(ac, cfg, db, vexiClient, statter, nil, telem.Tracer.Tracer)
			pricingEngine := fakes.NewMockPricingEngineInterface()
			discountEngine := fakes.NewMockDiscountEngineInterface()

			handler := NewWatermarkHandler(params, nil, engines.NewUsageEngine(engineParams), pricingEngine, discountEngine, nil)

			// Act
			err := handler.ProcessMessage(context.Background(), logger, aqueduct.ReceiveResult{Job: aqueduct.Job{Payload: tt.receivedJob}})

			// Assert
			assert.Nil(t, err)
			if tt.statterCounterReason != "" {
				statter.AssertCalled(t, "Counter", "watermark_handler.error", stats.Tags{"origin": tt.statterCounterReason}, int64(1))
			}
		})
	}

}

func TestWatermarkHandler_filterFutureRollups(t *testing.T) {
	now := time.Now().UTC()
	tests := []struct {
		name     string
		rollups  []*models.Item
		jobRun   *models.WatermarkJobRun
		expected []*models.Item
	}{
		{
			name: "UsageAt before JobRun",
			rollups: []*models.Item{
				{
					UsageAt: *models.NewUsageTimeFromTime(now.Add(-2 * time.Hour)),
				},
			},
			expected: []*models.Item{
				{
					UsageAt: *models.NewUsageTimeFromTime(now.Add(-2 * time.Hour)),
				},
			},
		},
		{
			name: "UsageAt equal to JobRun",
			rollups: []*models.Item{
				{
					UsageAt: *models.NewUsageTimeFromTime(now),
				},
			},
			expected: []*models.Item{
				{
					UsageAt: *models.NewUsageTimeFromTime(now),
				},
			},
		},
		{
			name: "UsageAt after JobRun",
			rollups: []*models.Item{
				{
					UsageAt: *models.NewUsageTimeFromTime(now.Add(2 * time.Hour)),
				},
			},
			expected: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			jobRun := &models.WatermarkJobRun{
				Year:  int64(now.Year()),
				Month: int64(now.Month()),
				Day:   int64(now.Day()),
				Hour:  int64(now.Hour()),
			}
			handler := &WatermarkHandler{
				watermarkJob: &models.WatermarkJob{
					JobRun: jobRun,
				},
			}
			result := handler.filterFutureRollups(tt.rollups)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestWatermarkHandler_rollupsToMap(t *testing.T) {
	now := time.Now().UTC()
	tests := []struct {
		name     string
		rollups  []*models.Item
		expected *sync.Map
	}{
		{
			name:     "Empty rollups",
			rollups:  []*models.Item{},
			expected: &sync.Map{},
		},
		{
			name: "Single rollup with same day",
			rollups: []*models.Item{
				{
					UsageAt: *models.NewUsageTimeFromTime(now),
					EntityDetail: &models.EntityDetail{
						CustomerId:     "123",
						OrganizationId: 456,
						RepositoryId:   789,
					},
					Amounts: &models.Amounts{
						FractionalQuantity: 240,
					},
					Pricing: &models.Pricing{
						Price: 1.0,
					},
				},
			},
			expected: func() *sync.Map {
				m := &sync.Map{}
				m.Store("123:456:789", nano.NewFromInt(10))
				return m
			}(),
		},
		{
			name: "Single rollup with different day",
			rollups: []*models.Item{
				{
					UsageAt: *models.NewUsageTimeFromTime(now.Add(-24 * time.Hour)),
					EntityDetail: &models.EntityDetail{
						CustomerId:     "123",
						OrganizationId: 456,
						RepositoryId:   789,
					},
					Amounts: &models.Amounts{
						Quantity: 480,
					},
					Pricing: &models.Pricing{
						Price: 1,
					},
				},
			},
			expected: func() *sync.Map {
				m := &sync.Map{}
				m.Store("123:456:789", nano.NewFromInt(20))
				return m
			}(),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			telem, _ := telemetry.NewFromEnv()

			jobRun := &models.WatermarkJobRun{
				Year:  int64(now.Year()),
				Month: int64(now.Month()),
				Day:   int64(now.Day()),
				Hour:  int64(now.Hour()),
			}
			handler := &WatermarkHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer: telem.Tracer.Tracer,
					},
				},
				watermarkJob: &models.WatermarkJob{
					JobRun: jobRun,
				},
			}
			result := handler.rollupsToMap(context.Background(), tt.rollups)
			result.Range(func(key, value interface{}) bool {
				v, ok := tt.expected.Load(key)
				assert.True(t, ok)
				ev := v.(*nano.Nano)
				av := value.(*nano.Nano)
				assert.Equal(t, ev.Int64(), av.Int64())
				return true
			})
		})
	}
}

func TestWatermarkHandler_rollupsToMapForTotals(t *testing.T) {
	now := time.Now().UTC()
	tests := []struct {
		name     string
		rollups  []*models.WatermarkTotalItem
		expected *sync.Map
	}{
		{
			name:     "Empty rollups",
			rollups:  []*models.WatermarkTotalItem{},
			expected: &sync.Map{},
		},
		{
			name: "Single rollup with same day",
			rollups: []*models.WatermarkTotalItem{
				{
					EntityDetail: &models.EntityDetail{
						CustomerId:     "123",
						OrganizationId: 456,
						RepositoryId:   789,
					},
					AmountsItem: &models.AmountsItem{
						Amounts: &models.Amounts{
							Quantity: 10,
						},
					},
				},
			},
			expected: func() *sync.Map {
				m := &sync.Map{}
				m.Store("123:456:789", nano.NewFromInt(10))
				return m
			}(),
		},
		{
			name: "Single rollup with different day",
			rollups: []*models.WatermarkTotalItem{
				{
					EntityDetail: &models.EntityDetail{
						CustomerId:     "123",
						OrganizationId: 456,
						RepositoryId:   789,
					},
					AmountsItem: &models.AmountsItem{
						Amounts: &models.Amounts{
							Quantity: 10,
						},
					},
				},
			},
			expected: func() *sync.Map {
				m := &sync.Map{}
				m.Store("123:456:789", nano.NewFromInt(10))
				return m
			}(),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			telem, _ := telemetry.NewFromEnv()

			jobRun := &models.WatermarkJobRun{
				Year:  int64(now.Year()),
				Month: int64(now.Month()),
				Day:   int64(now.Day()),
				Hour:  int64(now.Hour()),
			}
			handler := &WatermarkHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer: telem.Tracer.Tracer,
					},
				},
				watermarkJob: &models.WatermarkJob{
					JobRun: jobRun,
				},
			}
			result := handler.rollupsToMapForTotals(context.Background(), tt.rollups)
			result.Range(func(key, value interface{}) bool {
				v, ok := tt.expected.Load(key)
				assert.True(t, ok)
				ev := v.(*nano.Nano)
				av := value.(*nano.Nano)
				assert.Equal(t, ev.Int64(), av.Int64())
				return true
			})
		})
	}
}

func TestWatermarkHandler_generateLineItems(t *testing.T) {
	tests := []struct {
		name                   string
		quantityByEntity       *sync.Map
		pricing                *models.Pricing
		appliedCostPerQuantity int64
		expected               []*models.Item
	}{
		{
			name: "Test with one entity",
			quantityByEntity: func() *sync.Map {
				m := &sync.Map{}
				m.Store("123:456:789", nano.NewFromInt(10))
				return m
			}(),
			pricing: &models.Pricing{
				Price: 5.0,
			},
			appliedCostPerQuantity: 100,
			expected: []*models.Item{
				{
					Key: models.Key{
						Id:           "123",
						PartitionKey: "123:product1:events",
					},
					Pricing: &models.Pricing{
						Price: 5.0,
					},
					Amounts: &models.Amounts{
						Quantity:               10,
						AppliedCostPerQuantity: 100,
					},
					EntityDetail: &models.EntityDetail{
						CustomerId:     "123",
						OrganizationId: 456,
						RepositoryId:   789,
					},
				},
			},
		},
		{
			name: "Test with no entities",
			quantityByEntity: func() *sync.Map {
				m := &sync.Map{}
				return m
			}(),
			pricing: &models.Pricing{
				Price: 5.0,
			},
			appliedCostPerQuantity: 100,
			expected:               nil,
		},
		// Add more test cases here
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			telem, _ := telemetry.NewFromEnv()
			statter := &mocks.Statter{}
			handler := &WatermarkHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						statter: statter,
						tracer:  telem.Tracer.Tracer,
					},
				},
				watermarkJob: &models.WatermarkJob{
					ActiveCustomer: &models.Key{
						Id:           "123",
						PartitionKey: "123:product1:events",
					},
				},
			}
			result := handler.generateLineItems(context.Background(), tt.quantityByEntity, tt.pricing, tt.appliedCostPerQuantity)
			assert.Equal(t, len(tt.expected), len(result))
			for i := range tt.expected {
				assert.Equal(t, tt.expected[i].Quantity, result[i].Quantity)
				assert.Equal(t, tt.expected[i].AppliedCostPerQuantity, result[i].AppliedCostPerQuantity)
				assert.Equal(t, tt.expected[i].GetPrice(), result[i].GetPrice())
				assert.Equal(t, tt.expected[i].EntityDetail.CustomerId, result[i].EntityDetail.CustomerId)
				assert.Equal(t, tt.expected[i].Key.Id, result[i].Key.Id)
			}
		})
	}
}

func TestWatermarkHandler_emitLineItems(t *testing.T) {
	now := time.Now().UTC()
	tests := []struct {
		name                          string
		customerId                    string
		lineItems                     []*models.Item
		expectedError                 error
		expectedStatterCount          int64
		expectedStatterCounter        string
		expectedQueue                 string
		expectedHydroEvent            *hydro_schemas_billingplatform_v1.Usage
		expectedQueryRepoVisibilities bool
	}{
		{
			name:          "Empty lineItems",
			customerId:    "123",
			lineItems:     []*models.Item{},
			expectedError: nil,
		},
		{
			name:       "CustomerID is not valid number",
			customerId: "123",
			lineItems: []*models.Item{
				{
					EntityDetail: &models.EntityDetail{
						CustomerId: "abc",
					},
					Pricing: &models.Pricing{},
				},
			},
			expectedError:          errors.WithStack(errors.New("Failed to parse customer id: strconv.ParseInt: parsing \"abc\": invalid syntax")),
			expectedStatterCounter: "watermark_handler.error",
			expectedStatterCount:   1,
		},
		{
			name:       "Single lineItem happy path returns no error",
			customerId: "123",
			lineItems: []*models.Item{
				{
					Key: models.Key{
						Id:           "123",
						PartitionKey: "123:product1:events",
					},
					Pricing: &models.Pricing{
						Price: 5.0,
						Sku:   "sku1",
					},
					Amounts: &models.Amounts{
						Quantity:               1000000000, // Note quantity is scaled by ToNanoCents
						AppliedCostPerQuantity: 100,
					},
					EntityDetail: &models.EntityDetail{
						CustomerId:     "123",
						OrganizationId: 456,
						RepositoryId:   789,
						ActorId:        100,
					},
				},
			},
			expectedQueue: "hydro_billingplatform_v1_usage",
			expectedHydroEvent: &hydro_schemas_billingplatform_v1.Usage{
				Sku:       "sku1",
				Quantity:  1, // Note quantity is scaled by ToNanoCents
				SourceUri: models.InternallyProcessedEvent,
				UsageAt:   timestamppb.New(now),
				Entity: &hydro_schemas_billingplatform_v1_entities.EntityDetail{
					CustomerId:     123,
					OrganizationId: 456,
					RepoId:         789,
					ActorId:        100,
				},
				UsageUuid: fmt.Sprintf("123:sku1:456:789:%d:%d:%d:%d", now.Year(), now.Month(), now.Day(), now.Hour()),
			},
			expectedStatterCount:   1,
			expectedStatterCounter: "watermark_handler.send_usage",
			expectedError:          nil,
		},
		{
			name:       "Quantity is 0",
			customerId: "123",
			lineItems: []*models.Item{
				{
					Key: models.Key{
						Id:           "123",
						PartitionKey: "123:product1:events",
					},
					Pricing: &models.Pricing{
						Price: 5.0,
					},
					Amounts: &models.Amounts{
						Quantity:               0,
						AppliedCostPerQuantity: 100,
					},
					EntityDetail: &models.EntityDetail{
						CustomerId:     "123",
						OrganizationId: 456,
						RepositoryId:   789,
					},
				},
			},
			expectedError:          nil,
			expectedStatterCount:   1,
			expectedStatterCounter: "watermark_handler.negative_or_zero_quantity",
		},
		{
			name:       "Billed amount is 0",
			customerId: "123",
			lineItems: []*models.Item{
				{
					Key: models.Key{
						Id:           "123",
						PartitionKey: "123:product1:events",
					},
					Pricing: &models.Pricing{
						Price: 5.0,
					},
					Amounts: &models.Amounts{
						Quantity:               10,
						AppliedCostPerQuantity: 100,
						BilledAmount:           -1,
					},
					EntityDetail: &models.EntityDetail{
						CustomerId:     "123",
						OrganizationId: 456,
						RepositoryId:   789,
					},
				},
			},
			expectedError:          nil,
			expectedStatterCount:   1,
			expectedStatterCounter: "watermark_handler.negative_or_zero_amount",
		},
		{
			name:       "Queries visibilities when free for public repos is true",
			customerId: "1",
			lineItems: []*models.Item{
				{
					Key: models.Key{
						Id:           "123",
						PartitionKey: "123:product1:events",
					},
					Pricing: &models.Pricing{
						Price:              5.0,
						FreeForPublicRepos: true,
						Sku:                "sku1",
					},
					Amounts: &models.Amounts{
						Quantity:               1000000000, // Note quantity is scaled by ToNanoCents
						AppliedCostPerQuantity: 100,
						BilledAmount:           1,
					},
					EntityDetail: &models.EntityDetail{
						CustomerId:     "1",
						OrganizationId: 456,
						RepositoryId:   789,
					},
				},
			},
			expectedQueryRepoVisibilities: true,
			expectedStatterCount:          1,
			expectedStatterCounter:        "watermark.handler.get_repo_metadata",
			expectedQueue:                 "throttled-watermark",
			expectedHydroEvent: &hydro_schemas_billingplatform_v1.Usage{
				Sku:       "sku1",
				Quantity:  1, // Note quantity is scaled by ToNanoCents
				SourceUri: models.InternallyProcessedEvent,
				UsageAt:   timestamppb.New(now),
				Entity: &hydro_schemas_billingplatform_v1_entities.EntityDetail{
					CustomerId:     1,
					OrganizationId: 456,
					RepoId:         789,
				},
				UsageUuid:            fmt.Sprintf("1:sku1:456:789:%d:%d:%d:%d", now.Year(), now.Month(), now.Day(), now.Hour()),
				RepositoryVisibility: hydro_schemas_billingplatform_v1_entities.RepositoryVisibility_PUBLIC,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockClient := &fakes.MockAqueductClient{}
			statter := statsmocks.Client{}
			statter.Mock.On("Counter", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Return(nil)
			pegomock.RegisterMockTestingT(t)
			telem, _ := telemetry.NewFromEnv()

			mocker := pegomock.WithT(t)
			discountEngine := fakes.NewMockDiscountEngineInterface(mocker)
			mockMonolithClient := monolith.Client{
				RepositoryAPI: fakes.NewMockRepositoryAPI(mocker),
			}
			vexiClient, vexiAdapter := helpers.NewFeatureFlagClient(context.Background(), t, false)
			handler := &WatermarkHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						aqueductClient: mockClient,
						cfg: &config.Config{
							Environment: "test",
						},
						statter: &statter,
						tracer:  telem.Tracer.Tracer,
						flagger: vexiClient,
					},
				},
				watermarkJob: &models.WatermarkJob{
					ActiveCustomer: &models.Key{
						Id:           "123",
						PartitionKey: "123:sku1:events",
					},
					PartitionDetail: &models.UsagePartitionDetail{
						Sku: "sku1",
					},
					JobRun: &models.WatermarkJobRun{
						Year:  int64(now.Year()),
						Month: int64(now.Month()),
						Day:   int64(now.Day()),
						Hour:  int64(now.Hour()),
					},
				},
				discountEngine: discountEngine,
				monolithClient: &mockMonolithClient,
			}
			vexiAdapter.AddFeatureFlag("billing_platform_send_usage_to_throttled_watermark_queue", false) // create flag but disabled globally
			vexiAdapter.AddActors("billing_platform_send_usage_to_throttled_watermark_queue", []string{"Customer:1"})

			if tt.expectedQueryRepoVisibilities {
				pegomock.When(discountEngine.GetCachedRepositoryMetadata(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[int64]())).ThenReturn(nil, nil)
				pegomock.When(mockMonolithClient.RepositoryAPI.GetRepositoryMetadata(pegomock.Any[context.Context](), pegomock.Any[*repositories.GetRepositoryMetadataRequest]())).ThenReturn(&repositories.GetRepositoryMetadataResponse{
					Repository: &repositories.Repository{
						IsPublic: true,
						Id:       789,
					},
				}, nil)
			}

			err := handler.emitLineItems(context.Background(), log.NewNullLogger(), aqueduct.ReceiveResult{Job: aqueduct.Job{Payload: JobPayload1()}}, tt.lineItems, tt.customerId)
			if tt.expectedHydroEvent != nil {
				InspectAqSendLineItems(t, mockClient, tt.expectedHydroEvent, tt.expectedQueue)
			}
			if tt.expectedError != nil {
				assert.EqualError(t, err, tt.expectedError.Error())
			} else {
				assert.Nil(t, err)
			}
			if len(statter.Calls) > 0 {
				assert.Equal(t, tt.expectedStatterCount, statter.Mock.Calls[0].Arguments[2])
				assert.Equal(t, tt.expectedStatterCounter, statter.Mock.Calls[0].Arguments[0])
			}
		})
	}
}

func InspectAqSendLineItems(t *testing.T, ac *fakes.MockAqueductClient, expectedHydroEvent *hydro_schemas_billingplatform_v1.Usage, expectedQueue string) {
	usageAsBytes, err := protobuf.Marshal(expectedHydroEvent)
	assert.NoError(t, err)
	envelope := schemas.Envelope{
		Message: usageAsBytes,
	}
	envAsBytes, err := protobuf.Marshal(&envelope)
	assert.NoError(t, err)
	ExpectedJob := aqueduct.Job{
		Payload: envAsBytes,
		App:     "billing-platform-development",
		Queue:   expectedQueue,
	}

	_, actualJobs, _ := ac.VerifyWasCalled(pegomock.AtLeast(1)).Send(
		pegomock.Any[context.Context](),
		pegomock.Any[aqueduct.Job](),
		pegomock.Any[aqueduct.SendOption](),
	).GetAllCapturedArguments()

	actualJob := actualJobs[0]

	var actualEnv schemas.Envelope
	err = protobuf.Unmarshal(actualJob.Payload, &actualEnv)
	assert.NoError(t, err)
	var actualJobBytes hydro_schemas_billingplatform_v1.Usage
	err = protobuf.Unmarshal(actualEnv.Message, &actualJobBytes)
	assert.NoError(t, err)

	assert.Equal(t, ExpectedJob.Queue, actualJob.Queue, "Queues don't match")
	assert.Equal(t, expectedHydroEvent.Quantity, actualJobBytes.Quantity, "Quantities don't match")
	assert.Equal(t, expectedHydroEvent.Sku, actualJobBytes.Sku, "Skus don't match")
	assert.Equal(t, expectedHydroEvent.UsageUuid, actualJobBytes.UsageUuid, "UsageUuids don't match")
	// match on the start of the hour
	assert.Equal(t, expectedHydroEvent.GetUsageAt().AsTime().Hour(), actualJobBytes.GetUsageAt().AsTime().Hour(), "UsageAt hours don't match")
	assert.Equal(t, expectedHydroEvent.GetRepositoryVisibility(), actualJobBytes.GetRepositoryVisibility(), "RepositoryVisibility don't match")

	assert.Equal(t, len(actualJobs), 1, "expected only 1 job to be sent")
}

func Test_getRepositoryVisibilities_largeNumLineItems(t *testing.T) {
	mockClient := &fakes.MockAqueductClient{}
	statter := statsmocks.Client{}
	statter.Mock.On("Counter", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Return(nil)
	pegomock.RegisterMockTestingT(t)
	telem, _ := telemetry.NewFromEnv()

	mocker := pegomock.WithT(t)
	mockRepoAPI := fakes.NewMockRepositoryAPI(mocker)
	discountEngine := fakes.NewMockDiscountEngineInterface(mocker)
	mockMonolithClient := monolith.Client{
		RepositoryAPI: mockRepoAPI,
	}

	vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)

	pegomock.When(mockMonolithClient.RepositoryAPI.GetRepositoryMetadata(pegomock.Any[context.Context](), pegomock.Any[*repositories.GetRepositoryMetadataRequest]())).ThenReturn(&repositories.GetRepositoryMetadataResponse{}, nil)
	pegomock.When(discountEngine.GetCachedRepositoryMetadata(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[int64]())).ThenReturn(nil, nil)

	handler := &WatermarkHandler{
		Handler: &Handler{
			HandlerParams: &HandlerParams{
				aqueductClient: mockClient,
				cfg: &config.Config{
					Environment: "test",
				},
				statter: &statter,
				tracer:  telem.Tracer.Tracer,
				flagger: vexiClient,
			},
		},
		discountEngine: discountEngine,
		monolithClient: &mockMonolithClient,
	}

	lineItems := make([]*models.Item, 3001)
	for i := range lineItems {
		lineItems[i] = &models.Item{
			Key: models.Key{
				Id:           "123",
				PartitionKey: "123:product1:events",
			},
			Pricing: &models.Pricing{
				FreeForPublicRepos: true,
			},
			EntityDetail: &models.EntityDetail{
				// ensure no repoID of 0
				RepositoryId: int64(i + 1),
			},
		}
	}

	_, err := handler.getRepositoryVisibilities(context.TODO(), log.NewNullLogger(), lineItems)
	assert.NoError(t, err)

	// assert we have made the expected number of calls
	mockRepoAPI.VerifyWasCalled(pegomock.Times(3001)).GetRepositoryMetadata(pegomock.Any[context.Context](), pegomock.Any[*repositories.GetRepositoryMetadataRequest]())

	// assert a call was made for each repo ID
	for i := range lineItems {
		mockRepoAPI.VerifyWasCalled(pegomock.Times(1)).GetRepositoryMetadata(pegomock.Any[context.Context](), pegomock.Eq(&repositories.GetRepositoryMetadataRequest{
			Id: uint64(lineItems[i].EntityDetail.RepositoryId),
		}))
	}
}

func Test_getRepositoryVisibility_NotFound(t *testing.T) {
	mockClient := &fakes.MockAqueductClient{}
	statter := statsmocks.Client{}
	statter.Mock.On("Counter", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Return(nil)
	pegomock.RegisterMockTestingT(t)
	telem, _ := telemetry.NewFromEnv()

	mocker := pegomock.WithT(t)
	mockRepoAPI := fakes.NewMockRepositoryAPI(mocker)
	discountEngine := fakes.NewMockDiscountEngineInterface(mocker)
	mockMonolithClient := monolith.Client{
		RepositoryAPI: mockRepoAPI,
	}

	vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)

	pegomock.When(mockMonolithClient.RepositoryAPI.GetRepositoryMetadata(pegomock.Any[context.Context](), pegomock.Any[*repositories.GetRepositoryMetadataRequest]())).ThenReturn(nil, twirp.NotFoundError("not found"))
	pegomock.When(discountEngine.GetCachedRepositoryMetadata(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[int64]())).ThenReturn(nil, nil)

	handler := &WatermarkHandler{
		Handler: &Handler{
			HandlerParams: &HandlerParams{
				aqueductClient: mockClient,
				cfg: &config.Config{
					Environment: "test",
				},
				statter: &statter,
				tracer:  telem.Tracer.Tracer,
				flagger: vexiClient,
			},
		},
		discountEngine: discountEngine,
		monolithClient: &mockMonolithClient,
	}

	visibility, err := handler.getRepositoryVisibility(context.TODO(), log.NewNullLogger(), 1)
	assert.NoError(t, err)

	// assert we have made the expected number of calls
	mockRepoAPI.VerifyWasCalled(pegomock.Times(1)).GetRepositoryMetadata(pegomock.Any[context.Context](), pegomock.Any[*repositories.GetRepositoryMetadataRequest]())
	discountEngine.VerifyWasCalled(pegomock.Times(1)).GetCachedRepositoryMetadata(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[int64]())

	assert.Equal(t, hydro_schemas_billingplatform_v1_entities.RepositoryVisibility_PUBLIC, visibility)
}
