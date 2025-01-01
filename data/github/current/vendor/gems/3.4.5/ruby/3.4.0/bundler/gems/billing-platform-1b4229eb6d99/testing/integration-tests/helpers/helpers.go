package helpers

import (
	"context"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
)

func IngestUsage(usage []*hydroSchema.Usage, client *integration.IntegrationClient) {
	l := len(usage)
	client.ProduceMeteredUsage(usage)
	client.RunUsageIngestion(l)
	client.RunDailyJob(l)
	client.RunMonthlyJob(l)
}

func CreateCostCenter(enterpriseCustomerId string, costCenterName string, resources map[int64]proto.ResourceType, target proto.CostCenterType, client *integration.IntegrationClient) (*proto.CostCenterKey, error) {
	enterpriseCustomer := stubs.CreateEnabledCustomerWithId(enterpriseCustomerId, proto.BillingTarget_Zuora)
	client.CreateCustomer(enterpriseCustomer)

	costCenter := stubs.CreateCostCenterWithAll(enterpriseCustomerId, target, false, costCenterName, stubs.CreateResources(resources))
	response, err := client.CreateCostCenter(costCenter)
	if err != nil {
		return nil, err
	}

	return response.CostCenter.CostCenterKey, err

}

func PopulateCacheForTopOrgs(client *integration.IntegrationClient, input *models.UsageRequest, topOrgIDsToCache []int64) error {
	topOrgRepo := &models.TopOrgRepo{
		Key:         models.NewTopOrgRepoCacheKey(input),
		ResourceIDs: topOrgIDsToCache,
	}
	return client.DB.UpsertWithOptions(context.Background(), client.Logger, topOrgRepo, nil)
}
