package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	//nolint:staticcheck

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/zuora"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

func TestEmissionHandler_ProcessMessage(t *testing.T) {
	// set up mocks
	pegomock.RegisterMockTestingT(t)

	timeNow := time.Now()
	customerId := stubs.GetRandomId64AsString()
	billingTarget := models.Zuora
	usageTime := *models.NewUsageTimeFromTime(timeNow)

	customer := createMockCustomer(customerId, billingTarget)
	emissionPayload := setupEmissionPayload(customerId, usageTime)

	t.Run("ProcessMessage for a Zuora customer exits gracefully when daily emissions are not enabled any customers", func(t *testing.T) {
		fakeContainer, telem, mockedStatter, mockedLogger, mockedDatabase := helpers.SetupMocks(t)

		pegomock.When(mockedDatabase.GetTracer()).ThenReturn(telem.Tracer.Tracer)
		pegomock.When(mockedDatabase.GetConnection()).ThenReturn(fakeContainer)
		pegomock.When(mockedDatabase.GetGatewayConnection()).ThenReturn(fakeContainer)
		pegomock.When(mockedDatabase.GetStatter()).ThenReturn(mockedStatter)

		// Mock the customer
		pegomock.When(
			fakeContainer.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Any[azcosmos.PartitionKey](),
				pegomock.Eq("customer"),
				pegomock.Any[*azcosmos.ItemOptions]())).ThenReturn(
			helpers.MockAzureItemResponse(t, customer), nil,
		)

		cfg := &config.Config{
			CustomersWithDailyEmissionEnabled: "",
		}

		engineParams := engines.NewEngineParams(nil, cfg, mockedDatabase, nil, mockedStatter, nil, telem.Tracer.Tracer)
		handler := NewEmissionHandler(
			&HandlerParams{
				statter: mockedStatter,
				cfg:     cfg,
			},
			engines.NewCustomerEngine(engineParams),
			nil, engines.NewUsageEngine(engineParams),
			nil)

		// Act
		err := handler.ProcessMessage(context.Background(), mockedLogger, emissionPayload)

		// Assert
		assert.NoError(t, err)

		// TODO: mockedLogger.AssertCalled(t, "Info", "Feature flag for daily emission not enabled")
		mockedStatter.AssertCalled(t, "Timing", "emission_handler_zuora_fanout", stats.Tags{}, mock.AnythingOfType("time.Duration"))
	})

	t.Run("ProcessMessage for a Zuora customer exits gracefully when daily emissions are not enabled for that customer", func(t *testing.T) {
		fakeContainer, telem, mockedStatter, mockedLogger, mockedDatabase := helpers.SetupMocks(t)

		pegomock.When(mockedDatabase.GetTracer()).ThenReturn(telem.Tracer.Tracer)
		pegomock.When(mockedDatabase.GetConnection()).ThenReturn(fakeContainer)
		pegomock.When(mockedDatabase.GetGatewayConnection()).ThenReturn(fakeContainer)
		pegomock.When(mockedDatabase.GetStatter()).ThenReturn(mockedStatter)

		// Mock the customer
		pegomock.When(
			fakeContainer.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Any[azcosmos.PartitionKey](),
				pegomock.Eq("customer"),
				pegomock.Any[*azcosmos.ItemOptions]())).ThenReturn(
			helpers.MockAzureItemResponse(t, customer), nil,
		)

		cfg := &config.Config{
			// Some random ID, different from the customerId (hopefully)
			CustomersWithDailyEmissionEnabled: stubs.GetRandomId64AsString(),
		}
		engineParams := engines.NewEngineParams(nil, cfg, mockedDatabase, nil, mockedStatter, nil, telem.Tracer.Tracer)
		handler := NewEmissionHandler(
			&HandlerParams{
				statter: mockedStatter,
				cfg:     cfg,
			},
			engines.NewCustomerEngine(engineParams),
			nil, engines.NewUsageEngine(engineParams),
			nil)

		// Act
		err := handler.ProcessMessage(context.Background(), mockedLogger, emissionPayload)

		// Assert
		assert.NoError(t, err)

		// TODO: mockedLogger.AssertCalled(t, "Info", "Customer ID not enabled for daily emission")
		mockedStatter.AssertCalled(t, "Timing", "emission_handler_zuora_fanout", stats.Tags{}, mock.AnythingOfType("time.Duration"))
	})

	t.Run("ProcessMessage for a Zuora customer sends daily emissions when enabled for that customer", func(t *testing.T) {
		fakeContainer, telem, mockedStatter, mockedLogger, mockedDatabase := helpers.SetupMocks(t)

		// Initialize ProductTotals
		totals := &models.Totals{
			ProductTotals: make(map[string]*models.ProductTotalNano),
			UsageTotal:    &models.UsageTotalNano{},
		}

		// Pre-initialize product totals for all products
		products := map[string][]string{
			"ghec":    {"ghec_seats"},
			"actions": {"actions_storage"},
		}

		for product, skus := range products {
			productTotal := &models.ProductTotalNano{
				UsageTotal: &models.UsageTotalNano{},
				SkuTotals:  make(map[string]*models.SkuTotalNano),
			}

			for _, sku := range skus {
				productTotal.SkuTotals[sku] = &models.SkuTotalNano{
					UsageTotal:   &models.UsageTotalNano{},
					BillingItems: make([]*models.Item, 0),
				}
			}

			totals.ProductTotals[product] = productTotal
		}

		pegomock.When(mockedDatabase.GetTracer()).ThenReturn(telem.Tracer.Tracer)
		pegomock.When(mockedDatabase.GetConnection()).ThenReturn(fakeContainer)
		pegomock.When(mockedDatabase.GetGatewayConnection()).ThenReturn(fakeContainer)
		pegomock.When(mockedDatabase.GetStatter()).ThenReturn(mockedStatter)

		// Mock the customer
		pegomock.When(
			fakeContainer.ReadItem(
				pegomock.Any[context.Context](),
				pegomock.Any[azcosmos.PartitionKey](),
				pegomock.Eq("customer"),
				pegomock.Any[*azcosmos.ItemOptions]())).ThenReturn(
			helpers.MockAzureItemResponse(t, customer), nil,
		)

		// Mock any query where we expect it to return some line item data
		lineItem := createMockBillingItem(customerId, usageTime)
		lineItemPager := helpers.MakePagerWithData(t, []*models.Item{lineItem})
		pegomock.When(
			fakeContainer.NewQueryItemsPager(
				pegomock.Any[string](),
				pegomock.Eq(azcosmos.NewPartitionKeyString(lineItem.PartitionKey)),
				pegomock.Any[*azcosmos.QueryOptions]())).
			ThenReturn(lineItemPager)

		// Setup discount item mock using the working approach
		usageTime := models.NewUsageTime()
		partitionKey := fmt.Sprintf("%d:%d:%d:discount", usageTime.Year(), usageTime.Month(), usageTime.Day())

		setupItemMock(t, fakeContainer, customerId, partitionKey)
		setupDiscountItemMock(t, fakeContainer, partitionKey)

		// Allow upserts to succeed without writing
		pegomock.When(mockedDatabase.UpsertWithOptions(
			pegomock.Any[context.Context](),
			pegomock.Any[log.Logger](),
			pegomock.Any[models.ItemKey](),
			pegomock.Any[*interfaces.QueryOptions]())).
			ThenReturn(nil)

		product := models.NewProduct("ghec", "GHEC seats", "GitHub Enterprise Cloud Usage")
		productPager := helpers.MakePagerWithData(t, []*models.Product{product})
		pegomock.When(
			fakeContainer.NewQueryItemsPager(
				pegomock.Any[string](),
				pegomock.Eq(azcosmos.NewPartitionKeyString(product.PartitionKey)),
				pegomock.Any[*azcosmos.QueryOptions]())).
			ThenReturn(productPager)

		mockedUsageService := fakes.NewMockUsageServiceInterface()
		pegomock.When(mockedUsageService.UploadUsage(pegomock.Any[[]zuora.UploadUsageRecord]())).ThenReturn(&zuora.UploadUsageResponse{
			Success: true,
			Message: "OK",
		}, nil)

		cfg := &config.Config{
			// Some random ID, plus the expected customer ID, delimited by commas
			DailyEmissionsActiveDate:          timeNow.AddDate(0, 0, -1).Format("2006-01-02"), // Set to a past date
			CustomersWithDailyEmissionEnabled: strings.Join([]string{stubs.GetRandomId64AsString(), customerId}, ","),
		}
		engineParams := engines.NewEngineParams(nil, cfg, mockedDatabase, nil, mockedStatter, nil, telem.Tracer.Tracer)
		handler := NewEmissionHandler(
			&HandlerParams{
				statter: mockedStatter,
				cfg:     cfg,
			},
			engines.NewCustomerEngine(engineParams),
			nil, engines.NewUsageEngine(engineParams),
			engines.NewZuoraEngine(engineParams, &zuora.Client{
				UsageService: mockedUsageService,
			}, nil, nil, engines.NewProductEngine(engineParams)))

		// Act
		err := handler.ProcessMessage(context.Background(), mockedLogger, emissionPayload)

		// Assert
		assert.NoError(t, err)

		mockedStatter.AssertCalled(t, "Timing", "emission_handler_zuora_fanout", stats.Tags{}, mock.AnythingOfType("time.Duration"))
		mockedStatter.AssertCalled(t, "Timing", "zuora_emission_timing", stats.Tags{"origin": "upload_usage_success"}, mock.AnythingOfType("time.Duration"))
		mockedStatter.AssertCalled(t, "Timing", "zuora_engine.emit_to_zuora", stats.Tags{"success": "true"}, mock.AnythingOfType("time.Duration"))

		_, _, savedEmission, _ := mockedDatabase.VerifyWasCalled(pegomock.Times(2)).UpsertWithOptions(
			pegomock.Any[context.Context](),
			pegomock.Any[log.Logger](),
			pegomock.Any[models.ItemKey](),
			pegomock.Any[*interfaces.QueryOptions](),
		).GetCapturedArguments()

		// Verify that the PartitionKey is not nil
		assert.NotNil(t, savedEmission.GetKey().PartitionKey, "PartitionKey should not be nil")

	})
}

