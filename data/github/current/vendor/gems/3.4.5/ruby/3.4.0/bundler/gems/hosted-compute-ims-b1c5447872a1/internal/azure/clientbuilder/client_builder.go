package clientbuilder

import (
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/arm"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resources/armresources"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/storage/armstorage"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/pageblob"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/utils"
)

type ClientBuilder struct {
	credentials                        azcore.TokenCredential
	clientOptionsResources             *arm.ClientOptions
	clientOptionsResourceGroups        *arm.ClientOptions
	clientOptionsStorageAccounts       *arm.ClientOptions
	clientOptionsStorageBlobContainers *arm.ClientOptions
	clientOptionsGalleries             *arm.ClientOptions
	clientOptionsGalleryImages         *arm.ClientOptions
	clientOptionsGalleryImageVersions  *arm.ClientOptions
	clientOptionsPageBlob              *pageblob.ClientOptions
}

func NewClientBuilder(credentials azcore.TokenCredential, logger *telemetry.ReportingLogger) ClientBuilder {
	telemetryPolicy := newTelemetryPolicy(logger)
	armClientOptions := &arm.ClientOptions{
		ClientOptions: policy.ClientOptions{
			PerCallPolicies: []policy.Policy{telemetryPolicy},
		},
	}
	pageBlobClientOptions := &pageblob.ClientOptions{
		ClientOptions: policy.ClientOptions{
			PerCallPolicies: []policy.Policy{telemetryPolicy},
		},
	}

	return ClientBuilder{
		credentials:                        credentials,
		clientOptionsResources:             armClientOptions,
		clientOptionsResourceGroups:        armClientOptions,
		clientOptionsStorageAccounts:       armClientOptions,
		clientOptionsStorageBlobContainers: armClientOptions,
		clientOptionsGalleries:             armClientOptions,
		clientOptionsGalleryImages:         armClientOptions,
		clientOptionsGalleryImageVersions:  armClientOptions,
		clientOptionsPageBlob:              pageBlobClientOptions,
	}
}

func NewClientBuilderWithClientOptions(credentials azcore.TokenCredential, clientOptionsResources, clientOptionsResourceGroups, clientOptionsStorageAccounts, clientOptionsStorageBlobContainers, clientOptionsGalleries, clientOptionsGalleryImages, clientOptionsGalleryImageVersions *arm.ClientOptions, clientOptionsPageBlob *pageblob.ClientOptions) ClientBuilder {
	return ClientBuilder{
		credentials:                        credentials,
		clientOptionsResources:             clientOptionsResources,
		clientOptionsResourceGroups:        clientOptionsResourceGroups,
		clientOptionsStorageAccounts:       clientOptionsStorageAccounts,
		clientOptionsStorageBlobContainers: clientOptionsStorageBlobContainers,
		clientOptionsGalleries:             clientOptionsGalleries,
		clientOptionsGalleryImages:         clientOptionsGalleryImages,
		clientOptionsGalleryImageVersions:  clientOptionsGalleryImageVersions,
		clientOptionsPageBlob:              clientOptionsPageBlob,
	}
}

func (c *ClientBuilder) ResourcesClient(subscriptionId string) (*armresources.Client, error) {
	if err := assertSharedDevImagesSubscription(subscriptionId); err != nil {
		return nil, err
	}
	return armresources.NewClient(subscriptionId, c.credentials, c.clientOptionsResources)
}

func (c *ClientBuilder) ResourceGroupsClient(subscriptionId string) (*armresources.ResourceGroupsClient, error) {
	if err := assertSharedDevImagesSubscription(subscriptionId); err != nil {
		return nil, err
	}
	return armresources.NewResourceGroupsClient(subscriptionId, c.credentials, c.clientOptionsResourceGroups)
}

func (c *ClientBuilder) StorageAccountsClient(subscriptionId string) (*armstorage.AccountsClient, error) {
	if err := assertSharedDevImagesSubscription(subscriptionId); err != nil {
		return nil, err
	}
	return armstorage.NewAccountsClient(subscriptionId, c.credentials, c.clientOptionsStorageAccounts)
}

func (c *ClientBuilder) StorageContainersClient(subscriptionId string) (*armstorage.BlobContainersClient, error) {
	if err := assertSharedDevImagesSubscription(subscriptionId); err != nil {
		return nil, err
	}
	return armstorage.NewBlobContainersClient(subscriptionId, c.credentials, c.clientOptionsStorageBlobContainers)
}

func (c *ClientBuilder) GalleriesClient(subscriptionId string) (*armcompute.GalleriesClient, error) {
	if err := assertSharedDevImagesSubscription(subscriptionId); err != nil {
		return nil, err
	}
	return armcompute.NewGalleriesClient(subscriptionId, c.credentials, c.clientOptionsGalleries)
}

func (c *ClientBuilder) GalleryImagesClient(subscriptionId string) (*armcompute.GalleryImagesClient, error) {
	if err := assertSharedDevImagesSubscription(subscriptionId); err != nil {
		return nil, err
	}
	return armcompute.NewGalleryImagesClient(subscriptionId, c.credentials, c.clientOptionsGalleryImages)
}

func (c *ClientBuilder) GalleryImageVersionsClient(subscriptionId string) (*armcompute.GalleryImageVersionsClient, error) {
	if err := assertSharedDevImagesSubscription(subscriptionId); err != nil {
		return nil, err
	}
	return armcompute.NewGalleryImageVersionsClient(subscriptionId, c.credentials, c.clientOptionsGalleryImageVersions)
}

func (c *ClientBuilder) PageBlobClient(subscriptionId string, blobUrl string) (*pageblob.Client, error) {
	if err := assertSharedDevImagesSubscription(subscriptionId); err != nil {
		return nil, err
	}
	return pageblob.NewClient(blobUrl, c.credentials, c.clientOptionsPageBlob)
}

func assertSharedDevImagesSubscription(subscriptionId string) error {
	if subscriptionId == utils.SharedDevImagesSubscriptionId {
		// operations with shared dev subscription are not allowed
		return fmt.Errorf(utils.SharedDevImagesErrorMessage)
	}

	return nil
}
