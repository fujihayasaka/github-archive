package azure

import (
	"context"
	"fmt"
	"net/http"
	"testing"

	azfake "github.com/Azure/azure-sdk-for-go/sdk/azcore/fake"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resources/armresources"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

func TestCheckResourceExistenceById(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	resourceId := fmt.Sprintf("/subscriptions/%s/resourceGroups/rgName", subscriptionId)

	t.Run("exists", func(t *testing.T) {
		azureClient := setup()

		fakeResourcesServer.GetByID = func(ctx context.Context, id string, apiVersion string, options *armresources.ClientGetByIDOptions) (resp azfake.Responder[armresources.ClientGetByIDResponse], errResp azfake.ErrorResponder) {
			getResourceResponse := armresources.ClientGetByIDResponse{}
			resp.SetResponse(http.StatusOK, getResourceResponse, nil)
			return
		}

		actual, err := azureClient.checkResourceExistenceById(ctx, subscriptionId, resourceId, apiVersionLatestStable)
		assert.NoError(t, err)
		assert.True(t, actual)
	})

	t.Run("not found", func(t *testing.T) {
		azureClient := setup()

		fakeResourcesServer.GetByID = func(ctx context.Context, id string, apiVersion string, options *armresources.ClientGetByIDOptions) (resp azfake.Responder[armresources.ClientGetByIDResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusNotFound, "Resource not found")
			return
		}

		actual, err := azureClient.checkResourceExistenceById(ctx, subscriptionId, resourceId, apiVersionLatestStable)
		assert.NoError(t, err)
		assert.False(t, actual)
	})

	t.Run("azure error", func(t *testing.T) {
		azureClient := setup()

		fakeResourcesServer.GetByID = func(ctx context.Context, id string, apiVersion string, options *armresources.ClientGetByIDOptions) (resp azfake.Responder[armresources.ClientGetByIDResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		_, err := azureClient.checkResourceExistenceById(ctx, subscriptionId, resourceId, apiVersionLatestStable)
		assert.ErrorContains(t, err, "failed to check resource existence")
	})

	t.Run("connection error", func(t *testing.T) {
		azureClient := setup()

		fakeResourcesServer.GetByID = func(ctx context.Context, id string, apiVersion string, options *armresources.ClientGetByIDOptions) (resp azfake.Responder[armresources.ClientGetByIDResponse], errResp azfake.ErrorResponder) {
			errResp.SetError(fmt.Errorf("Internal server error"))
			return
		}

		_, err := azureClient.checkResourceExistenceById(ctx, subscriptionId, resourceId, apiVersionLatestStable)
		assert.ErrorContains(t, err, "failed to check resource existence")
	})
}

func TestCreateResourceGroupIfNotExists(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	location := "westus2"
	resourceGroupKey := &ResourceGroupKey{
		SubscriptionId: subscriptionId,
		ResourceGroup:  "rgName",
	}

	t.Run("already exists", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(resourceGroupKey.ResourceGroupResourceId(), true)

		err := azureClient.CreateResourceGroupIfNotExists(ctx, resourceGroupKey, location)
		assert.NoError(t, err)
	})

	t.Run("created", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(resourceGroupKey.ResourceGroupResourceId(), false)
		fakeResourceGroupsServer.CreateOrUpdate = func(ctx context.Context, resourceGroupName string, parameters armresources.ResourceGroup, options *armresources.ResourceGroupsClientCreateOrUpdateOptions) (resp azfake.Responder[armresources.ResourceGroupsClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			resp.SetResponse(http.StatusOK, armresources.ResourceGroupsClientCreateOrUpdateResponse{}, nil)
			return
		}

		err := azureClient.CreateResourceGroupIfNotExists(ctx, resourceGroupKey, location)
		assert.NoError(t, err)
	})

	t.Run("failed to create", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(resourceGroupKey.ResourceGroupResourceId(), false)
		fakeResourceGroupsServer.CreateOrUpdate = func(ctx context.Context, resourceGroupName string, parameters armresources.ResourceGroup, options *armresources.ResourceGroupsClientCreateOrUpdateOptions) (resp azfake.Responder[armresources.ResourceGroupsClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		err := azureClient.CreateResourceGroupIfNotExists(ctx, resourceGroupKey, location)
		assert.ErrorContains(t, err, "failed to create resource group")
	})
}
