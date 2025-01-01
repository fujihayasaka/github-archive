//go:build integration
// +build integration

package integrationtests_test

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/assertions"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/integration-tests/helpers"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/onsi/gomega"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
)

func Test_Costcenter_Create_GetAllCostcenters(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerId := "1"

	costCenter1 := stubs.CreateAzureCostCenterWithCustomerId(customerId)
	costCenter2 := stubs.CreateAzureCostCenterWithCustomerId(customerId)
	costCenter3 := stubs.CreateAzureCostCenterWithCustomerId(customerId)
	costCenter4 := stubs.CreateAzureCostCenterWithCustomerId(customerId)

	_, _ = client.CreateCostCenter(costCenter1)
	_, _ = client.CreateCostCenter(costCenter2)
	_, _ = client.CreateCostCenter(costCenter3)
	_, _ = client.CreateCostCenter(costCenter4)

	costCentersResponse := client.GetAllCostCenters(customerId)
	costCenters := costCentersResponse.CostCenters

	g.Expect(len(costCenters)).Should(gomega.Equal(4))
	g.Expect(costCenters).Should(assertions.IncludeItem(func(r *proto.CostCenter) bool {
		return r.CostCenterKey.TargetId == costCenter1.CostCenterKey.TargetId
	}))
	g.Expect(costCenters).Should(assertions.IncludeItem(func(r *proto.CostCenter) bool {
		return r.CostCenterKey.TargetId == costCenter2.CostCenterKey.TargetId
	}))
	g.Expect(costCenters).Should(assertions.IncludeItem(func(r *proto.CostCenter) bool {
		return r.CostCenterKey.TargetId == costCenter3.CostCenterKey.TargetId
	}))
	g.Expect(costCenters).Should(assertions.IncludeItem(func(r *proto.CostCenter) bool {
		return r.CostCenterKey.TargetId == costCenter4.CostCenterKey.TargetId
	}))
}

func Test_Costcenter_Create_Get_Update_Costcenter(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// We discovered an indexing bug when deleting multiple resources so we intentionally want to be able to remove 2
	originalResource1 := &proto.Resource{Id: "not very resourceful", Type: proto.ResourceType_Org}
	originalResource2 := &proto.Resource{Id: "even less resourceful", Type: proto.ResourceType_Org}
	originalResource3 := &proto.Resource{Id: "no resources available", Type: proto.ResourceType_Repo}
	costCenter := stubs.CreateCostCenterWithAll("123", proto.CostCenterType_AzureSubscription, true, "", []*proto.Resource{originalResource1, originalResource2, originalResource3})

	createResponse, err := client.CreateCostCenter(costCenter)
	if err != nil {
		t.Fatal(err)
	}

	originalCostCenter := client.GetCostCenter(createResponse.CostCenter.CostCenterKey).CostCenter

	g.Expect(originalCostCenter).ShouldNot(gomega.BeNil())
	key := originalCostCenter.CostCenterKey
	g.Expect(key.CustomerId).Should(gomega.Equal(costCenter.CostCenterKey.CustomerId))
	g.Expect(key.TargetType).Should(gomega.Equal(proto.CostCenterType_AzureSubscription))
	g.Expect(key.TargetId).Should(gomega.Equal(costCenter.CostCenterKey.TargetId))
	g.Expect(originalCostCenter.Name).Should(gomega.Equal(costCenter.Name))
	g.Expect(len(originalCostCenter.Resources)).Should(gomega.Equal(3))
	g.Expect(originalCostCenter.Resources).Should(assertions.IncludeItem(func(r *proto.Resource) bool {
		return r.Id == "not very resourceful" && r.Type == proto.ResourceType_Org
	}))
	g.Expect(originalCostCenter.Resources).Should(assertions.IncludeItem(func(r *proto.Resource) bool {
		return r.Id == "even less resourceful" && r.Type == proto.ResourceType_Org
	}))
	g.Expect(originalCostCenter.Resources).Should(assertions.IncludeItem(func(r *proto.Resource) bool {
		return r.Id == "no resources available" && r.Type == proto.ResourceType_Repo
	}))

	newResource := &proto.Resource{Id: "very resourceful", Type: proto.ResourceType_Repo}
	newTargetId := "new target id"
	updateResponse, err := client.UpdateCostCenter(integration.UpdateCostCenterArgs{
		CostCenterKey:     createResponse.CostCenter.CostCenterKey,
		Name:              "a new name",
		TargetId:          newTargetId,
		ResourcesToAdd:    []*proto.Resource{newResource},
		ResourcesToRemove: []*proto.Resource{originalResource1, originalResource2, originalResource3},
	})
	if err != nil {
		t.Fatal(err)
	}

	c := client.GetCostCenter(updateResponse.CostCenter.CostCenterKey).CostCenter

	g.Expect(c).ShouldNot(gomega.BeNil())
	key = c.CostCenterKey
	g.Expect(key.CustomerId).Should(gomega.Equal(costCenter.CostCenterKey.CustomerId))
	g.Expect(key.TargetType).Should(gomega.Equal(proto.CostCenterType_AzureSubscription))
	g.Expect(key.TargetId).Should(gomega.Equal(newTargetId))
	g.Expect(c.Name).Should(gomega.Equal("a new name"))
	g.Expect(len(c.Resources)).Should(gomega.Equal(1))
	// TODO: Why is this not working? Verified that the list of resources is only [id:"very resourceful" type:Repo]
	// g.Expect(c.Resources).ShouldNot(assertions.IncludeItem(func(r *proto.Resource) bool {
	// 	return r.Id == "not very resourceful" && r.Type == proto.ResourceType_Repo
	// }))

	g.Expect(c.Resources[0].String()).Should(gomega.Equal(newResource.String()))

	// Verify that the DB has the correct documents
	costCenterQuerier := db.NewQuerier[*models.CostCenter](client.DB)

	costCenterModel := models.NewCostCenter(c, false)
	costCenterDocument, err := costCenterQuerier.ReadItemWithRetries(context.Background(), client.Logger, costCenterModel.GetKey())

	g.Expect(assert.NoError(t, err)).Should(gomega.BeTrue())

	assert.Equal(t, "a new name", costCenterDocument.Name)
	assert.Equal(t, costCenter.CostCenterKey.CustomerId, costCenterDocument.CostCenterKey.Customer.EnterpriseCustomerId)
	assert.Equal(t, newTargetId, costCenterDocument.CostCenterKey.TargetId)
	assert.Equal(t, models.AzureSubscription, costCenterDocument.CostCenterKey.TargetType)
	assert.Len(t, costCenterDocument.Resources, 1)
	assert.Equal(t, "very resourceful", costCenterDocument.Resources[0].Id)
	assert.Equal(t, models.Repository, costCenterDocument.Resources[0].Type)

	// Created a cost center as resource lookup document
	_, err = costCenterQuerier.ReadItemWithRetries(context.Background(), client.Logger, costCenterModel.AsResourceLookup(&models.Resource{Id: "very resourceful", Type: models.Repository}))
	g.Expect(assert.NoError(t, err)).Should(gomega.BeTrue())
}

