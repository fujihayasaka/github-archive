package engines

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/bperrors"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/feature-management-client-go/vexi/adapter/fake"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
)

type TestUsageObject struct {
	usageEngine            *UsageEngine
	mocker                 pegomock.Option
	activeUsageItemQuerier *fakes.MockQuerier[*models.ActiveUsageItem]
	itemQuerier            *fakes.MockQuerier[*models.Item]
	discountItemQuerier    *fakes.MockQuerier[*models.DiscountItem]
	pricingEngine          PricingEngineInterface
	pricingQuerier         *fakes.MockQuerier[*models.Pricing]
	mockDB                 *fakes.MockDatabase
	aqueductClient         *fakes.MockAqueductClient
	topOrgRepoQuerier      *fakes.MockQuerier[*models.TopOrgRepo]
	vexiFakeAdapter        *fake.Adapter
}

func InitializeUsageTestObject(t *testing.T) TestUsageObject {
	mocker := pegomock.WithT(t)
	activeUsageItemQuerier := fakes.NewMockQuerier[*models.ActiveUsageItem](mocker)
	itemQuerier := fakes.NewMockQuerier[*models.Item](mocker)
	discountItemQuerier := fakes.NewMockQuerier[*models.DiscountItem](mocker)
	topOrgRepoQuerier := fakes.NewMockQuerier[*models.TopOrgRepo](mocker)
	watermarkTotalItemQuerier := fakes.NewMockQuerier[*models.WatermarkTotalItem](mocker)
	pricingQuerier := fakes.NewMockQuerier[*models.Pricing](mocker)
	gatewayPricingQuerier := fakes.NewMockQuerier[*models.Pricing](mocker)
	mockDB := fakes.NewMockDatabase(mocker)
	aqueductClient := &fakes.MockAqueductClient{}
	_, _, stats, _, _ := helpers.SetupMocks(t)

	cfg := &config.Config{
		Environment: "test",
	}

	vexiClient, vexiAdapter := helpers.NewFeatureFlagClient(context.Background(), t, false)

	engineParams := &EngineParams{
		db:             mockDB,
		cfg:            cfg,
		aqueductClient: aqueductClient,
		statter:        stats,
		flagger:        vexiClient,
	}
	pricingEngine := NewPricingEngineWithQuerier(engineParams, pricingQuerier, gatewayPricingQuerier)

	testObject := newUsageEngineWithQuerier(engineParams, activeUsageItemQuerier, itemQuerier, discountItemQuerier, topOrgRepoQuerier, watermarkTotalItemQuerier, pricingEngine)
	return TestUsageObject{
		usageEngine:            testObject,
		mocker:                 mocker,
		activeUsageItemQuerier: activeUsageItemQuerier,
		itemQuerier:            itemQuerier,
		discountItemQuerier:    discountItemQuerier,
		pricingEngine:          pricingEngine,
		pricingQuerier:         pricingQuerier,
		mockDB:                 mockDB,
		aqueductClient:         aqueductClient,
		topOrgRepoQuerier:      topOrgRepoQuerier,
		vexiFakeAdapter:        vexiAdapter,
	}
}

