package kusto

import (
	"context"
	"testing"
	"time"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"
	"github.com/stretchr/testify/assert"
)

func setupKustoService() *AzureKustoService {
	return &AzureKustoService{
		logger: log.NewNullLogger(),
	}
}

func TestKustoService_QueryBuilderWithOrgIds(t *testing.T) {
	ctx := context.Background()
	azureKustoService := setupKustoService()
	usageReport := models.UsageReportExport{
		StartDate:       time.Now().AddDate(0, 0, -1), // Yesterday
		EndDate:         time.Now(),
		CustomerID:      "123",
		OrganizationIDs: []int64{1, 2},
	}
	sasUrl := "www.azure.com/sas"
	isProxima := false

	query := azureKustoService.BuildSubmitExportRequestQuery(
		ctx,
		&usageReport,
		sasUrl,
		isProxima,
	)

	assert.Contains(t, query.String(), "where org_id in (dynamic([1,2]))")
}

func TestKustoService_QueryBuilderWithNoOrgIds(t *testing.T) {
	ctx := context.Background()
	azureKustoService := setupKustoService()
	usageReport := models.UsageReportExport{
		StartDate:       time.Now().AddDate(0, 0, -1), // Yesterday
		EndDate:         time.Now(),
		CustomerID:      "123",
		OrganizationIDs: []int64{},
	}
	sasUrl := "www.azure.com/sas"
	isProxima := false

	query := azureKustoService.BuildSubmitExportRequestQuery(
		ctx,
		&usageReport,
		sasUrl,
		isProxima,
	)

	assert.NotContains(t, query.String(), "where org_id in (dynamic([1,2]))")
}

func TestKustoService_BuildTopOrgsReposByGrossAmountQuery_ByRepo(t *testing.T) {
	azureKustoService := setupKustoService()
	query, err := azureKustoService.BuildTopOrgsReposByGrossAmountQuery(
		&models.UsageRequest{
			CustomerId:    1,
			Limit:         5,
			BillingPeriod: proto.BillingPeriod_Daily,
			Year:          2022,
			Month:         1,
			Day:           1,
			Hour:          1,
		},
		ByRepoQueryType,
	)

	assert.NoError(t, err)
	// We don't filter for org IDs since no org ID array is passed in the request
	assert.NotContains(t, query.String(), "| where org_id in (dynamic(")

	assert.Contains(t, query.String(), "| where repo_id != 0")
	assert.Contains(t, query.String(), "| summarize sum_gross_amount=sum(gross_amount) by repo_id")
}

func TestKustoService_BuildTopOrgsReposByGrossAmountQuery_ByOrg(t *testing.T) {
	azureKustoService := AzureKustoService{logger: log.NewNullLogger()}
	query, err := azureKustoService.BuildTopOrgsReposByGrossAmountQuery(
		&models.UsageRequest{
			CustomerId:    1,
			Limit:         5,
			BillingPeriod: proto.BillingPeriod_Daily,
			Year:          2022,
			Month:         1,
			Day:           1,
			Hour:          1,
		},
		ByOrgQueryType,
	)

	assert.NoError(t, err)
	// We don't filter for org IDs since no org ID array is passed in the request
	assert.NotContains(t, query.String(), "| where org_id in (dynamic(")

	assert.Contains(t, query.String(), "| where org_id != 0")
	assert.Contains(t, query.String(), "| summarize sum_gross_amount=sum(gross_amount) by org_id")
}

func TestKustoService_BuildTopOrgsReposByGrossAmountQuery_OrgAdminFilter(t *testing.T) {
	azureKustoService := setupKustoService()
	query, err := azureKustoService.BuildTopOrgsReposByGrossAmountQuery(
		&models.UsageRequest{
			CustomerId:    1,
			Limit:         5,
			BillingPeriod: proto.BillingPeriod_Daily,
			Year:          2022,
			Month:         1,
			Day:           1,
			Hour:          1,
			FilteredOrgs:  []int64{1, 2},
		},
		ByOrgQueryType,
	)

	assert.NoError(t, err)
	assert.Contains(t, query.String(), "| where org_id in (dynamic([1,2]))")
}