func Test_Costcenter_Create_Uniqueness_Costcenter(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerId := stubs.GetRandomId64AsString()

	costCenter := stubs.CreateAzureCostCenterWithCustomerAndResources(customerId, []*proto.Resource{
		{
			Id:   "resourceId",
			Type: proto.ResourceType_Repo,
		},
	})

	// First attempt to create the cost center should succeed.
	_, err := client.CreateCostCenter(costCenter)
	g.Expect(err).ToNot(gomega.HaveOccurred())

	// Second attempt to create the same cost center should fail due to uniqueness constraint.
	costCenter = stubs.CreateAzureCostCenterWithCustomerAndResources(customerId, []*proto.Resource{
		{
			Id:   "resourceId",
			Type: proto.ResourceType_Repo,
		}})

	_, err = client.CreateCostCenter(costCenter)
	g.Expect(err).ToNot(gomega.BeNil()) // Ensure there is an error
	twerr, ok := err.(twirp.Error)
	g.Expect(ok).To(gomega.BeTrue()) // Ensure the error is a twirp.Error
	g.Expect(twerr.Code()).To(gomega.Equal(twirp.AlreadyExists))
}

func Test_Costcenter_Create_Get_CostcenterByUUID(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	costCenter := stubs.CreateAzureCostCenter()

	response, err := client.CreateCostCenter(costCenter)
	g.Expect(err).ToNot(gomega.HaveOccurred())

	response.CostCenter.CostCenterKey.TargetId = ""
	response.CostCenter.CostCenterKey.TargetType = proto.CostCenterType_NoCostCenter

	costCenterResponse := client.GetCostCenter(response.CostCenter.CostCenterKey)

	c := costCenterResponse.CostCenter
	g.Expect(c).ShouldNot(gomega.BeNil())
	key := c.CostCenterKey
	g.Expect(key.CustomerId).Should(gomega.Equal(costCenter.CostCenterKey.CustomerId))
	g.Expect(key.TargetType).Should(gomega.Equal(proto.CostCenterType_AzureSubscription))
	g.Expect(key.TargetId).Should(gomega.Equal(costCenter.CostCenterKey.TargetId))
	g.Expect(c.Name).Should(gomega.Equal(costCenter.Name))
	g.Expect(c.Resources).Should(gomega.BeEmpty())
}

func Test_Costcenter_Create_Get_Costcenter_With_Resource(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	costCenter := stubs.CreateAzureCostCenterWithResources([]*proto.Resource{
		{
			Id:   "resourceId",
			Type: proto.ResourceType_Repo,
		}})

	res, _ := client.CreateCostCenter(costCenter)

	costCenterResponse := client.GetCostCenter(res.CostCenter.CostCenterKey)

	c := costCenterResponse.CostCenter
	g.Expect(c).ShouldNot(gomega.BeNil())
	g.Expect(c.Resources).Should(assertions.IncludeItem(func(r *proto.Resource) bool {
		return r.Id == "resourceId" && r.Type == proto.ResourceType_Repo
	}))
}

func Test_Costcenter_Create_Get_Costcenter_With_AddResourceTo(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerId := stubs.GetRandomId64AsString()
	costCenter := stubs.CreateAzureCostCenterWithCustomerIdAndTargetId(customerId)

	res, _ := client.CreateCostCenter(costCenter)
	// Patch has a limit of 10 operations per update.
	// Adding 11 resources to validate that the patch is split into 2 requests
	_, err := client.CostCenterAddResourceTo(res.CostCenter.CostCenterKey, []*proto.Resource{
		{
			Id:   "resource-1",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-2",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-3",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-4",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-5",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-6",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-7",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-8",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-9",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-10",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-11",
			Type: proto.ResourceType_Repo,
		}})
	g.Expect(err).ToNot(gomega.HaveOccurred())

	costCenterResponse := client.GetCostCenter(res.CostCenter.CostCenterKey)

	c := costCenterResponse.CostCenter
	g.Expect(c).ShouldNot(gomega.BeNil())
	g.Expect(len(c.Resources)).Should(gomega.Equal(11))
	for i := 1; i <= 11; i++ {
		g.Expect(c.Resources).Should(assertions.IncludeItem(func(r *proto.Resource) bool {
			return r.Id == fmt.Sprintf("resource-%d", i) && r.Type == proto.ResourceType_Repo
		}))
	}
}