func TestUsage_WriteActiveUsageItems(t *testing.T) {

	pegomock.RegisterMockTestingT(t)
	now := time.Now().UTC()
	nowUsageAt := *models.NewUsageTimeFromTime(now)
	year := nowUsageAt.Year()
	month := nowUsageAt.Month()
	day := nowUsageAt.Day()
	partitionKey := fmt.Sprintf("activeUsageItems:%d:%d:%d", year, month, day)
	customerId := "123"

	mockBillingItem := &models.Item{
		Pricing: &models.Pricing{
			Sku:     "sku1",
			Product: "product1",
		},
		UsageAt: nowUsageAt,
		EntityDetail: &models.EntityDetail{
			CustomerId: customerId,
			CostCenterDetail: &models.CostCenterDetail{
				EnterpriseCustomerId: customerId,
			},
		},
	}

	tests := []struct {
		name               string
		item               *models.Item
		customer           *models.Customer
		constructorError   error
		expectedReadItemId string
		expectedReadError  error
		mockUsageItemRead  *models.ActiveUsageItem
		expectedDbUpsert   bool
		expectedWriteError error
		mockUsageItemWrite *models.ActiveUsageItem
	}{
		{
			name: "If no record exists and new BillingTarget is Zuora, create new record",
			item: mockBillingItem,
			customer: &models.Customer{
				BillingTarget: models.Zuora,
			},
			constructorError:   nil,
			expectedReadItemId: customerId,
			expectedReadError:  nil,
			mockUsageItemRead:  nil,
			expectedDbUpsert:   true,
			expectedWriteError: nil,
			mockUsageItemWrite: &models.ActiveUsageItem{
				Key: &models.Key{
					PartitionKey: partitionKey,
					Id:           customerId,
				},
				Target: models.BillingTarget(models.Zuora),
			},
		},
		{
			name: "If no record exists and new BillingTarget is Azure, create new record",
			item: mockBillingItem,
			customer: &models.Customer{
				BillingTarget: models.Azure,
			},
			constructorError:   nil,
			expectedReadItemId: customerId,
			expectedReadError:  nil,
			mockUsageItemRead:  nil,
			expectedDbUpsert:   true,
			expectedWriteError: nil,
			mockUsageItemWrite: &models.ActiveUsageItem{
				Key: &models.Key{
					PartitionKey: partitionKey,
					Id:           customerId,
				},
				Target: models.BillingTarget(models.Azure),
			},
		},
		{
			name: "If record exists with BillingTarget of Zuora and the new BillingTarget is Azure, update record",
			item: mockBillingItem,
			customer: &models.Customer{
				BillingTarget: models.Azure,
			},
			expectedReadItemId: customerId,
			expectedReadError:  nil,
			mockUsageItemRead: &models.ActiveUsageItem{
				Key: &models.Key{
					PartitionKey: partitionKey,
					Id:           customerId,
				},
				Target: models.BillingTarget(models.Zuora),
			},
			expectedDbUpsert:   true,
			expectedWriteError: nil,
			mockUsageItemWrite: &models.ActiveUsageItem{
				Key: &models.Key{
					PartitionKey: partitionKey,
					Id:           customerId,
				},
				Target: models.BillingTarget(models.Azure),
			},
		},
		{
			name: "If record exists with BillingTarget of Zuora and the new BillingTarget is still Zuora, do not update record",
			item: mockBillingItem,
			customer: &models.Customer{
				BillingTarget: models.Zuora,
			},
			expectedReadItemId: customerId,
			expectedReadError:  nil,
			mockUsageItemRead: &models.ActiveUsageItem{
				Key: &models.Key{
					PartitionKey: partitionKey,
					Id:           customerId,
				},
				Target: models.BillingTarget(models.Zuora),
			},
			expectedDbUpsert:   false,
			expectedWriteError: nil,
			mockUsageItemWrite: nil,
		},
		{
			name: "If record exists with BillingTarget of Azure and the new BillingTarget is still Azure, do not update record",
			item: mockBillingItem,
			customer: &models.Customer{
				BillingTarget: models.Azure,
			},
			constructorError:   nil,
			expectedReadItemId: customerId,
			expectedReadError:  nil,
			mockUsageItemRead: &models.ActiveUsageItem{
				Key: &models.Key{
					PartitionKey: partitionKey,
					Id:           customerId,
				},
				Target: models.BillingTarget(models.Azure),
			},
			expectedDbUpsert:   false,
			expectedWriteError: nil,
			mockUsageItemWrite: nil,
		},
		{
			name: "If record exists with BillingTarget of Azure and the new BillingTarget is Zuora, update record",
			item: mockBillingItem,
			customer: &models.Customer{
				BillingTarget: models.Zuora,
			},
			constructorError:   nil,
			expectedReadItemId: customerId,
			expectedReadError:  nil,
			mockUsageItemRead: &models.ActiveUsageItem{
				Key: &models.Key{
					PartitionKey: partitionKey,
					Id:           customerId,
				},
				Target: models.BillingTarget(models.Azure),
			},
			expectedDbUpsert:   true,
			expectedWriteError: nil,
			mockUsageItemWrite: &models.ActiveUsageItem{
				Key: &models.Key{
					PartitionKey: partitionKey,
					Id:           customerId,
				},
				Target: models.BillingTarget(models.Zuora),
			},
		},
		{
			name: "If Item is not found, return error",
			item: nil,
			customer: &models.Customer{
				BillingTarget: models.Zuora,
			},
			constructorError:   bperrors.NewError(bperrors.Internal, errors.New("item cannot be null")),
			expectedReadItemId: "",
			expectedReadError:  nil,
			mockUsageItemRead:  nil,
			expectedDbUpsert:   false,
			expectedWriteError: nil,
			mockUsageItemWrite: nil,
		},
		{
			name:               "If Customer is not found, return error",
			item:               mockBillingItem,
			customer:           nil,
			constructorError:   bperrors.NewError(bperrors.Internal, errors.New("customer cannot be null")),
			expectedReadItemId: "",
			expectedReadError:  nil,
			mockUsageItemRead:  nil,
			expectedDbUpsert:   false,
			expectedWriteError: nil,
			mockUsageItemWrite: nil,
		},
		{
			name: "If there is a database read error, return error",
			item: mockBillingItem,
			customer: &models.Customer{
				BillingTarget: models.Zuora,
			},
			constructorError:   nil,
			expectedReadItemId: customerId,
			expectedReadError:  errors.New("document read exploded"),
			mockUsageItemRead:  nil,
			expectedDbUpsert:   false,
			expectedWriteError: nil,
			mockUsageItemWrite: nil,
		},
		{
			name: "If there is a database write error, return error",
			item: mockBillingItem,
			customer: &models.Customer{
				BillingTarget: models.Zuora,
			},
			constructorError:   nil,
			expectedReadItemId: customerId,
			expectedReadError:  nil,
			mockUsageItemRead:  nil,
			expectedDbUpsert:   true,
			expectedWriteError: errors.New("document write exploded"),
			mockUsageItemWrite: &models.ActiveUsageItem{
				Key: &models.Key{
					PartitionKey: partitionKey,
					Id:           customerId,
				},
				Target: models.BillingTarget(models.Azure),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup mocks
			c, telem, stats, l, db := helpers.SetupMocks(t)
			cfg := &config.Config{
				Environment: "test",
			}
			pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(db.GetConnection()).ThenReturn(c)
			pegomock.When(db.GetStatter()).ThenReturn(stats)
			engineParams := NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)

			pegomock.When(c.ReadItem(
				pegomock.Any[context.Context](),
				// Expect this to be the partition key for the active usage item
				pegomock.Eq(azcosmos.NewPartitionKeyString(partitionKey)),
				// Expect this to be the record ID for the active usage item
				pegomock.Eq(tt.expectedReadItemId),
				pegomock.Any[*azcosmos.ItemOptions]())).
				ThenReturn(
					helpers.MockAzureItemResponse(t, tt.mockUsageItemRead), tt.expectedReadError)

			if tt.expectedWriteError != nil {
				pegomock.When(db.UpsertWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Any[*interfaces.QueryOptions]())).
					ThenReturn(tt.expectedWriteError)
			}

			usageEngine := NewUsageEngine(engineParams)
			err := usageEngine.WriteActiveUsageItems(context.Background(), l, tt.item, tt.customer)

			if tt.constructorError != nil {
				assert.EqualError(t, err, tt.constructorError.Error())
			}

			if tt.expectedReadError != nil {
				wrappedExpectedReadError := bperrors.NewError(bperrors.Internal, tt.expectedReadError)
				assert.Equal(t, wrappedExpectedReadError, err)
			}

			if tt.expectedDbUpsert {
				if tt.expectedWriteError != nil {
					wrappedExpectedWriteError := bperrors.NewError(bperrors.Internal, tt.expectedWriteError)
					assert.Equal(t, wrappedExpectedWriteError, err)
				} else {
					db.VerifyWasCalled(
						pegomock.Once()).
						UpsertWithOptions(
							pegomock.Any[context.Context](),
							pegomock.Any[log.Logger](),
							pegomock.Eq(tt.mockUsageItemWrite),
							pegomock.Any[*interfaces.QueryOptions]())
				}
			}

			// If we aren't expecting any errors, assert that the error is nil
			if tt.constructorError == nil && tt.expectedReadError == nil && tt.expectedWriteError == nil {
				assert.NoError(t, err)
			}
		})
	}
}

