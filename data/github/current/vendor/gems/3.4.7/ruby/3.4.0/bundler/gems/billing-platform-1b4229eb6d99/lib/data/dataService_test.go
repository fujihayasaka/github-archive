package data

import (
	"context"
	"testing"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydro_schemas_billingplatform_v1_entities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/github-telemetry-go/log"
	statsmocks "github.com/github/go-stats/mocks"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func Test_generateInvoiceHydroMessage(t *testing.T) {
	mockHydroPublisher := fakes.NewMockHydroPublisher()
	mockUsageEngine := fakes.NewMockUsageEngineInterface()
	mockCostCenterEngine := fakes.NewMockCostCenterEngineInterface()
	mockDiscountEngine := fakes.NewMockDiscountEngineInterface()

	mockStatter := statsmocks.Client{}
	mockStatter.Mock.On("WithTags", mock.AnythingOfType("stats.Tags")).Return(&mockStatter)
	mockStatter.Mock.On("Distribution", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("float64")).Return(nil)
	mockStatter.Mock.On("Counter", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Return(nil)
	mockStatter.Mock.On("Timing", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("time.Duration")).Return(nil)

	itemUsageAt := models.NewUsageTime().WithYear(2024).WithMonth(11).WithDay(7)

	tests := []struct {
		name                        string
		enterpriseInfo              *models.EnterpriseInfo
		item                        *models.Item
		emission                    *models.AzureEmission
		returnedDiscountQuantity    float64
		returnCostCenter            *models.CostCenter
		expectedInvoiceHydroMessage *hydroSchema.Invoice
	}{
		{
			name: "Properly creates Azure invoice message with whole amounts",
			enterpriseInfo: &models.EnterpriseInfo{
				EnterpriseCustomerId: "1",
				AzureAccountId:       "azure-account-id",
			},
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 7013000000000,
					// actions linux pricing
					AppliedCostPerQuantity: 8000000,
				},
				Pricing: &models.Pricing{
					Sku:          "actions_linux",
					Product:      "actions",
					AzureMeterId: "azure-meter-id",
					UnitType:     models.UnitTypeMinutes,
				},
				EntityDetail: &models.EntityDetail{
					CostCenterDetail: &models.CostCenterDetail{
						IsCostCenterProxy: false,
					},
				},
				UsageAt: *itemUsageAt,
			},
			emission: &models.AzureEmission{
				Key: &models.Key{
					Id: "azure-emission-id",
				},
			},
			returnedDiscountQuantity: 1.0,
			expectedInvoiceHydroMessage: &hydroSchema.Invoice{
				InvoiceId:  "azure-emission-id",
				CustomerId: "1",
				Skus: []*hydro_schemas_billingplatform_v1_entities.SkuInvoice{
					{
						Name:                  "actions_linux",
						Product:               "actions",
						GrossQuantity:         7013,
						DiscountQuantity:      1,
						NetQuantity:           7012,
						GrossBilledAmount:     56.104,
						DiscountAmount:        0.008,
						NetBilledAmount:       56.096,
						UnitType:              "minutes",
						BillingTargetChargeId: "azure-meter-id",
					},
				},
				GrossBilledAmount:  56.104,
				DiscountAmount:     0.008,
				NetAmountDue:       56.096,
				PaymentProcessorId: "azure-account-id",
				UsageAt:            timestamppb.New(itemUsageAt.Time),
				Target:             hydro_schemas_billingplatform_v1_entities.BillingTarget_AZURE,
				InvoiceYear:        2024,
				InvoiceMonth:       11,
				InvoiceDay:         7,
				BillingTargetId:    "azure-account-id",
			},
		},
		{
			name: "Properly creates Azure invoice message with cost center info if item is cost center proxy",
			enterpriseInfo: &models.EnterpriseInfo{
				EnterpriseCustomerId: "1",
				AzureAccountId:       "azure-account-id",
			},
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 7013000000000,
					// actions linux pricing
					AppliedCostPerQuantity: 8000000,
				},
				Pricing: &models.Pricing{
					Sku:          "actions_linux",
					Product:      "actions",
					AzureMeterId: "azure-meter-id",
					UnitType:     models.UnitTypeMinutes,
				},
				EntityDetail: &models.EntityDetail{
					CostCenterDetail: &models.CostCenterDetail{
						IsCostCenterProxy: true,
					},
				},
				UsageAt: *itemUsageAt,
			},
			emission: &models.AzureEmission{
				Key: &models.Key{
					Id: "azure-emission-id",
				},
			},
			returnedDiscountQuantity: 1.0,
			returnCostCenter: &models.CostCenter{
				CostCenterKey: &models.CostCenterKey{
					UUID: "cost-center-uuid",
				},
				Name: "cost-center-name",
			},
			expectedInvoiceHydroMessage: &hydroSchema.Invoice{
				InvoiceId:  "azure-emission-id",
				CustomerId: "1",
				Skus: []*hydro_schemas_billingplatform_v1_entities.SkuInvoice{
					{
						Name:                  "actions_linux",
						Product:               "actions",
						GrossQuantity:         7013,
						DiscountQuantity:      1,
						NetQuantity:           7012,
						GrossBilledAmount:     56.104,
						DiscountAmount:        0.008,
						NetBilledAmount:       56.096,
						UnitType:              "minutes",
						BillingTargetChargeId: "azure-meter-id",
					},
				},
				GrossBilledAmount:  56.104,
				DiscountAmount:     0.008,
				NetAmountDue:       56.096,
				PaymentProcessorId: "azure-account-id",
				UsageAt:            timestamppb.New(itemUsageAt.Time),
				Target:             hydro_schemas_billingplatform_v1_entities.BillingTarget_AZURE,
				InvoiceYear:        2024,
				InvoiceMonth:       11,
				InvoiceDay:         7,
				BillingTargetId:    "azure-account-id",
				CostCenter: &hydro_schemas_billingplatform_v1_entities.CostCenter{
					Uuid: "cost-center-uuid",
					Name: "cost-center-name",
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.item.IsCostCenterProxy() {
				pegomock.When(mockCostCenterEngine.Get(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.CostCenterKey]())).ThenReturn(tt.returnCostCenter, nil)
			}

			pegomock.When(mockDiscountEngine.GetDailyDiscountQuantity(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.Item]())).ThenReturn(tt.returnedDiscountQuantity, nil)

			dataService := NewDataService(mockHydroPublisher, mockUsageEngine, mockCostCenterEngine, mockDiscountEngine, log.NewNullLogger(), &mockStatter)
			invoiceMessage := dataService.generateInvoiceHydroMessage(context.TODO(), log.NewNullLogger(), tt.enterpriseInfo, tt.item, tt.emission)
			// reset the generated by billing at since it's a timestamp using now which we can't predict or easily mock
			invoiceMessage.GeneratedByBillingAt = nil

			assert.Equal(t, tt.expectedInvoiceHydroMessage, invoiceMessage)
		})
	}

}