func Test_Costcenter_Create_Get_Costcenter_With_AddResourceTo_And_DuplicateResources(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerId := stubs.GetRandomId64AsString()
	costCenter := stubs.CreateAzureCostCenterWithCustomerIdAndTargetId(customerId)

	upsertRes, _ := client.CreateCostCenter(costCenter)
	_, err := client.CostCenterAddResourceTo(upsertRes.CostCenter.CostCenterKey, []*proto.Resource{
		{
			Id:   "resource-1",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-1",
			Type: proto.ResourceType_Repo,
		}})
	g.Expect(err).To(gomega.HaveOccurred())

	costCenterResponse := client.GetCostCenter(upsertRes.CostCenter.CostCenterKey)

	c := costCenterResponse.CostCenter
	g.Expect(c).ShouldNot(gomega.BeNil())
	g.Expect(len(c.Resources)).Should(gomega.Equal(0))
}

func Test_Costcenter_Create_Get_Costcenter_With_RemoveResourceFrom(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerId := stubs.GetRandomId64AsString()
	costCenter := stubs.CreateAzureCostCenterWithCustomerIdAndTargetId(customerId)

	// Patch has a limit of 10 operations per update.
	// Adding 11 resources to validate that the patch is split into 2 requests
	resources := []*proto.Resource{
		{
			Id:   "resource-1",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-2",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-3",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-4",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-5",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-6",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-7",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-8",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-9",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-10",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-11",
			Type: proto.ResourceType_Repo,
		}}

	res, _ := client.CreateCostCenter(costCenter)
	_, err := client.CostCenterAddResourceTo(res.CostCenter.CostCenterKey, append(resources, &proto.Resource{
		Id:   "resource-12", // Only resource not removed
		Type: proto.ResourceType_Repo,
	}))
	g.Expect(err).ToNot(gomega.HaveOccurred())

	costCenterResponse := client.GetCostCenter(res.CostCenter.CostCenterKey)

	c := costCenterResponse.CostCenter
	g.Expect(c).ShouldNot(gomega.BeNil())
	g.Expect(len(c.Resources)).Should(gomega.Equal(12))
	for i := 1; i <= 12; i++ {
		g.Expect(c.Resources).Should(assertions.IncludeItem(func(r *proto.Resource) bool {
			return r.Id == fmt.Sprintf("resource-%d", i) && r.Type == proto.ResourceType_Repo
		}))
	}

	_, err = client.CostCenterRemoveResourceFrom(res.CostCenter.CostCenterKey, resources)
	g.Expect(err).ToNot(gomega.HaveOccurred())

	costCenterResponse = client.GetCostCenter(res.CostCenter.CostCenterKey)

	c = costCenterResponse.CostCenter
	g.Expect(c).ShouldNot(gomega.BeNil())

	// Only resource-12 should remain
	g.Expect(len(c.Resources)).Should(gomega.Equal(1))
	g.Expect(c.Resources).Should(assertions.IncludeItem(func(r *proto.Resource) bool {
		return r.Id == "resource-12" && r.Type == proto.ResourceType_Repo
	}))
}

func Test_Costcenter_Create_Get_Costcenter_With_RemoveResourceFrom_And_NonExistingResource(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerId := stubs.GetRandomId64AsString()
	costCenter := stubs.CreateAzureCostCenterWithCustomerIdAndTargetId(customerId)
	res, _ := client.CreateCostCenter(costCenter)
	_, err := client.CostCenterAddResourceTo(res.CostCenter.CostCenterKey, []*proto.Resource{
		{
			Id:   "resource-1",
			Type: proto.ResourceType_Repo,
		}})
	g.Expect(err).ToNot(gomega.HaveOccurred())

	costCenterResponse := client.GetCostCenter(res.CostCenter.CostCenterKey)

	c := costCenterResponse.CostCenter
	g.Expect(c).ShouldNot(gomega.BeNil())
	g.Expect(len(c.Resources)).Should(gomega.Equal(1))
	g.Expect(c.Resources).Should(assertions.IncludeItem(func(r *proto.Resource) bool {
		return r.Id == "resource-1" && r.Type == proto.ResourceType_Repo
	}))

	_, err = client.CostCenterRemoveResourceFrom(res.CostCenter.CostCenterKey, []*proto.Resource{
		{
			Id:   "resource-1",
			Type: proto.ResourceType_Repo,
		},
		{
			Id:   "resource-not-found",
			Type: proto.ResourceType_Repo,
		}})
	g.Expect(err).ToNot(gomega.HaveOccurred())

	costCenterResponse = client.GetCostCenter(res.CostCenter.CostCenterKey)

	c = costCenterResponse.CostCenter
	g.Expect(c).ShouldNot(gomega.BeNil())
	g.Expect(len(c.Resources)).Should(gomega.Equal(0))
}

func Test_Costcenter_FindCostCenterFor(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	t.Cleanup(func() {
		defer client.Close()
	})

	resources := []proto.ResourceType{
		proto.ResourceType_Repo,
		proto.ResourceType_Org,
		proto.ResourceType_User,
	}

	for _, resource := range resources {
		entity := stubs.CreateEntity()
		resource := &proto.Resource{
			Id:   stubs.GetResourceIDFromEntityByType(entity, resource),
			Type: resource,
		}

		t.Run(resource.Type.String(), func(t *testing.T) {
			t.Parallel()
			findCostCenterHelper(t, resource, entity, client, g)
		})
	}
}