func TestUsage_ScheduleEmission(t *testing.T) {

	pegomock.RegisterMockTestingT(t)
	sYear := 2024
	sMonth := 10
	sDay := 10
	dateStr := fmt.Sprintf("%04d:%02d:%02d", sYear, sMonth, sDay)
	customerId := "123"
	customerId2 := "456"
	partitionKey := fmt.Sprintf("ghec_seats:%s:%s", dateStr, "byZuoraEmission")
	partitionKey2 := fmt.Sprintf("actions_storage:%s:%s", dateStr, "byZuoraEmission")

	t.Logf("Using partition key: %s", partitionKey)

	mockUsageItemQuery := []*models.Item{
		{
			Key: models.Key{
				PartitionKey: partitionKey,
				Id:           fmt.Sprintf("%s:%s:%s", customerId, "ghec_seats", "2024:10:10"),
			},
			EntityDetail: &models.EntityDetail{
				CustomerId: customerId,
				CostCenterDetail: &models.CostCenterDetail{
					EnterpriseCustomerId: customerId,
				},
			},
			Pricing: &models.Pricing{
				Product: "ghec",
				Sku:     "ghec_seats",
			},
		},
		{
			Key: models.Key{
				PartitionKey: partitionKey2,
				Id:           fmt.Sprintf("%s:%s:%s", customerId2, "actions_storage", "2024:10:10"),
			},
			EntityDetail: &models.EntityDetail{
				CustomerId: customerId2,
				CostCenterDetail: &models.CostCenterDetail{
					EnterpriseCustomerId: customerId2,
				},
			},
			Pricing: &models.Pricing{
				Product: "actions",
				Sku:     "actions_storage",
			},
		},
	}

	actionsRolloutEffectiveAt := time.Date(2023, 7, 14, 20, 30, 0, 0, time.UTC).Unix()

	// Prepare mock pricing data
	mockPricings := []*models.Pricing{
		{
			Price:              int64(1000 * 0.008),
			Sku:                "actions_storage",
			FriendlyName:       "Actions Storage",
			Product:            "actions",
			AzureMeterId:       "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
			MeterType:          models.PricingMeterDefault,
			FreeForPublicRepos: true,
			EffectiveAt:        actionsRolloutEffectiveAt,
			UnitType:           models.UnitTypeMinutes,
		},
		{
			Price:              int64(1000 * 0.064),
			Sku:                "actions_storage",
			FriendlyName:       "Actions Storage",
			Product:            "actions",
			AzureMeterId:       "cdc3163b-3623-5f85-9c2b-980c77501091",
			MeterType:          models.PricingMeterDefault,
			FreeForPublicRepos: false,
			EffectiveAt:        actionsRolloutEffectiveAt,
			UnitType:           models.UnitTypeMinutes,
		},
		{
			Price:              int64(1000 * 0.128),
			Sku:                "ghec_seats",
			FriendlyName:       "ghec_seats",
			Product:            "ghec",
			AzureMeterId:       "8a019f97-b29d-54e1-9cff-ca30b7b7bdca",
			MeterType:          models.PricingMeterDefault,
			FreeForPublicRepos: false,
			EffectiveAt:        actionsRolloutEffectiveAt,
			UnitType:           models.UnitTypeMinutes,
		},
	}

	testUsageObject := InitializeUsageTestObject(t)

	// Corrected: Added missing closing parenthesis for the QueryItems call
	pegomock.When(testUsageObject.itemQuerier.QueryItems(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(db.QueryStringAll),
		pegomock.Any[string](),
	)).ThenReturn(mockUsageItemQuery, nil)

	pegomock.When(testUsageObject.pricingQuerier.QueryItems(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(db.QueryStringAll),
		pegomock.Eq("pricing"),
	)).ThenReturn(mockPricings, nil)

	// Setup a EmissionDate
	target := models.EmissionTarget{
		Year:  int64(sYear),
		Month: int64(sMonth),
		Day:   int64(sDay),
	}
	l := log.NewNullLogger()

	skipCache := true
	err := testUsageObject.usageEngine.ScheduleZuoraEmission(context.Background(), l, &target, skipCache)
	assert.NoError(t, err)

	InspectAqueductSend(t, testUsageObject.aqueductClient, mockUsageItemQuery)

}