func TestKustoService_BuildTopOrgsReposByGrossAmountQuery_UsageAtFilter(t *testing.T) {
	tests := []struct {
		name     string
		request  *models.UsageRequest
		expected string
	}{
		{
			name: "Hourly",
			request: &models.UsageRequest{
				CustomerId:    1,
				Limit:         5,
				BillingPeriod: proto.BillingPeriod_Hourly,
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          1,
			},
			expected: "| where todatetime(usage_at) between(datetime(2022-01-01",
		},
		{
			name: "Daily",
			request: &models.UsageRequest{
				CustomerId:    1,
				Limit:         5,
				BillingPeriod: proto.BillingPeriod_Daily,
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          1,
			},
			expected: "| where todatetime(usage_at) between(startofday(datetime(2022-01-01",
		},
		{
			name: "Monthly",
			request: &models.UsageRequest{
				CustomerId:    1,
				Limit:         5,
				BillingPeriod: proto.BillingPeriod_Monthly,
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          1,
			},
			expected: "| where todatetime(usage_at) between(startofmonth(datetime(2022-01-01",
		},
		{
			name: "Yearly",
			request: &models.UsageRequest{
				CustomerId:    1,
				Limit:         5,
				BillingPeriod: proto.BillingPeriod_Yearly,
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          1,
			},
			expected: "| where todatetime(usage_at) between(startofyear(datetime(2022-01-01",
		},
		{
			name: "Aggregate Usage including all cost centers",
			request: &models.UsageRequest{
				CustomerId:    1,
				Limit:         5,
				BillingPeriod: proto.BillingPeriod_Yearly,
				Year:          2022,
				Month:         1,
				Day:           1,
				Hour:          1,
				CostCenterId:  "All",
			},
			expected: " where customer_id == \"1\"\t| where repo_id != 0",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			azureKustoService := setupKustoService()
			query, err := azureKustoService.BuildTopOrgsReposByGrossAmountQuery(
				tt.request,
				ByRepoQueryType,
			)

			assert.NoError(t, err)
			assert.Contains(t, query.String(), tt.expected)
		})
	}
}

func TestKustoService_BuildDistinctOrgOrRepoTotalCountQuery(t *testing.T) {
	test := []struct {
		name                string
		request             *proto.GetPaginatedUsageRequest
		expectedQueryString []string
	}{
		{
			name: "GroupByOrganization specific cost center",
			request: &proto.GetPaginatedUsageRequest{
				UsageEntityId:   "1",
				Year:            2022,
				Month:           1,
				Day:             1,
				Hour:            1,
				BillingPeriod:   proto.BillingPeriod_Monthly,
				GroupBy:         proto.UsageGroupBy_GroupByOrganization,
				Page:            1,
				OrganizationIds: []int64{1, 2},
				CostCenterId:    "123",
			},
			expectedQueryString: []string{"| where org_id != 0", "| where org_id in (dynamic([1,2]))",
				"| where todatetime(usage_at) between(startofmonth(datetime(2022-01-01", "| summarize count_distinct(org_id)",
				"| where customer_id == \"1\" and cost_center.uuid == \"123\""},
		},
		{
			name: "GroupByOrganization all cost centers",
			request: &proto.GetPaginatedUsageRequest{
				UsageEntityId:   "1",
				Year:            2022,
				Month:           1,
				Day:             1,
				Hour:            1,
				BillingPeriod:   proto.BillingPeriod_Monthly,
				GroupBy:         proto.UsageGroupBy_GroupByOrganization,
				Page:            1,
				OrganizationIds: []int64{1, 2},
				CostCenterId:    "All",
			},
			expectedQueryString: []string{"| where org_id != 0", "| where org_id in (dynamic([1,2]))",
				"| where todatetime(usage_at) between(startofmonth(datetime(2022-01-01", "| summarize count_distinct(org_id)",
				"| where customer_id == \"1\""},
		},
		{
			name: "GroupByRepository",
			request: &proto.GetPaginatedUsageRequest{
				UsageEntityId:   "1",
				Year:            2022,
				Month:           1,
				Day:             1,
				Hour:            1,
				BillingPeriod:   proto.BillingPeriod_Monthly,
				GroupBy:         proto.UsageGroupBy_GroupByRepository,
				Page:            1,
				OrganizationIds: []int64{1, 2},
				CostCenterId:    "123",
			},
			expectedQueryString: []string{"| where repo_id != 0", "| where org_id in (dynamic([1,2]))",
				"| where todatetime(usage_at) between(startofmonth(datetime(2022-01-01", "| summarize count_distinct(repo_id)"},
		},
	}
	for _, tt := range test {
		t.Run(tt.name, func(t *testing.T) {
			azureKustoService := setupKustoService()
			query, err := azureKustoService.BuildDistinctOrgOrRepoTotalCountQuery(
				tt.request,
			)

			assert.NoError(t, err)
			for _, expected := range tt.expectedQueryString {
				assert.Contains(t, query.String(), expected)
			}
		})
	}

}