func findCostCenterHelper(_ *testing.T, resource *proto.Resource, entity *proto.EntityDetail, client *integration.IntegrationClient, g *gomega.GomegaWithT) {
	customerId := entity.CustomerId
	costCenter := stubs.CreateAzureCostCenterWithCustomerId(customerId)

	createResponse, _ := client.CreateCostCenter(costCenter)
	createKey := createResponse.CostCenter.CostCenterKey
	g.Expect(createKey).ShouldNot(gomega.BeNil())
	g.Expect(createKey.CustomerId).Should(gomega.Equal(customerId))
	g.Expect(createKey.Uuid).ShouldNot(gomega.BeEmpty())

	_, err := client.CostCenterAddResourceTo(createKey, []*proto.Resource{resource})
	g.Expect(err).ToNot(gomega.HaveOccurred())

	y := client.GetCostCenter(createKey)
	g.Expect(y.CostCenter).ShouldNot(gomega.BeNil())
	g.Expect(y.CostCenter.Resources).Should(assertions.IncludeItem(func(r *proto.Resource) bool {
		return r.Id == resource.Id && r.Type == resource.Type
	}), "resource should be added to cost center")

	var sku string
	if resource.Type == proto.ResourceType_User {
		sku = "copilot_for_business"
	} else {
		sku = "actions_linux"
	}

	costCenterResponse := client.FindCostCenterFor(entity, sku)

	c := costCenterResponse.CostCenterKey
	g.Expect(c).ShouldNot(gomega.BeNil())
	g.Expect(c.CustomerId).Should(gomega.Equal(createKey.Uuid))
}

func Test_Costcenter_FindCostCenter_WithUserResource_ReturnsNil_WhenUsageIsNotUserBased(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	t.Cleanup(func() {
		defer client.Close()
	})

	entity := stubs.CreateEntity()
	resource := &proto.Resource{
		Id:   stubs.GetResourceIDFromEntityByType(entity, proto.ResourceType_User),
		Type: proto.ResourceType_User,
	}

	customerId := entity.CustomerId
	costCenter := stubs.CreateAzureCostCenterWithCustomerId(customerId)

	createResponse, _ := client.CreateCostCenter(costCenter)
	createKey := createResponse.CostCenter.CostCenterKey
	g.Expect(createKey).ShouldNot(gomega.BeNil())
	g.Expect(createKey.CustomerId).Should(gomega.Equal(customerId))
	g.Expect(createKey.Uuid).ShouldNot(gomega.BeEmpty())

	_, err := client.CostCenterAddResourceTo(createKey, []*proto.Resource{resource})
	g.Expect(err).ToNot(gomega.HaveOccurred())

	y := client.GetCostCenter(createKey)
	g.Expect(y.CostCenter).ShouldNot(gomega.BeNil())
	g.Expect(y.CostCenter.Resources).Should(assertions.IncludeItem(func(r *proto.Resource) bool {
		return r.Id == resource.Id && r.Type == resource.Type
	}), "resource should be added to cost center")

	costCenterResponse := client.FindCostCenterFor(entity, "actions_linux") // models.UnitTypeMinutes

	c := costCenterResponse.CostCenterKey
	g.Expect(c).Should(gomega.BeNil())
}