func TestUsage_ScheduleEmission_NoRecords(t *testing.T) {

	now := time.Now().UTC()
	then := now.AddDate(0, 0, -1)
	nowUsageAt := *models.NewUsageTimeFromTime(then)
	year, month, day := nowUsageAt.Date()

	usageTime := models.NewUsageTimeFromTime(then)
	activeType := models.Daily

	partitionDetail := models.UsagePartitionDetail{
		UsageTime:  usageTime,
		ActiveType: activeType,
	}
	partitionKey := partitionDetail.ToPartitionKey()

	mockUsageItemRead := []*models.Item{} // Empty list to simulate no records

	actionsRolloutEffectiveAt := time.Date(2023, 7, 14, 20, 30, 0, 0, time.UTC).Unix()

	// Prepare mock pricing data
	mockPricings := []*models.Pricing{
		{
			Price:              int64(1000 * 0.008),
			Sku:                "actions_linux",
			FriendlyName:       "Actions Linux",
			Product:            "actions",
			AzureMeterId:       "3dbfec75-284c-4c89-8c9c-0d395be81a0c",
			MeterType:          models.PricingMeterDefault,
			FreeForPublicRepos: true,
			EffectiveAt:        actionsRolloutEffectiveAt,
			UnitType:           models.UnitTypeMinutes,
		},
		{
			Price:              int64(1000 * 0.064),
			Sku:                "actions_linux_16_core",
			FriendlyName:       "Actions Linux 16-core",
			Product:            "actions",
			AzureMeterId:       "cdc3163b-3623-5f85-9c2b-980c77501091",
			MeterType:          models.PricingMeterDefault,
			FreeForPublicRepos: false,
			EffectiveAt:        actionsRolloutEffectiveAt,
			UnitType:           models.UnitTypeMinutes,
		},
		{
			Price:              int64(1000 * 0.128),
			Sku:                "actions_linux_32_core",
			FriendlyName:       "Actions Linux 32-core",
			Product:            "actions",
			AzureMeterId:       "8a019f97-b29d-54e1-9cff-ca30b7b7bdca",
			MeterType:          models.PricingMeterDefault,
			FreeForPublicRepos: false,
			EffectiveAt:        actionsRolloutEffectiveAt,
			UnitType:           models.UnitTypeMinutes,
		},
	}

	pegomock.RegisterMockTestingT(t)

	// Initialize test object and set up mock behavior
	testUsageObject := InitializeUsageTestObject(t)
	pegomock.When(testUsageObject.itemQuerier.QueryItems(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[string](),
		pegomock.Eq(partitionKey),
	)).ThenReturn(mockUsageItemRead, nil)

	pegomock.When(testUsageObject.itemQuerier.QueryItemsWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[string](),
		pegomock.Eq(partitionKey),
		pegomock.Any[int](),
		pegomock.Any[*azcosmos.QueryOptions](),
	)).ThenReturn(mockUsageItemRead, nil)

	pegomock.When(testUsageObject.pricingQuerier.QueryItems(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq(db.QueryStringAll),
		pegomock.Eq("pricing"),
	)).ThenReturn(mockPricings, nil)

	// Set up an emission target date
	target := models.EmissionTarget{
		Year:  int64(year),
		Month: int64(month),
		Day:   int64(day),
	}
	logger := log.NewNullLogger()

	// Run the ScheduleEmission function
	skipCache := true
	err := testUsageObject.usageEngine.ScheduleZuoraEmission(context.Background(), logger, &target, skipCache)
	assert.NoError(t, err)

	testUsageObject.aqueductClient.VerifyWasCalled(pegomock.Times(0)).Send(
		pegomock.Any[context.Context](),
		pegomock.Any[aqueduct.Job](),
		pegomock.Any[aqueduct.SendOption](),
	)
}

