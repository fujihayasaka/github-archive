package api

import (
	"testing"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/stretchr/testify/assert"
)

func Test_FromUsageChartRequestToUsagePartitionDetails(t *testing.T) {
	costCenters := []*models.CostCenter{
		{
			Name: "cost-center-1",
			CostCenterKey: &models.CostCenterKey{
				UUID: "uuid",
				Key: &models.Key{
					Id: "cost-center-id",
				},
			},
		},
	}

	type TestData struct {
		name         string
		chartRequest *proto.GetUsageChartDataRequest
		expected     []*models.UsagePartitionDetail
	}

	tests := []TestData{
		{
			name: "returns correct UsagePartitionDetail for daily chart request",
			chartRequest: &proto.GetUsageChartDataRequest{
				UsageEntityId: "1",
				Product:       "product",
				Sku:           "sku",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				RepoId:        1,
				OrgId:         1,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				FilteredOrgs:  []string{},
				FilteredRepos: []string{},
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "cost-center-id",
					Product:       "product",
					Sku:           "sku",
					RepoId:        1,
					OrgId:         1,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
				{
					UsageEntityId: "1",
					Product:       "product",
					Sku:           "sku",
					RepoId:        1,
					OrgId:         1,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
			},
		},
		{
			name: "returns usage entity id only for chart request with 'none' cost center id",
			chartRequest: &proto.GetUsageChartDataRequest{
				UsageEntityId: "1",
				Product:       "product",
				Sku:           "sku",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				RepoId:        1,
				OrgId:         1,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				CostCenterId:  "none",
				FilteredOrgs:  []string{},
				FilteredRepos: []string{},
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					Product:       "product",
					Sku:           "sku",
					RepoId:        1,
					OrgId:         1,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
			},
		},
		{
			name: "returns correct UsagePartitionDetail for cost center id request",
			chartRequest: &proto.GetUsageChartDataRequest{
				UsageEntityId: "1",
				Product:       "product",
				Sku:           "sku",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				RepoId:        1,
				OrgId:         1,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				CostCenterId:  "uuid",
				FilteredOrgs:  []string{},
				FilteredRepos: []string{},
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "uuid",
					Product:       "product",
					Sku:           "sku",
					RepoId:        1,
					OrgId:         1,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
			},
		},
		{
			name: "returns correct UsagePartitionDetail for daily chart request with filtered orgs",
			chartRequest: &proto.GetUsageChartDataRequest{
				UsageEntityId: "1",
				Product:       "product",
				Sku:           "sku",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				RepoId:        1,
				OrgId:         1,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				FilteredOrgs:  []string{"5"},
				FilteredRepos: []string{},
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "cost-center-id",
					Product:       "product",
					Sku:           "sku",
					RepoId:        1,
					OrgId:         5,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
				{
					UsageEntityId: "1",
					Product:       "product",
					Sku:           "sku",
					RepoId:        1,
					OrgId:         5,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			upd, err := FromUsageChartRequestToUsagePartitionDetails(tt.chartRequest, costCenters)
			assert.NoError(t, err)
			assert.Equal(t, tt.expected, upd)
		})
	}
}

func Test_FromUsageRequestToUsagePartitionDetails(t *testing.T) {
	type TestData struct {
		name        string
		request     *proto.GetUsageRequest
		expected    []*models.UsagePartitionDetail
		costCenters []*models.CostCenter
	}

	tests := []TestData{
		{
			name: "returns correct UsagePartitionDetail for request with cost centers",
			request: &proto.GetUsageRequest{
				UsageEntityId: "1",
				Product:       "product",
				Sku:           "sku",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				RepoId:        1,
				OrgId:         1,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				CostCenterId:  "All",
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "cost-center-id",
					Product:       "product",
					Sku:           "sku",
					RepoId:        1,
					OrgId:         1,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
				{
					UsageEntityId: "1",
					Product:       "product",
					Sku:           "sku",
					RepoId:        1,
					OrgId:         1,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
			},
			costCenters: []*models.CostCenter{
				{
					Name: "cost-center-1",
					CostCenterKey: &models.CostCenterKey{
						UUID: "uuid",
						Key: &models.Key{
							Id: "cost-center-id",
						},
					},
				},
			},
		},
		{
			name: "returns correct UsagePartitionDetail for request without cost centers",
			request: &proto.GetUsageRequest{
				UsageEntityId: "1",
				Product:       "product",
				Sku:           "sku",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				RepoId:        1,
				OrgId:         1,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				CostCenterId:  "",
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					Product:       "product",
					Sku:           "sku",
					RepoId:        1,
					OrgId:         1,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
			},
			costCenters: []*models.CostCenter{
				{
					Name: "cost-center-1",
					CostCenterKey: &models.CostCenterKey{
						UUID: "uuid",
						Key: &models.Key{
							Id: "cost-center-id",
						},
					},
				},
			},
		},
		{
			name: "returns correct UsagePartitionDetail for request with no cost centers",
			request: &proto.GetUsageRequest{
				UsageEntityId: "1",
				Product:       "product",
				Sku:           "sku",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				RepoId:        1,
				OrgId:         1,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				CostCenterId:  "none",
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					Product:       "product",
					Sku:           "sku",
					RepoId:        1,
					OrgId:         1,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
			},
			costCenters: []*models.CostCenter{
				{
					Name: "cost-center-1",
					CostCenterKey: &models.CostCenterKey{
						UUID: "uuid",
						Key: &models.Key{
							Id: "cost-center-id",
						},
					},
				},
			},
		},
		{
			name: "returns correct UsagePartitionDetail for request for only cost centers",
			request: &proto.GetUsageRequest{
				UsageEntityId: "1",
				Product:       "product",
				Sku:           "sku",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				RepoId:        1,
				OrgId:         1,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				CostCenterId:  "cost-center-id",
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "cost-center-id",
					Product:       "product",
					Sku:           "sku",
					RepoId:        1,
					OrgId:         1,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
			},
			costCenters: []*models.CostCenter{
				{
					Name: "cost-center-1",
					CostCenterKey: &models.CostCenterKey{
						UUID: "uuid",
						Key: &models.Key{
							Id: "cost-center-id",
						},
					},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			upd, err := FromUsageRequestToUsagePartitionDetails(tt.request, tt.costCenters)
			assert.NoError(t, err)
			assert.Equal(t, tt.expected, upd)
		})
	}
}

func Test_FromPaginatedUsageRequestToUsagePartitionDetail(t *testing.T) {
	type TestData struct {
		name        string
		request     *proto.GetPaginatedUsageRequest
		expected    []*models.UsagePartitionDetail
		costCenters []*models.CostCenter
	}

	tests := []TestData{
		{
			name: "returns correct UsagePartitionDetail for request with cost centers",
			request: &proto.GetPaginatedUsageRequest{
				UsageEntityId: "1",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				CostCenterId:  "All",
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "cost-center-id",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
			},
			costCenters: []*models.CostCenter{
				{
					Name: "cost-center-1",
					CostCenterKey: &models.CostCenterKey{
						UUID: "uuid",
						Key: &models.Key{
							Id: "cost-center-id",
						},
					},
				},
			},
		},
		{
			name: "returns correct UsagePartitionDetail for request without cost centers",
			request: &proto.GetPaginatedUsageRequest{
				UsageEntityId: "1",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				CostCenterId:  "",
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
			},
			costCenters: []*models.CostCenter{
				{
					Name: "cost-center-1",
					CostCenterKey: &models.CostCenterKey{
						UUID: "uuid",
						Key: &models.Key{
							Id: "cost-center-id",
						},
					},
				},
			},
		},
		{
			name: "returns correct UsagePartitionDetail for request with no cost centers",
			request: &proto.GetPaginatedUsageRequest{
				UsageEntityId: "1",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				CostCenterId:  "none",
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
			},
			costCenters: []*models.CostCenter{
				{
					Name: "cost-center-1",
					CostCenterKey: &models.CostCenterKey{
						UUID: "uuid",
						Key: &models.Key{
							Id: "cost-center-id",
						},
					},
				},
			},
		},
		{
			name: "returns correct UsagePartitionDetail for request for only cost centers",
			request: &proto.GetPaginatedUsageRequest{
				UsageEntityId: "1",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				CostCenterId:  "cost-center-id",
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "cost-center-id",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
				},
			},
			costCenters: []*models.CostCenter{
				{
					Name: "cost-center-1",
					CostCenterKey: &models.CostCenterKey{
						UUID: "uuid",
						Key: &models.Key{
							Id: "cost-center-id",
						},
					},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			upd, err := FromPaginatedUsageRequestToUsagePartitionDetail(tt.request, tt.costCenters)
			assert.NoError(t, err)
			assert.Equal(t, tt.expected, upd)
		})
	}
}