func Test_Costcenter_UsageEmissionWhenResourceMovesAcrossCostCenters(t *testing.T) {
	// This test does the following:
	// 1. tests usage is emitted to a costcenter
	// 2. tests removing of resource from a costcenter
	// 2. tests adding of resources to a costcenter
	// 3. tests emission of usage to Zuora from a costcenter when resource is added/removed to it mid cycle

	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	client.EnsureProductExists("actions", "Actions", "GitHub Actions Usage")
	pricing := client.EnsureSpecificPricingExists(0.016, "actions_linux_4_core", "actions", "Actions")

	// Create costcenter 1 for customer with org1, org2
	customerId := "123"
	org1Id, org2Id := int64(1), int64(2)
	resources := map[int64]proto.ResourceType{org1Id: proto.ResourceType_Org, org2Id: proto.ResourceType_Org}
	costCenter1Key, _ := helpers.CreateCostCenter(customerId, "costcenter1", resources, proto.CostCenterType_ZuoraSubscription, client)

	// Generate and ingest usage from org1,org2
	year := 2020
	month := time.Month(10)
	usageDate := time.Date(year, month, 21, 18, 0, 0, 0, time.UTC)
	org1Quantity, org2Quantity := 10.0, 5.0
	usageFromOrg1 := stubs.CreateUsageFrom(pricing, &proto.EntityDetail{CustomerId: customerId, OwnerId: org1Id, RepoId: 888, ActorId: 667}, usageDate, org1Quantity)
	usageFromOrg2 := stubs.CreateUsageFrom(pricing, &proto.EntityDetail{CustomerId: customerId, OwnerId: org2Id, RepoId: 22, ActorId: 222}, usageDate, org2Quantity)
	helpers.IngestUsage([]*hydroSchema.Usage{usageFromOrg1, usageFromOrg2}, client)

	u := client.GetUsageTotal("", pricing.GetSku(), costCenter1Key.Uuid, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(org1Quantity+org2Quantity), "usage quantity")

	// verify usage chart data for grouped by costcenter
	response := client.GetUsageChartData("", "", customerId, usageDate, proto.BillingPeriod_Daily, proto.UsageGroupBy_GroupByCostCenter, 0, 0, "")
	items := response.UsageChartData
	g.Expect(len(items)).Should(gomega.Equal(1))
	g.Expect(items[0].Name).Should(gomega.Equal("costcenter1"))

	// Edit costcenter1 by removing org1
	org1Resource := &proto.Resource{Id: strconv.Itoa(int(org1Id)), Type: proto.ResourceType_Org}
	_, _ = client.CostCenterRemoveResourceFrom(costCenter1Key, []*proto.Resource{org1Resource})

	// Create costcenter2 with org1
	resources = map[int64]proto.ResourceType{org1Id: proto.ResourceType_Org}
	costCenter2Key, _ := helpers.CreateCostCenter(customerId, "costcenter2", resources, proto.CostCenterType_ZuoraSubscription, client)

	// Generate and ingest usage from org1,org2
	usageFromOrg1 = stubs.CreateUsageFrom(pricing, &proto.EntityDetail{CustomerId: customerId, OwnerId: org1Id, RepoId: 888, ActorId: 667}, usageDate.Add(time.Hour*1), org1Quantity)
	usageFromOrg2 = stubs.CreateUsageFrom(pricing, &proto.EntityDetail{CustomerId: customerId, OwnerId: org2Id, RepoId: 22, ActorId: 222}, usageDate.Add(time.Hour*1), org2Quantity)
	helpers.IngestUsage([]*hydroSchema.Usage{usageFromOrg1, usageFromOrg2}, client)

	u = client.GetUsageTotal("", pricing.GetSku(), costCenter2Key.Uuid, usageDate.Add(time.Hour*1), proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(org1Quantity), "usage quantity")

	response = client.GetUsageChartData("", "", customerId, usageDate, proto.BillingPeriod_Daily, proto.UsageGroupBy_GroupByCostCenter, 0, 0, "")
	items = response.UsageChartData
	g.Expect(len(items)).Should(gomega.Equal(2))

	// Run emission and check costcenter1 has 1 usage from org1 and org2
	// run emission and check costcenter2 has 1 usage from org1
	zuoraCalled := false
	client.StartZuoraServer([]func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			zuoraCalled = true
			rw.WriteHeader(200)
			_, _ = rw.Write([]byte(`{
				"success": true,
				"message": "Successfully uploaded 1 record"
			}`))
		},
		func(rw http.ResponseWriter, r *http.Request) {
			zuoraCalled = true
			rw.WriteHeader(200)
			_, _ = rw.Write([]byte(`{
				"success": true,
				"message": "Successfully uploaded 1 record"
			}`))
		},
	})
	client.ScheduleInvoiceGeneration(int64(year), int64(month))
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	ipd := &models.InvoicePartitionDetail{
		CustomerId: costCenter1Key.Uuid,
		Period:     models.InvoiceMonthly,
		Year:       int64(year),
		Month:      int64(month),
	}

	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(2, models.WorkerTypeInvoiceGeneration) // 2 invoices for the 2 cost centers

	client.RunInvoiceGeneration(1)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)
	g.Expect(zuoraCalled).To(gomega.BeTrue())
	zuoraCalled = false
	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)
	g.Expect(zuoraCalled).To(gomega.BeTrue())

	// end of invoice generation and emission

	// validate values in invoice

	CostCenter1Invoice, _ := db.NewQuerier[*models.Invoice](client.DB).ReadItem(context.Background(), client.Logger, models.NewInvoiceKey(ipd), nil)

	g.Expect(CostCenter1Invoice.State).To(gomega.Equal(models.Submitted))
	expectedCostCenter1Quantity := org1Quantity + org2Quantity*2
	expectedCostCenter1UsageTotal := models.UsageTotal{Gross: expectedCostCenter1Quantity * pricing.GetPrice(), Discount: 0, Net: expectedCostCenter1Quantity * pricing.GetPrice(), Quantity: expectedCostCenter1Quantity}
	g.Expect(*CostCenter1Invoice.UsageTotal).To(gomega.Equal(expectedCostCenter1UsageTotal))

	ipd.CustomerId = costCenter2Key.Uuid
	CostCenter2Invoice, _ := db.NewQuerier[*models.Invoice](client.DB).ReadItem(context.Background(), client.Logger, models.NewInvoiceKey(ipd), nil)

	g.Expect(CostCenter2Invoice.State).To(gomega.Equal(models.Submitted))
	costCenter2UsageTotal := models.UsageTotal{Gross: 0.16, Discount: 0, Net: 0.16, Quantity: 10}
	g.Expect(*CostCenter2Invoice.UsageTotal).To(gomega.Equal(costCenter2UsageTotal))
}