func InspectAqueductSend(t *testing.T, aqueductClient *fakes.MockAqueductClient, expectedRecords []*models.Item) {

	_, actualJobs, _ := aqueductClient.VerifyWasCalled(pegomock.Times(len(expectedRecords))).Send(pegomock.Any[context.Context](), pegomock.Any[aqueduct.Job](), pegomock.Any[aqueduct.SendOption]()).GetAllCapturedArguments()

	expectedRecord := expectedRecords
	usageAsBytes, err := json.Marshal(expectedRecord)

	assert.NoError(t, err)
	ExpectedJob := aqueduct.Job{
		Payload: usageAsBytes,
		App:     "billing-platform-development",
		Queue:   "emission-handler",
	}

	queueName := ""
	var allActualRecords [][]*models.Item
	for _, actualJob := range actualJobs {
		var actualRecord []*models.Item
		err = json.Unmarshal(actualJob.Payload, &actualRecord)
		assert.NoError(t, err)
		allActualRecords = append(allActualRecords, actualRecord)
		queueName = actualJob.Queue

	}

	assert.NoError(t, err)

	assert.Equal(t, ExpectedJob.Queue, queueName)
	assert.Equal(t, len(expectedRecord), len(allActualRecords))

	assert.NoError(t, err)

}

func TestUsage_GetNetUsageLineItems(t *testing.T) {
	year := int64(2021)
	month := int64(1)
	day := 1
	usagePartitionDetail := &models.UsagePartitionDetail{
		UsageEntityId: "123",
		Product:       "product1",
		Sku:           "sku1",
		UsageTime:     models.NewUsageTime().WithYear(year).WithMonthInt(month).WithDay(day),
		ActiveType:    models.Monthly,
	}
	partitionKey := usagePartitionDetail.ToGetLineItemsPartitionKey()
	discountsPartitionKey := usagePartitionDetail.ToDiscountsPartitionKey()

	mockUsageItems := []*models.Item{
		{
			Key: models.Key{
				PartitionKey: partitionKey,
				Id:           "123",
			},
			EntityDetail: &models.EntityDetail{
				CustomerId: "123",
				CostCenterDetail: &models.CostCenterDetail{
					EnterpriseCustomerId: "123",
				},
			},
			Pricing: &models.Pricing{
				Product: "product1",
				Sku:     "sku1",
			},
		},
		{
			Key: models.Key{
				PartitionKey: partitionKey,
				Id:           "456",
			},
			EntityDetail: &models.EntityDetail{
				CustomerId: "456",
				CostCenterDetail: &models.CostCenterDetail{
					EnterpriseCustomerId: "123",
				},
			},
			Pricing: &models.Pricing{
				Product: "product1",
				Sku:     "sku1",
			},
		},
	}

	mockDiscountItems := []*models.DiscountItem{
		{
			Key: &models.Key{
				PartitionKey: partitionKey,
				Id:           "123",
			},
			DiscountAmount: 1.0,
			Quantity:       1,
			Pricing: &models.Pricing{
				Product: "product1",
				Sku:     "sku1",
			},
		},
	}

	usagePartitionDetails := make([]*models.UsagePartitionDetail, 1)
	usagePartitionDetails[0] = usagePartitionDetail

	pegomock.RegisterMockTestingT(t)

	testUsageObject := InitializeUsageTestObject(t)

	pegomock.When(testUsageObject.itemQuerier.QueryItems(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[string](),
		pegomock.Eq(partitionKey))).
		ThenReturn(mockUsageItems, nil)

	pegomock.When(testUsageObject.discountItemQuerier.QueryItems(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[string](),
		pegomock.Eq(discountsPartitionKey))).
		ThenReturn(mockDiscountItems, nil)

	result, err := testUsageObject.usageEngine.GetNetUsageLineItems(context.Background(), log.NewNullLogger(), usagePartitionDetail)
	assert.NoError(t, err)
	assert.Equal(t, len(mockUsageItems), len(result.UsageItems))
}

