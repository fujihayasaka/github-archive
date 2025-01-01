package usage

import (
	"context"
	"testing"

	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	statsmocks "github.com/github/go-stats/mocks"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

func Test_BuildEnterpriseUsageTotals(t *testing.T) {
	usageSvc := NewUsageService(nil, nil, nil, nil)

	tests := []struct {
		name             string
		input            *proto.GetEnterpriseUsageTotalsRequest
		items            []*models.Item
		costCenters      []*models.CostCenter
		expectedResponse *proto.GetEnterpriseUsageTotalsResponse
	}{
		{
			name: "empty items has expected response",
			input: &proto.GetEnterpriseUsageTotalsRequest{
				CustomerId: "123",
			},
			expectedResponse: &proto.GetEnterpriseUsageTotalsResponse{
				TotalGrossAmount: 0,
				Totals: []*proto.EnterpriseUsageTotal{
					{
						Id:          "123",
						Name:        "Enterprise Only",
						GrossAmount: 0,
					},
				},
			},
		},
		{
			name: "items with no cost center has expected response",
			input: &proto.GetEnterpriseUsageTotalsRequest{
				CustomerId: "123",
			},
			items: []*models.Item{
				{
					// convert the billed amount to nano units for the item so we can test conversions
					Amounts: &models.Amounts{BilledAmount: 10 * nano.NanoDivisor},
					EntityDetail: &models.EntityDetail{
						CostCenterDetail: &models.CostCenterDetail{
							IsCostCenterProxy: false,
						},
					},
				},
			},
			expectedResponse: &proto.GetEnterpriseUsageTotalsResponse{
				TotalGrossAmount: 10,
				Totals: []*proto.EnterpriseUsageTotal{
					{
						Id:          "123",
						Name:        "Enterprise Only",
						GrossAmount: 10,
					},
				},
			},
		},
		{
			name: "items with cost centers has expected response",
			input: &proto.GetEnterpriseUsageTotalsRequest{
				CustomerId: "123",
			},
			costCenters: []*models.CostCenter{
				{
					CostCenterKey: &models.CostCenterKey{
						Key: &models.Key{
							Id: "test-cost-center-uuid",
						},
					},
					Name: "Test Cost Center",
				},
			},
			items: []*models.Item{
				{
					// convert the billed amount to nano units for the item so we can test conversions
					Amounts: &models.Amounts{BilledAmount: 10 * nano.NanoDivisor},
					EntityDetail: &models.EntityDetail{
						CostCenterDetail: &models.CostCenterDetail{
							IsCostCenterProxy: false,
						},
					},
				},
				{
					// convert the billed amount to nano units for the item so we can test conversions
					Amounts: &models.Amounts{BilledAmount: 10 * nano.NanoDivisor},
					EntityDetail: &models.EntityDetail{
						CostCenterDetail: &models.CostCenterDetail{
							CostCenterUUID:    "test-cost-center-uuid",
							IsCostCenterProxy: true,
						},
					},
				},
			},
			expectedResponse: &proto.GetEnterpriseUsageTotalsResponse{
				TotalGrossAmount: 20,
				Totals: []*proto.EnterpriseUsageTotal{
					{
						Id:          "123",
						Name:        "Enterprise Only",
						GrossAmount: 10,
					},
					{
						Id:          "test-cost-center-uuid",
						Name:        "Test Cost Center",
						GrossAmount: 10,
					},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp, err := usageSvc.BuildEnterpriseUsageTotals(tt.input, tt.items, tt.costCenters)
			assert.NoError(t, err)
			assert.Equal(t, tt.expectedResponse.TotalGrossAmount, resp.TotalGrossAmount)
			assert.ElementsMatch(t, tt.expectedResponse.Totals, resp.Totals)
		})
	}
}

func Test_GetTopOrgRepoUsageLineItems(t *testing.T) {
	tests := []struct {
		name                     string
		usageRequest             *proto.TopOrgRepoUsageRequest
		topUsagePartitionDetails []*models.UsagePartitionDetail
		allUsagePartitionDetails []*models.UsagePartitionDetail
	}{
		{
			name: "calls GetNetUsageLineItems when IncludeDiscounts is true",
			usageRequest: &proto.TopOrgRepoUsageRequest{
				IncludeDiscounts: true,
			},
			topUsagePartitionDetails: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					OrgId:         1,
					UsageTime:     models.NewUsageTime().WithYear(2023).WithMonth(1).WithDay(1).WithHour(0),
					ActiveType:    models.Yearly,
				},
			},
			allUsagePartitionDetails: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2023).WithMonth(1).WithDay(1).WithHour(0),
					ActiveType:    models.Yearly,
				},
			},
		},
		{
			name: "calls GetUsageLineItems when IncludeDiscounts is false",
			usageRequest: &proto.TopOrgRepoUsageRequest{
				IncludeDiscounts: false,
			},
			topUsagePartitionDetails: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					OrgId:         1,
					UsageTime:     models.NewUsageTime().WithYear(2023).WithMonth(1).WithDay(1).WithHour(0),
					ActiveType:    models.Yearly,
				},
			},
			allUsagePartitionDetails: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2023).WithMonth(1).WithDay(1).WithHour(0),
					ActiveType:    models.Yearly,
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockUsageEngine := fakes.NewMockUsageEngineInterface(pegomock.WithT(t))
			usageSvc := NewUsageService(nil, mockUsageEngine, log.NewNullLogger(), getMockStatter())

			_, err := usageSvc.GetTopOrgRepoUsageLineItems(context.TODO(), tt.usageRequest, tt.topUsagePartitionDetails, tt.allUsagePartitionDetails)

			if tt.usageRequest.IncludeDiscounts {
				mockUsageEngine.VerifyWasCalled(pegomock.AtLeast(1)).GetNetUsageLineItems(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[*models.UsagePartitionDetail](),
				)
			} else {
				mockUsageEngine.VerifyWasCalled(pegomock.AtLeast(1)).GetUsageLineItems(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[*models.UsagePartitionDetail](),
				)
			}

			assert.NoError(t, err)
		})
	}
}

func getMockStatter() stats.Client {
	mockStatter := statsmocks.Client{}
	mockStatter.Mock.On("WithTags", mock.AnythingOfType("stats.Tags")).Return(&mockStatter)
	mockStatter.Mock.On("Distribution", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("float64")).Return(nil)
	mockStatter.Mock.On("Counter", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Return(nil)
	mockStatter.Mock.On("Timing", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("time.Duration")).Return(nil)
	return &mockStatter
}