func Test_Costcenter_EmissionOfExistingUsageOnArchivedCostCenter(t *testing.T) {
	// This test does the following:
	// 1. tests usage is emitted to a costcenter
	// 2. tests archival of a costcenter
	// 3. tests emission of usage to Zuora from a costcenter that has some usage and was archived mid cycle

	client, g := integration.NewTestClient(t, integration.ClientOptions{PreserveData: true})
	defer client.Close()

	client.EnsureProductExists("actions", "Actions", "GitHub Actions Usage")
	pricing := client.EnsureSpecificPricingExists(0.016, "actions_linux_4_core", "actions", "Actions")

	// Create costcenter 1 for cusstomer with org1, org2
	customerId := "123"
	org1Id, org2Id := int64(1), int64(2)
	resources := map[int64]proto.ResourceType{org1Id: proto.ResourceType_Org, org2Id: proto.ResourceType_Org}
	costCenter1Key, _ := helpers.CreateCostCenter(customerId, "costcenter1", resources, proto.CostCenterType_ZuoraSubscription, client)

	// Generate and ingest usage from org1,org2
	year := 2020
	month := time.Month(10)
	org1Quantity, org2Quantity := 10.0, 5.0
	usageDate := time.Date(year, month, 21, 18, 0, 0, 0, time.UTC)
	usageFromOrg1 := stubs.CreateUsageFrom(pricing, &proto.EntityDetail{CustomerId: customerId, OwnerId: org1Id, RepoId: 888, ActorId: 667}, usageDate, org1Quantity)
	usageFromOrg2 := stubs.CreateUsageFrom(pricing, &proto.EntityDetail{CustomerId: customerId, OwnerId: org2Id, RepoId: 22, ActorId: 222}, usageDate, org2Quantity)
	helpers.IngestUsage([]*hydroSchema.Usage{usageFromOrg1, usageFromOrg2}, client)

	u := client.GetUsageTotal("", pricing.GetSku(), costCenter1Key.Uuid, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(org1Quantity+org2Quantity), "usage quantity")

	// Archive cost center
	client.ArchiveCostCenter(costCenter1Key)
	costCenterResponse := client.GetCostCenter(costCenter1Key)
	assert.Equal(t, proto.CostCenterState(1), costCenterResponse.CostCenter.CostCenterState)

	// Run emission on the archived cost center
	zuoraCalled := false
	client.StartZuoraServer([]func(rw http.ResponseWriter, r *http.Request){
		func(rw http.ResponseWriter, r *http.Request) {
			zuoraCalled = true
			rw.WriteHeader(200)
			_, _ = rw.Write([]byte(`{
				"success": true,
				"message": "Successfully uploaded 1 record"
			}`))
		},
	})
	client.ScheduleInvoiceGeneration(int64(year), int64(month))
	client.ValidateQueue(1, models.WorkerTypeRequestHandler)
	ipd := &models.InvoicePartitionDetail{
		CustomerId: costCenter1Key.Uuid,
		Period:     models.InvoiceMonthly,
		Year:       int64(year),
		Month:      int64(month),
	}

	client.RunRequestHandler(1)
	client.ValidateQueue(0, models.WorkerTypeRequestHandler)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)
	g.Expect(zuoraCalled).To(gomega.BeTrue())

	// end of invoice generation and emission

	// validate values in invoice

	CostCenter1Invoice, _ := db.NewQuerier[*models.Invoice](client.DB).ReadItem(context.Background(), client.Logger, models.NewInvoiceKey(ipd), nil)

	g.Expect(CostCenter1Invoice.State).To(gomega.Equal(models.Submitted))
	expectedCostCenter1Quantity := org1Quantity + org2Quantity
	expectedCostCenter1UsageTotal := models.UsageTotal{Gross: expectedCostCenter1Quantity * pricing.GetPrice(), Discount: 0, Net: expectedCostCenter1Quantity * pricing.GetPrice(), Quantity: expectedCostCenter1Quantity}
	g.Expect(*CostCenter1Invoice.UsageTotal).To(gomega.Equal(expectedCostCenter1UsageTotal))

}

func Test_Costcenter_BudgetOnCostCenter(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	entity := stubs.CreateEntity()

	customerProto := stubs.CreateEnabledCustomerWithTarget(proto.BillingTarget_Zuora)
	customerProto.CustomerId = entity.CustomerId
	_ = client.CreateCustomer(customerProto)

	costCenter := stubs.CreateAzureCostCenterWithCustomerId(entity.CustomerId)

	response, _ := client.CreateCostCenter(costCenter)
	costCenterKey := response.CostCenter.CostCenterKey
	resource := stubs.GetResource(entity, proto.ResourceType_Repo)
	_, err := client.CostCenterAddResourceTo(costCenterKey, []*proto.Resource{resource})
	g.Expect(err).ToNot(gomega.HaveOccurred())

	pricing := client.EnsureRandomPricingExists()

	amount := 10.0
	budget := stubs.CreateBudget(costCenterKey.Uuid, proto.ResourceType_Repo, fmt.Sprintf("%d", entity.RepoId), amount)
	_ = client.UpsertBudget(budget)

	// create usage
	quantity := 10.0
	usageDate := time.Date(2020, 7, 17, 18, 0, 0, 0, time.UTC)
	usage := stubs.CreateUsageFrom(pricing, entity, usageDate, quantity)

	client.ProduceMeteredUsage([]*hydroSchema.Usage{usage})

	client.RunUsageIngestion(1)
	client.RunDailyJob(1)

	u := client.GetUsageTotal("", pricing.GetSku(), costCenterKey.Uuid, usageDate, proto.BillingPeriod_Daily)
	g.Expect(float64(u.Quantity)).Should(gomega.Equal(quantity), "usage quantity")
	g.Expect(float64(u.BillableAmount)).Should(gomega.Equal(pricing.GetPrice()*quantity), "usage Amount")
}