func Test_GroupLineItems(t *testing.T) {
	testUsageObject := InitializeUsageTestObject(t)
	usageAtOneDayAgo := *models.NewUsageTimeFromTime(time.Now().UTC().AddDate(0, 0, -1))
	usageAtTwoDaysAgo := *models.NewUsageTimeFromTime(time.Now().UTC().AddDate(0, 0, -2))

	tests := []struct {
		name                 string
		lineItems            []*models.UsageItem
		groupBy              proto.UsageGroupBy
		period               proto.BillingPeriod
		expectedGroupedItems []*models.UsageItem
	}{
		{"nil line items", nil, proto.UsageGroupBy_GroupByOrganization, proto.BillingPeriod_Daily, nil},
		{"empty line items", []*models.UsageItem{}, proto.UsageGroupBy_GroupByOrganization, proto.BillingPeriod_Daily, nil},
		{"same date, same organization",
			[]*models.UsageItem{
				{
					GrossAmount:    10,
					DiscountAmount: 4,
					NetAmount:      6,
					OrgId:          1,
					UsageAt:        usageAtOneDayAgo.UnixMilli(),
				},
				{
					GrossAmount:    10,
					DiscountAmount: 4,
					NetAmount:      6,
					OrgId:          1,
					UsageAt:        usageAtOneDayAgo.UnixMilli(),
				},
			},
			proto.UsageGroupBy_GroupByOrganization,
			proto.BillingPeriod_Daily,
			[]*models.UsageItem{
				{
					GrossAmount:    20,
					DiscountAmount: 8,
					NetAmount:      12,
					OrgId:          1,
					UsageAt:        usageAtOneDayAgo.UnixMilli(),
				},
			},
		},
		{"different date, same organization",
			[]*models.UsageItem{
				{
					GrossAmount:    10,
					DiscountAmount: 4,
					NetAmount:      6,
					OrgId:          1,
					UsageAt:        usageAtOneDayAgo.UnixMilli(),
				},
				{
					GrossAmount:    10,
					DiscountAmount: 0,
					NetAmount:      10,
					OrgId:          1,
					UsageAt:        usageAtTwoDaysAgo.UnixMilli(),
				},
			},
			proto.UsageGroupBy_GroupByOrganization,
			proto.BillingPeriod_Monthly,
			[]*models.UsageItem{
				{
					GrossAmount:    10,
					DiscountAmount: 0,
					NetAmount:      10,
					OrgId:          1,
					UsageAt:        usageAtTwoDaysAgo.UnixMilli(),
				},
				{
					GrossAmount:    10,
					DiscountAmount: 4,
					NetAmount:      6,
					OrgId:          1,
					UsageAt:        usageAtOneDayAgo.UnixMilli(),
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			groupedLineItems := testUsageObject.usageEngine.GroupLineItems(tt.lineItems, tt.groupBy, tt.period)
			assert.Equal(t, tt.expectedGroupedItems, groupedLineItems)
		})
	}
}

func Test_CalculateOtherUsages(t *testing.T) {
	testUsageObject := InitializeUsageTestObject(t)
	usageAtOneDayAgo := *models.NewUsageTimeFromTime(time.Now().UTC().AddDate(0, 0, -1))
	usageAtTwoDaysAgo := *models.NewUsageTimeFromTime(time.Now().UTC().AddDate(0, 0, -2))

	tests := []struct {
		name               string
		allUsage           []*models.UsageItem
		topUsage           []*models.UsageItem
		expectedOtherUsage []*models.UsageItem
	}{
		{"nil usages", nil, nil, nil},
		{"empty usages", []*models.UsageItem{}, []*models.UsageItem{}, nil},
		{"3 usages all same date 1 top usage",
			// all usage
			[]*models.UsageItem{
				{
					GrossAmount:    10,
					DiscountAmount: 4,
					NetAmount:      6,
					UsageAt:        usageAtOneDayAgo.UnixMilli(),
				},
				{
					GrossAmount:    10,
					DiscountAmount: 4,
					NetAmount:      6,
					UsageAt:        usageAtOneDayAgo.UnixMilli(),
				},
				{
					GrossAmount:    10,
					DiscountAmount: 4,
					NetAmount:      6,
					UsageAt:        usageAtOneDayAgo.UnixMilli(),
				},
			},
			// top usage
			[]*models.UsageItem{{
				GrossAmount:    10,
				DiscountAmount: 4,
				NetAmount:      6,
				UsageAt:        usageAtOneDayAgo.UnixMilli(),
			}},
			// expected other usage
			[]*models.UsageItem{{
				GrossAmount:    20,
				DiscountAmount: 8,
				NetAmount:      12,
				UsageAt:        usageAtOneDayAgo.UnixMilli(),
			}},
		},
		{"3 usages different date 1 top usage",
			// all usage
			[]*models.UsageItem{
				{
					GrossAmount:    10,
					DiscountAmount: 4,
					NetAmount:      6,
					UsageAt:        usageAtOneDayAgo.UnixMilli(),
				},
				{
					GrossAmount:    10,
					DiscountAmount: 4,
					NetAmount:      6,
					UsageAt:        usageAtOneDayAgo.UnixMilli(),
				},
				{
					GrossAmount:    10,
					DiscountAmount: 4,
					NetAmount:      6,
					UsageAt:        usageAtTwoDaysAgo.UnixMilli(),
				},
			},
			// top usage
			[]*models.UsageItem{{
				GrossAmount:    10,
				DiscountAmount: 4,
				NetAmount:      6,
				UsageAt:        usageAtOneDayAgo.UnixMilli(),
			}},
			// expected other usage
			[]*models.UsageItem{{
				GrossAmount:    10,
				DiscountAmount: 4,
				NetAmount:      6,
				UsageAt:        usageAtTwoDaysAgo.UnixMilli(),
			}, {
				GrossAmount:    10,
				DiscountAmount: 4,
				NetAmount:      6,
				UsageAt:        usageAtOneDayAgo.UnixMilli(),
			}},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			otherUsages := testUsageObject.usageEngine.CalculateOtherUsages(tt.allUsage, tt.topUsage, proto.BillingPeriod_Monthly)
			assert.Equal(t, tt.expectedOtherUsage, otherUsages)
		})
	}
}

