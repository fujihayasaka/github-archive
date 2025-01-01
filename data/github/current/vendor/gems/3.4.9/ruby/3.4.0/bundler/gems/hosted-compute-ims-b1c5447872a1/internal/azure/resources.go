package azure

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resources/armresources"
)

func (c *AzureClient) CreateResourceGroupIfNotExists(ctx context.Context, rgKey *ResourceGroupKey, location string) error {
	exist, err := c.checkResourceExistenceById(ctx, rgKey.SubscriptionId, rgKey.ResourceGroupResourceId(), apiVersionLatestStable)
	if err != nil {
		return fmt.Errorf("failed to check resource group existence: %w", err)
	} else if exist {
		return nil
	}

	client, err := c.clientBuilder.ResourceGroupsClient(rgKey.SubscriptionId)
	if err != nil {
		return fmt.Errorf("failed to initialize azure resource groups client: %w", err)
	}

	_, err = client.CreateOrUpdate(
		ctx,
		rgKey.ResourceGroup,
		armresources.ResourceGroup{
			Location: &location,
		},
		nil,
	)
	if err != nil {
		return fmt.Errorf("failed to create resource group: %w", err)
	}

	return nil
}

func (c *AzureClient) checkResourceExistenceById(ctx context.Context, subscriptionId, resourceId string, azureApiVersion apiVersion) (bool, error) {
	resourceClient, err := c.clientBuilder.ResourcesClient(subscriptionId)
	if err != nil {
		return false, fmt.Errorf("failed to initialize azure resources client: %w", err)
	}

	// It is not possible to use checkExistenceById method (https://learn.microsoft.com/en-us/rest/api/resources/resources/check-existence-by-id)
	// because of "This API currently works only for a limited set of Resource providers".
	// It doesn't work for storages and galleries.
	_, err = resourceClient.GetByID(ctx, resourceId, string(azureApiVersion), nil)
	if err == nil {
		return true, nil
	}

	var azError *azcore.ResponseError
	if errors.As(err, &azError) {
		if azError.StatusCode == http.StatusNotFound {
			return false, nil
		}
	}

	return false, fmt.Errorf("failed to check resource existence: %w", err)
}