func TestDiscountItemQuery(t *testing.T) {
	// Setup
	pegomock.RegisterMockTestingT(t)
	fakeContainer, _, _, _, _ := helpers.SetupMocks(t)

	// Test partition key
	partitionKey := "1754:8:30:discount"

	// Setup mock
	setupDiscountItemMock(t, fakeContainer, partitionKey)

	// Verify mock behavior
	pager := fakeContainer.NewQueryItemsPager(
		"SELECT * FROM c",
		azcosmos.NewPartitionKeyString(partitionKey),
		nil,
	)

	assert.NotNil(t, pager)
}

func setupItemMock(t *testing.T, fakeContainer *fakes.MockCosmosConnection, customerId string, partitionKey string) {

	usageTime := models.NewUsageTime()
	items := []*models.Item{
		{
			Key: models.Key{
				PartitionKey: partitionKey,
				Id:           fmt.Sprintf("%s:%s:%s", customerId, "ghec_seats", usageTime.ToPartitionKey(models.Daily)),
			},
			EntityDetail: &models.EntityDetail{
				CustomerId: customerId,
				CostCenterDetail: &models.CostCenterDetail{
					EnterpriseCustomerId: customerId,
				},
			},
			Amounts: &models.Amounts{
				BilledAmount: 100,
				Quantity:     10,
				FullQuantity: 10,
			},
			Pricing: &models.Pricing{
				Product: "ghec",
				Sku:     "ghec_seats",
			},
			SourceUri: "backfill",
		},
		{
			Key: models.Key{
				PartitionKey: partitionKey,
				Id:           fmt.Sprintf("%s:%s:%s", customerId, "actions_storage", usageTime.ToPartitionKey(models.Daily)),
			},
			EntityDetail: &models.EntityDetail{
				CustomerId: customerId,
				CostCenterDetail: &models.CostCenterDetail{
					EnterpriseCustomerId: customerId,
				},
			},
			Amounts: &models.Amounts{
				BilledAmount: 100,
				Quantity:     10,
				FullQuantity: 10,
			},
			Pricing: &models.Pricing{
				Product: "actions",
				Sku:     "actions_storage",
			},
			SourceUri: "backfill",
		},
	}

	itemPager := helpers.MakePagerWithData(t, items)
	pegomock.When(
		fakeContainer.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](),
			pegomock.Any[*azcosmos.QueryOptions](),
		)).ThenReturn(itemPager)
}