func Test_GetTopOrgRepoFromCache(t *testing.T) {
	now := time.Now().UTC()
	lastMonth := now.AddDate(0, -1, 0)

	testUsageObject := InitializeUsageTestObject(t)

	tests := []struct {
		name                string
		input               *models.UsageRequest
		cachedData          *models.TopOrgRepo
		queryError          error
		expectedError       bool
		expectedResourceIDs []int64
	}{
		{
			name: "Return nil if cached data is nil",
			input: &models.UsageRequest{
				CustomerId:    1,
				Year:          2021,
				BillingPeriod: proto.BillingPeriod_Yearly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
				CostCenterId:  "",
			},
		},
		{
			name: "Return error if query errors",
			input: &models.UsageRequest{
				CustomerId:    1,
				Year:          2021,
				BillingPeriod: proto.BillingPeriod_Yearly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
				CostCenterId:  "",
			},
			queryError:    errors.New("error"),
			expectedError: true,
		},
		{
			name: "Return data if not expired",
			input: &models.UsageRequest{
				CustomerId:    1,
				Year:          int64(now.Year()),
				Month:         int64(now.Month()),
				Day:           int64(now.Day()),
				Hour:          int64(now.Hour()),
				BillingPeriod: proto.BillingPeriod_Monthly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
				CostCenterId:  "",
			},
			cachedData: &models.TopOrgRepo{
				ResourceIDs: []int64{1, 2, 3, 4, 5},
				Timestamp:   now.Unix(),
			},
			expectedResourceIDs: []int64{1, 2, 3, 4, 5},
		},
		{
			name: "Return data if not expired for empty cost center ID",
			input: &models.UsageRequest{
				CustomerId:    1,
				Year:          int64(now.Year()),
				Month:         int64(now.Month()),
				Day:           int64(now.Day()),
				Hour:          int64(now.Hour()),
				BillingPeriod: proto.BillingPeriod_Monthly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
				CostCenterId:  "",
			},
			cachedData: &models.TopOrgRepo{
				ResourceIDs: []int64{1, 2, 3, 4, 5},
				Timestamp:   now.Unix(),
			},
			expectedResourceIDs: []int64{1, 2, 3, 4, 5},
		},
		{
			name: "Return nil if data expired",
			input: &models.UsageRequest{
				CustomerId:    1,
				Year:          int64(now.Year()),
				Month:         int64(now.Month()),
				Day:           int64(now.Day()),
				Hour:          int64(now.Hour()),
				BillingPeriod: proto.BillingPeriod_Monthly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
				CostCenterId:  "",
			},
			cachedData: &models.TopOrgRepo{
				ResourceIDs: []int64{1, 2, 3, 4, 5},
				// shift the time to 1 hour ago to simulate expired data
				Timestamp: now.Add(-time.Hour * 1).Unix(),
			},
		},
		{
			name: "Return data if data expired but last month",
			input: &models.UsageRequest{
				CustomerId:    1,
				Year:          int64(lastMonth.Year()),
				Month:         int64(lastMonth.Month()),
				Day:           int64(lastMonth.Day()),
				Hour:          int64(now.Hour()),
				BillingPeriod: proto.BillingPeriod_Monthly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
				CostCenterId:  "",
			},
			cachedData: &models.TopOrgRepo{
				ResourceIDs: []int64{1, 2, 3, 4, 5},
				// shift the time to 1 hour ago to simulate expired data
				Timestamp: now.Add(-time.Hour * 1).Unix(),
			},
			expectedResourceIDs: []int64{1, 2, 3, 4, 5},
		},
		{
			name: "Return data if data expired but last year",
			input: &models.UsageRequest{
				CustomerId:    1,
				Year:          int64(now.AddDate(-1, 0, 0).Year()),
				Month:         int64(now.AddDate(-1, 0, 0).Month()),
				Day:           int64(now.AddDate(-1, 0, 0).Day()),
				Hour:          int64(now.AddDate(-1, 0, 0).Hour()),
				BillingPeriod: proto.BillingPeriod_Yearly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
				CostCenterId:  "",
			},
			cachedData: &models.TopOrgRepo{
				ResourceIDs: []int64{1, 2, 3, 4, 5},
				// shift the time to 1 hour ago to simulate expired data
				Timestamp: now.Add(-time.Hour * 1).Unix(),
			},
			expectedResourceIDs: []int64{1, 2, 3, 4, 5},
		},
		{
			name: "Skip cache for org admin",
			input: &models.UsageRequest{
				CustomerId:    1,
				FilteredOrgs:  []int64{1, 2, 3},
				Year:          int64(now.Year()),
				Month:         int64(now.Month()),
				Day:           int64(now.Day()),
				Hour:          int64(now.Hour()),
				BillingPeriod: proto.BillingPeriod_Monthly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
				CostCenterId:  "",
			},
			cachedData: &models.TopOrgRepo{
				ResourceIDs: []int64{1, 2, 3, 4, 5},
				Timestamp:   now.Unix(),
			},
		},
		{
			name: "Skip cache cost center search",
			input: &models.UsageRequest{
				CustomerId:    1,
				Year:          int64(now.Year()),
				Month:         int64(now.Month()),
				Day:           int64(now.Day()),
				Hour:          int64(now.Hour()),
				BillingPeriod: proto.BillingPeriod_Monthly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
				CostCenterId:  "123456",
			},
			cachedData: &models.TopOrgRepo{
				ResourceIDs: []int64{1, 2, 3, 4, 5},
				Timestamp:   now.Unix(),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pegomock.When(
				testUsageObject.topOrgRepoQuerier.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Any[*interfaces.QueryOptions](),
				),
			).ThenReturn(tt.cachedData, tt.queryError)

			resourceIDs, err := testUsageObject.usageEngine.GetTopOrgRepoFromCache(context.Background(), log.NewNullLogger(), tt.input)

			if tt.expectedError {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
			assert.Equal(t, resourceIDs, tt.expectedResourceIDs)
		})
	}
}

