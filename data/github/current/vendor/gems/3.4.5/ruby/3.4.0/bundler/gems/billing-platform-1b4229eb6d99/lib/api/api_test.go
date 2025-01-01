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
		name           string
		chartRequest   *proto.GetUsageChartDataRequest
		topResourceIDs []int64
		expected       []*models.UsagePartitionDetail
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
				OrgId:         5,
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
					IsOrgAdmin:    true,
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
					IsOrgAdmin:    true,
				},
			},
		},
		{
			name: "returns correct UsagePartitionDetail for daily chart request with filtered orgs and no specific org ID",
			chartRequest: &proto.GetUsageChartDataRequest{
				UsageEntityId: "1",
				Product:       "product",
				Sku:           "sku",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				GroupBy:       proto.UsageGroupBy_NoGroupBy,
				FilteredOrgs:  []string{"5"},
				FilteredRepos: []string{},
			},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "cost-center-id",
					Product:       "product",
					Sku:           "sku",
					RepoId:        0,
					OrgId:         5,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
					IsOrgAdmin:    true,
				},
				{
					UsageEntityId: "1",
					Product:       "product",
					Sku:           "sku",
					RepoId:        0,
					OrgId:         5,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "",
					IsOrgAdmin:    true,
				},
			},
		},
		{
			name: "returns correct UsagePartitionDetail for org admin group by repo request",
			chartRequest: &proto.GetUsageChartDataRequest{
				UsageEntityId: "1",
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          0,
				BillingPeriod: proto.BillingPeriod_Daily,
				GroupBy:       proto.UsageGroupBy_GroupByRepository,
				FilteredOrgs:  []string{"1"},
				FilteredRepos: []string{},
			},
			topResourceIDs: []int64{4, 5},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "cost-center-id",
					RepoId:        4,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "byOrgAndRepo",
					IsOrgAdmin:    true,
				},
				{
					UsageEntityId: "cost-center-id",
					RepoId:        5,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "byOrgAndRepo",
					IsOrgAdmin:    true,
				},
				{
					UsageEntityId: "1",
					RepoId:        4,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "byOrgAndRepo",
					IsOrgAdmin:    true,
				},
				{
					UsageEntityId: "1",
					RepoId:        5,
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(1).WithDay(1).WithHour(0),
					ActiveType:    models.Daily,
					GroupBy:       "byOrgAndRepo",
					IsOrgAdmin:    true,
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			upd, err := FromUsageChartRequestToUsagePartitionDetails(tt.chartRequest, costCenters, tt.topResourceIDs)
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
				CostCenterId:  "",
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
			costCenters: []*models.CostCenter{},
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
				CostCenterId:  "",
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
			costCenters: []*models.CostCenter{},
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

func Test_FromOrgAdminTopOrgRepoUsageRequestToUsagePartitionDetailForOthers(t *testing.T) {
	type TestData struct {
		name     string
		request  *proto.TopOrgRepoUsageRequest
		entityId string
		orgId    int64

		expected *models.UsagePartitionDetail
	}

	tests := []TestData{
		{
			name: "returns correct UsagePartitionDetail for yearly request with org ID",
			request: &proto.TopOrgRepoUsageRequest{
				BillingPeriod: proto.BillingPeriod_Yearly,
				Year:          2022,
				Month:         4,
				Day:           5,
				Hour:          0,
			},
			entityId: "1",
			orgId:    1,
			expected: &models.UsagePartitionDetail{
				UsageEntityId: "1",
				UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(5).WithHour(0),
				ActiveType:    models.Yearly,
				OrgId:         1,
			},
		},
		{
			name: "returns correct UsagePartitionDetail for monthly request with org ID",
			request: &proto.TopOrgRepoUsageRequest{
				BillingPeriod: proto.BillingPeriod_Monthly,
				Year:          2022,
				Month:         4,
				Day:           5,
				Hour:          0,
			},
			entityId: "1",
			orgId:    1,
			expected: &models.UsagePartitionDetail{
				UsageEntityId: "1",
				UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(5).WithHour(0),
				ActiveType:    models.Monthly,
				OrgId:         1,
			},
		},
		{
			name: "returns correct UsagePartitionDetail for daily request with org ID",
			request: &proto.TopOrgRepoUsageRequest{
				BillingPeriod: proto.BillingPeriod_Daily,
				Year:          2022,
				Month:         4,
				Day:           5,
				Hour:          0,
			},
			entityId: "1",
			orgId:    1,
			expected: &models.UsagePartitionDetail{
				UsageEntityId: "1",
				UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(5).WithHour(0),
				ActiveType:    models.Daily,
				OrgId:         1,
			},
		},
		{
			name: "returns correct UsagePartitionDetail for hourly request with org ID",
			request: &proto.TopOrgRepoUsageRequest{
				BillingPeriod: proto.BillingPeriod_Hourly,
				Year:          2022,
				Month:         4,
				Day:           5,
				Hour:          0,
			},
			entityId: "1",
			orgId:    1,
			expected: &models.UsagePartitionDetail{
				UsageEntityId: "1",
				UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(5).WithHour(0),
				ActiveType:    models.Hourly,
				OrgId:         1,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			upd, err := FromOrgAdminTopOrgRepoUsageRequestToUsagePartitionDetailForOthers(tt.request, tt.entityId, tt.orgId)
			assert.NoError(t, err)
			assert.Equal(t, tt.expected, upd)
		})
	}
}

func Test_BuildPartitionDetailsForTopOrgRepoUsageRequest(t *testing.T) {
	type TestData struct {
		name           string
		request        *proto.TopOrgRepoUsageRequest
		costCenters    []*models.CostCenter
		topResourceIDs []int64

		expectedTopUsagePartitionDetails []*models.UsagePartitionDetail
		expectedAllUsagePartitionDetails []*models.UsagePartitionDetail
	}

	tests := []TestData{
		{
			name: "does not create allUsagePartitionDetails when length of resource IDs is less than our limit",
			request: &proto.TopOrgRepoUsageRequest{
				BillingPeriod: proto.BillingPeriod_Monthly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
				Year:          2022,
				Month:         4,
				Limit:         5,
				CustomerId:    1,
			},
			topResourceIDs: []int64{1, 2},
			costCenters:    []*models.CostCenter{},
			expectedTopUsagePartitionDetails: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
					OrgId:         1,
				},
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
					OrgId:         2,
				},
			},
			expectedAllUsagePartitionDetails: []*models.UsagePartitionDetail{},
		},
		{
			name: "creates allUsagePartitionDetails when length of resource IDs is equal to our limit",
			request: &proto.TopOrgRepoUsageRequest{
				BillingPeriod: proto.BillingPeriod_Monthly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
				Year:          2022,
				Month:         4,
				Limit:         2,
				CustomerId:    1,
			},
			topResourceIDs: []int64{1, 2},
			costCenters:    []*models.CostCenter{},
			expectedTopUsagePartitionDetails: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
					OrgId:         1,
				},
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
					OrgId:         2,
				},
			},
			expectedAllUsagePartitionDetails: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
				},
			},
		},
		{
			name: "includes cost centers in both top and all usage partition details",
			request: &proto.TopOrgRepoUsageRequest{
				BillingPeriod: proto.BillingPeriod_Monthly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
				Year:          2022,
				Month:         4,
				Limit:         1,
				CustomerId:    1,
			},
			topResourceIDs: []int64{1},
			costCenters: []*models.CostCenter{
				{
					Name: "test-cost-center",
					CostCenterKey: &models.CostCenterKey{
						Key: &models.Key{
							Id: "test-cost-center-uuid",
						},
					},
				},
			},
			expectedTopUsagePartitionDetails: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "test-cost-center-uuid",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
					OrgId:         1,
				},
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
					OrgId:         1,
				},
			},
			expectedAllUsagePartitionDetails: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "test-cost-center-uuid",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
				},
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
				},
			},
		},
		{
			name: "org admin requests limit all usage to usage in orgs they are admin of",
			request: &proto.TopOrgRepoUsageRequest{
				BillingPeriod:   proto.BillingPeriod_Monthly,
				GroupBy:         proto.UsageGroupBy_GroupByOrganization,
				Year:            2022,
				Month:           4,
				Limit:           1,
				CustomerId:      1,
				OrganizationIds: []int64{1},
			},
			topResourceIDs: []int64{1},
			costCenters: []*models.CostCenter{
				{
					Name: "test-cost-center",
					CostCenterKey: &models.CostCenterKey{
						Key: &models.Key{
							Id: "test-cost-center-uuid",
						},
					},
				},
			},
			expectedTopUsagePartitionDetails: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "test-cost-center-uuid",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
					OrgId:         1,
				},
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
					OrgId:         1,
				},
			},
			expectedAllUsagePartitionDetails: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "test-cost-center-uuid",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
					OrgId:         1,
				},
				{
					UsageEntityId: "1",
					UsageTime:     models.NewUsageTime().WithYear(2022).WithMonthInt(4).WithDay(int(0)).WithHour(int(0)),
					ActiveType:    models.Monthly,
					OrgId:         1,
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			topUsagePartitionDetails, allUsagePartitionDetails, err := BuildPartitionDetailsForTopOrgRepoUsageRequest(tt.request, tt.costCenters, tt.topResourceIDs)
			assert.NoError(t, err)
			assert.Equal(t, tt.expectedTopUsagePartitionDetails, topUsagePartitionDetails)
			assert.Equal(t, tt.expectedAllUsagePartitionDetails, allUsagePartitionDetails)
		})
	}
}