func Test_Costcenter_Create_Cost_Center_Creates_Customer_Record(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	costCenter := stubs.CreateAzureCostCenter()
	response, _ := client.CreateCostCenter(costCenter)

	// verify that upsert cost center creates a customer record
	customerResponse := client.GetCustomer(response.CostCenter.CostCenterKey.Uuid)
	costCenterKey := response.CostCenter.CostCenterKey

	g.Expect(customerResponse.Customer).To(gomega.Not(gomega.BeNil()))
	g.Expect(customerResponse.Customer.IsCostCenterProxy).To(gomega.BeTrue())
	g.Expect(customerResponse.Customer.CustomerId).To(gomega.Equal(costCenterKey.Uuid))
	g.Expect(customerResponse.Customer.EnterpriseCustomerId).To(gomega.Equal(costCenter.CostCenterKey.CustomerId))
	g.Expect(customerResponse.Customer.CostCenterUUID).To(gomega.Equal(costCenterKey.Uuid))
	g.Expect(customerResponse.Customer.BillingTarget).To(gomega.BeEquivalentTo(proto.BillingTarget_Azure))
	g.Expect(len(customerResponse.Customer.EnabledProducts)).To(gomega.Equal(0))
	g.Expect(customerResponse.Customer.AzureAccountId).To(gomega.Equal(costCenter.CostCenterKey.TargetId))
	g.Expect(customerResponse.Customer.BillForPublicRepoUsage).To(gomega.BeFalse())
	// We don't expect these fields to be set for cost centers with azure target
	g.Expect(customerResponse.Customer.ZuoraAccountId).To(gomega.Equal(""))
	g.Expect(customerResponse.Customer.ZuoraAccountNumber).To(gomega.Equal(""))
	// this is empty as it lives on the parent customer record and should be queried from there
	g.Expect(customerResponse.Customer.DiscountPlanName).To(gomega.Equal(""))
}

func Test_Costcenter_Customer_Can_Create_Multiple_Cost_Centers_With_No_TargetId(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// stub two cost centers without target ids for the same customer
	customerId := stubs.GetRandomId64AsString()
	costCenter := stubs.CreateZuoraCostCenterWithCustomerAndResources(customerId, []*proto.Resource{{Id: "resourceId", Type: proto.ResourceType_Org}})
	costCenter2 := stubs.CreateZuoraCostCenterWithCustomerAndResources(customerId, []*proto.Resource{{Id: "anotherResourceId", Type: proto.ResourceType_Org}})

	// cost center one is created
	upsertResponse, err := client.CreateCostCenter(costCenter)
	g.Expect(err).ToNot(gomega.HaveOccurred())

	// cost center two is created
	upsertResponse2, err := client.CreateCostCenter(costCenter2)
	g.Expect(err).ToNot(gomega.HaveOccurred())

	// ensure two cost centers are created when no target ids are provided
	costCentersResponse := client.GetAllCostCenters(customerId)
	costCenters := costCentersResponse.CostCenters
	g.Expect(costCenters).To(gomega.HaveLen(2))

	costCenterResponse := client.GetCostCenter(upsertResponse.CostCenter.CostCenterKey)
	c := costCenterResponse.CostCenter
	g.Expect(c).To(gomega.Not(gomega.BeNil()))
	g.Expect(c.Name).To(gomega.Equal(costCenter.Name))
	g.Expect(c.CostCenterKey.TargetType).To(gomega.Equal(proto.CostCenterType_ZuoraSubscription))

	costCenterResponse2 := client.GetCostCenter(upsertResponse2.CostCenter.CostCenterKey)
	c2 := costCenterResponse2.CostCenter
	g.Expect(c2).To(gomega.Not(gomega.BeNil()))
	g.Expect(c2.Name).To(gomega.Equal(costCenter2.Name))
	g.Expect(c2.CostCenterKey.TargetType).To(gomega.Equal(proto.CostCenterType_ZuoraSubscription))

	// ensure two customer records are created when there are no target ids
	customerResponse := client.GetCustomer(c.CostCenterKey.Uuid)
	g.Expect(customerResponse.Customer).To(gomega.Not(gomega.BeNil()))

	customerResponse2 := client.GetCustomer(c2.CostCenterKey.Uuid)
	g.Expect(customerResponse2.Customer).To(gomega.Not(gomega.BeNil()))
}

func Test_Costcenter_Cost_Center_Updates_When_Target_Id_Is_Not_Set(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	customerId := stubs.GetRandomId64AsString()
	costCenter := stubs.CreateZuoraCostCenterWithCustomerAndResources(customerId, []*proto.Resource{{Id: "resourceId", Type: proto.ResourceType_Org}})
	res, err := client.CreateCostCenter(costCenter)

	g.Expect(err).ToNot(gomega.HaveOccurred())

	costCenterResponse := client.GetCostCenter(res.CostCenter.CostCenterKey)
	c := costCenterResponse.CostCenter

	g.Expect(c).To(gomega.Not(gomega.BeNil()))
	g.Expect(c.Name).To(gomega.Equal(costCenter.Name))
	g.Expect(c.CostCenterKey.TargetType).To(gomega.Equal(proto.CostCenterType_ZuoraSubscription))
	g.Expect(c.CostCenterKey.TargetId).To(gomega.Equal(""))
	g.Expect(c.Resources).To(gomega.HaveLen(1))

	// update the cost center with a new name and add a resource.
	updateArgs := integration.UpdateCostCenterArgs{
		CostCenterKey: c.CostCenterKey,       // Use the existing CostCenterKey from `c`
		Name:          "Updated Cost Center", // New name for the cost center
		TargetId:      "",
		ResourcesToAdd: []*proto.Resource{
			{Id: "newResourceId", Type: proto.ResourceType_Org},
		},
		ResourcesToRemove: []*proto.Resource{},
	}

	var updateRes *proto.UpdateCostCenterResponse
	updateRes, err = client.UpdateCostCenter(updateArgs)
	if err != nil {
		t.Fatalf("Failed to update cost center: %v", err)
	}

	costCenterResponse = client.GetCostCenter(updateRes.CostCenter.CostCenterKey)
	c = costCenterResponse.CostCenter
	g.Expect(err).ToNot(gomega.HaveOccurred())

	g.Expect(c.Name).To(gomega.Equal("Updated Cost Center"))
	g.Expect(c.CostCenterKey.TargetType).To(gomega.Equal(proto.CostCenterType_ZuoraSubscription))
	g.Expect(c.CostCenterKey.TargetId).To(gomega.Equal(""))
	g.Expect(c.Resources).To(gomega.HaveLen(2))
}