func Test_buildPaginatedLineItemsQuery(t *testing.T) {
	testUsageObject := InitializeUsageTestObject(t)

	tests := []struct {
		name                  string
		inputPaginatedRequest *proto.GetPaginatedUsageRequest
		expectedQueryPart     string
	}{
		{
			name: "Correctly builds query for org grouping",
			inputPaginatedRequest: &proto.GetPaginatedUsageRequest{
				Page:    1,
				GroupBy: proto.UsageGroupBy_GroupByOrganization,
			},
			expectedQueryPart: "GROUP BY c.EntityDetail.OrganizationId",
		},
		{
			name: "Correctly builds query for repo grouping",
			inputPaginatedRequest: &proto.GetPaginatedUsageRequest{
				Page:    1,
				GroupBy: proto.UsageGroupBy_GroupByRepository,
			},
			expectedQueryPart: "GROUP BY c.EntityDetail.RepositoryId",
		},
		{
			name: "Correctly builds query for org admin",
			inputPaginatedRequest: &proto.GetPaginatedUsageRequest{
				Page:            1,
				GroupBy:         proto.UsageGroupBy_GroupByRepository,
				OrganizationIds: []int64{1, 2, 3},
			},
			expectedQueryPart: "WHERE c.EntityDetail.OrganizationId IN (1,2,3)",
		},
		{
			name: "Sets offset to 0 for page 1",
			inputPaginatedRequest: &proto.GetPaginatedUsageRequest{
				Page:    1,
				GroupBy: proto.UsageGroupBy_GroupByRepository,
			},
			expectedQueryPart: "OFFSET 0 LIMIT 15",
		},
		{
			name: "Sets offset to 15 for page 2",
			inputPaginatedRequest: &proto.GetPaginatedUsageRequest{
				Page:    2,
				GroupBy: proto.UsageGroupBy_GroupByRepository,
			},
			expectedQueryPart: "OFFSET 15 LIMIT 15",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			query := testUsageObject.usageEngine.buildPaginatedLineItemsQuery(tt.inputPaginatedRequest)
			assert.Contains(t, query, tt.expectedQueryPart)
		})
	}
}

func Test_GetUsageTotalItems(t *testing.T) {
	tests := []struct {
		name                 string
		upd                  *models.UsagePartitionDetail
		req                  *proto.GetEnterpriseUsageTotalsRequest
		expectedQueryString  string
		expectedPartitionKey string
	}{
		{
			name: "Builds proper query and partition key for non org admin request",
			upd: &models.UsagePartitionDetail{
				UsageEntityId: "123",
				UsageTime:     models.NewUsageTime().WithYear(2024),
				ActiveType:    models.Yearly,
			},
			req: &proto.GetEnterpriseUsageTotalsRequest{
				CustomerId: "123",
				Year:       2024,
				Month:      10,
			},
			expectedQueryString:  "SELECT * FROM c where NOT IS_DEFINED(c.IsTotal) AND c.id LIKE '123:%:2024:10'",
			expectedPartitionKey: "123:2024",
		},
		{
			name: "Builds proper query and partition key for org admin request",
			upd: &models.UsagePartitionDetail{
				UsageEntityId: "123",
				UsageTime:     models.NewUsageTime().WithYear(2024),
				ActiveType:    models.Yearly,
				OrgId:         1,
			},
			req: &proto.GetEnterpriseUsageTotalsRequest{
				CustomerId:           "123",
				Year:                 2024,
				Month:                10,
				OrganizationAdminIds: []int64{1},
			},
			expectedQueryString:  "SELECT * FROM c where NOT IS_DEFINED(c.IsTotal) AND c.id LIKE '123:%:2024:10'",
			expectedPartitionKey: "123:org:1:2024:byProductSku",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			testUsageObject := InitializeUsageTestObject(t)

			_, err := testUsageObject.usageEngine.GetUsageTotalItems(
				context.Background(),
				log.NewNullLogger(),
				tt.upd,
				tt.req.CustomerId,
				tt.req.Year,
				tt.req.Month,
			)
			assert.NoError(t, err)

			testUsageObject.itemQuerier.VerifyWasCalledOnce().QueryItems(
				pegomock.Any[context.Context](),
				pegomock.Any[log.Logger](),
				pegomock.Eq(tt.expectedQueryString),
				pegomock.Eq(tt.expectedPartitionKey),
			)
		})
	}
}