// Mock Setup Helper
func setupDiscountItemMock(t *testing.T, fakeContainer *fakes.MockCosmosConnection, partitionKey string) {
	// Create mock discount item
	discountItem := &models.DiscountItem{
		Key: &models.Key{
			PartitionKey: partitionKey,
			Id:           "test_discount_id",
		},
		Pricing: &models.Pricing{
			Product: "ghec",
			Sku:     "ghec_seats",
		},
		DiscountAmount: 10.0,
		Quantity:       1,
	}

	// Create pager with mock data
	discountItemPager := helpers.MakePagerWithData(t, []*models.DiscountItem{discountItem})

	// Set up mock to handle any partition key format
	pegomock.When(
		fakeContainer.NewQueryItemsPager(
			pegomock.Any[string](),
			pegomock.Any[azcosmos.PartitionKey](), // Changed from Eq to Any
			pegomock.Any[*azcosmos.QueryOptions](),
		)).ThenReturn(discountItemPager)

	// Add debug logging
	t.Logf("Mocked discount item partition key: %s", partitionKey)
}

func setupEmissionPayload(customerId string, usageTime models.UsageTime) aqueduct.ReceiveResult {

	partitionKey := fmt.Sprintf("%s:%s", usageTime.ToPartitionKey(models.Daily), "byZuoraEmission")

	mockUsageItems := []*models.Item{
		{
			Key: models.Key{
				PartitionKey: partitionKey,
				Id:           fmt.Sprintf("%s:%s:%s", customerId, "ghec_seats", usageTime.ToPartitionKey(models.Daily)),
			},
			EntityDetail: &models.EntityDetail{
				CustomerId: customerId,
				CostCenterDetail: &models.CostCenterDetail{
					EnterpriseCustomerId: customerId,
				},
			},
			Amounts: &models.Amounts{
				BilledAmount: 100,
				Quantity:     10,
				FullQuantity: 10,
			},
			Pricing: &models.Pricing{
				Product: "ghec",
				Sku:     "ghec_seats",
			},
			SourceUri: "backfill",
		},
		{
			Key: models.Key{
				PartitionKey: partitionKey,
				Id:           fmt.Sprintf("%s:%s:%s", customerId, "actions_storage", usageTime.ToPartitionKey(models.Daily)),
			},
			EntityDetail: &models.EntityDetail{
				CustomerId: customerId,
				CostCenterDetail: &models.CostCenterDetail{
					EnterpriseCustomerId: customerId,
				},
			},
			Amounts: &models.Amounts{
				BilledAmount: 100,
				Quantity:     10,
				FullQuantity: 10,
			},
			Pricing: &models.Pricing{
				Product: "actions",
				Sku:     "actions_storage",
			},
			SourceUri: "backfill",
		},
	}

	payload, _ := json.Marshal(mockUsageItems)
	rr := aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			Payload: payload,
		},
	}
	return rr
}

func createMockCustomer(customerId string, target models.BillingTarget) *models.Customer {
	customer := models.NewCustomer(customerId)
	customer.BillingTarget = target
	customer.ZuoraAccountNumber = stubs.GetRandomId64AsString()
	customer.EnabledProducts = []string{"copilot, actions, ghec"}
	return customer
}

func createMockBillingItem(customerId string, usageTime models.UsageTime) *models.Item {
	lineItemSourcePK := fmt.Sprintf("%s:%s", customerId, usageTime.ToPartitionKey(models.Daily))

	return &models.Item{
		Key:     models.Key{Id: "1", PartitionKey: lineItemSourcePK},
		UsageAt: usageTime,
		EntityDetail: &models.EntityDetail{
			CustomerId: customerId,
			CostCenterDetail: &models.CostCenterDetail{
				EnterpriseCustomerId: customerId,
			},
		},
		Amounts: &models.Amounts{
			BilledAmount: 100,
			Quantity:     10,
			FullQuantity: 10,
		},
		Pricing:   &models.Pricing{Product: "copilot", Sku: "copilot", Price: 5.0},
		SourceUri: "backfill",
	}
}