func Test_createPartitionDetailsForUsageChart(t *testing.T) {
	inputUsageTime := models.NewUsageTime()

	tests := []struct {
		name          string
		request       *proto.GetUsageChartDataRequest
		usageTime     *models.UsageTime
		activeType    models.ActiveType
		groupBySuffix string
		usageEntityId string
		resourceIDs   []int64

		expected []*models.UsagePartitionDetail
	}{
		{
			name: "returns correct UsagePartitionDetails for non org admin usage request no grouping",
			request: &proto.GetUsageChartDataRequest{
				GroupBy: proto.UsageGroupBy_NoGroupBy,
			},
			usageTime:     inputUsageTime,
			activeType:    models.Monthly,
			groupBySuffix: "",
			usageEntityId: "1",
			resourceIDs:   []int64{},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
				},
			},
		},
		{
			name: "returns correct UsagePartitionDetails for non org admin usage request with org grouping and resource IDs",
			request: &proto.GetUsageChartDataRequest{
				GroupBy: proto.UsageGroupBy_GroupByOrganization,
			},
			usageTime:     inputUsageTime,
			activeType:    models.Monthly,
			groupBySuffix: "byOrgAndRepo",
			usageEntityId: "1",
			resourceIDs:   []int64{1, 2, 3, 4, 5},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
					GroupBy:       "byOrgAndRepo",
					OrgId:         1,
				},
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
					GroupBy:       "byOrgAndRepo",
					OrgId:         2,
				},
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
					GroupBy:       "byOrgAndRepo",
					OrgId:         3,
				},
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
					GroupBy:       "byOrgAndRepo",
					OrgId:         4,
				},
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
					GroupBy:       "byOrgAndRepo",
					OrgId:         5,
				},
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
				},
			},
		},
		{
			name: "returns correct UsagePartitionDetails for non org admin usage request with repo grouping and resource IDs",
			request: &proto.GetUsageChartDataRequest{
				GroupBy: proto.UsageGroupBy_GroupByRepository,
			},
			usageTime:     inputUsageTime,
			activeType:    models.Monthly,
			groupBySuffix: "byOrgAndRepo",
			usageEntityId: "1",
			resourceIDs:   []int64{1, 2, 3, 4, 5},
			expected: []*models.UsagePartitionDetail{
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
					GroupBy:       "byOrgAndRepo",
					RepoId:        1,
				},
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
					GroupBy:       "byOrgAndRepo",
					RepoId:        2,
				},
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
					GroupBy:       "byOrgAndRepo",
					RepoId:        3,
				},
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
					GroupBy:       "byOrgAndRepo",
					RepoId:        4,
				},
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
					GroupBy:       "byOrgAndRepo",
					RepoId:        5,
				},
				{
					UsageEntityId: "1",
					UsageTime:     inputUsageTime,
					ActiveType:    models.Monthly,
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			partitionDetails := createPartitionDetailsForUsageChart(tt.request, []*models.UsagePartitionDetail{}, models.NewUsageTime(), tt.activeType, tt.groupBySuffix, tt.usageEntityId, tt.resourceIDs)
			assert.Equal(t, tt.expected, partitionDetails)
		})
	}
}