func Test_Costcenter_Archived_Cost_Center(t *testing.T) {
	/* This test does the following:
	  - tests create and archival of a cost center
		- tests an archived cost center cannot be updated
		- tests an archived cost centers resources can be used in a new cost center
	*/
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()
	resources := map[int64]proto.ResourceType{
		1: proto.ResourceType_Org,
		2: proto.ResourceType_Repo}
	costcenterKey, err := helpers.CreateCostCenter("123", "CostCenterToArchive", resources, proto.CostCenterType_AzureSubscription, client)

	g.Expect(err).ToNot(gomega.HaveOccurred())
	g.Expect(costcenterKey).To(gomega.Not(gomega.BeNil()))

	// archive the cost center
	archiveCostCenterResponse := client.ArchiveCostCenter(costcenterKey)
	g.Expect(archiveCostCenterResponse).To(gomega.Not(gomega.BeNil()))

	costCenterResponse := client.GetCostCenter(costcenterKey)
	g.Expect(err).ToNot(gomega.HaveOccurred())

	// CostCenterState should be updated to archived
	g.Expect(costCenterResponse.CostCenter.CostCenterState.String()).To(gomega.Equal("CostCenterArchived"))

	// The CostCenterState on the CostCenterCustomer field should be updated to archived
	ccCustomerResponse := client.GetCustomer(costCenterResponse.CostCenter.CostCenterKey.Uuid)
	g.Expect(ccCustomerResponse.Customer.CostCenterState.String()).To(gomega.Equal("CostCenterArchived"))

	// Updating an archived cost center should fail
	updateArgs := integration.UpdateCostCenterArgs{
		CostCenterKey:     costCenterResponse.CostCenter.CostCenterKey,
		Name:              "a new name",
		TargetId:          "",
		ResourcesToAdd:    []*proto.Resource{},
		ResourcesToRemove: []*proto.Resource{},
	}
	_, err = client.UpdateCostCenter(updateArgs)
	g.Expect(err).To(gomega.HaveOccurred())

	// Create a new cost center with the same resources as the archived cost center
	costcenterKey, err = helpers.CreateCostCenter("123", "A new costcenter", resources, proto.CostCenterType_AzureSubscription, client)
	g.Expect(err).ToNot(gomega.HaveOccurred())
	assert.Equal(t, costcenterKey.CustomerId, "123")

}

func Test_Costcenter_FindCostCenter_WithUserResource_ReturnsUserCostCenter_WithActorAndOrgID(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	t.Cleanup(func() {
		defer client.Close()
	})

	entity := stubs.CreateEntity()
	userResource := &proto.Resource{
		Id:   stubs.GetResourceIDFromEntityByType(entity, proto.ResourceType_User),
		Type: proto.ResourceType_User,
	}

	// create the seats based cost center
	customerId := entity.CustomerId
	costCenter1 := stubs.CreateAzureCostCenterWithCustomerId(customerId)
	createResponse1, _ := client.CreateCostCenter(costCenter1)
	createKey1 := createResponse1.CostCenter.CostCenterKey
	g.Expect(createKey1).ShouldNot(gomega.BeNil())
	g.Expect(createKey1.CustomerId).Should(gomega.Equal(customerId))
	g.Expect(createKey1.Uuid).ShouldNot(gomega.BeEmpty())
	_, err := client.CostCenterAddResourceTo(createKey1, []*proto.Resource{userResource})
	g.Expect(err).ToNot(gomega.HaveOccurred())
	y := client.GetCostCenter(createKey1)
	g.Expect(y.CostCenter).ShouldNot(gomega.BeNil())

	// create a second org based cost center under the same enterprise
	orgResource := &proto.Resource{
		Id:   stubs.GetResourceIDFromEntityByType(entity, proto.ResourceType_Org),
		Type: proto.ResourceType_Org,
	}
	customerId = entity.CustomerId
	costCenter2 := stubs.CreateAzureCostCenterWithCustomerId(customerId)
	createResponse2, _ := client.CreateCostCenter(costCenter2)
	createKey2 := createResponse2.CostCenter.CostCenterKey
	g.Expect(createKey2).ShouldNot(gomega.BeNil())
	g.Expect(createKey2.CustomerId).Should(gomega.Equal(customerId))
	g.Expect(createKey2.Uuid).ShouldNot(gomega.BeEmpty())
	_, err = client.CostCenterAddResourceTo(createKey2, []*proto.Resource{orgResource})
	g.Expect(err).ToNot(gomega.HaveOccurred())
	y = client.GetCostCenter(createKey2)
	g.Expect(y.CostCenter).ShouldNot(gomega.BeNil())

	costCenterResponse := client.FindCostCenterFor(entity, "ghec_seats") // models.UnitTypeMinutes

	c := costCenterResponse.CostCenterKey
	g.Expect(c).ShouldNot(gomega.BeNil())
	g.Expect(c.Uuid).Should(gomega.Equal(createKey1.Uuid))
}
