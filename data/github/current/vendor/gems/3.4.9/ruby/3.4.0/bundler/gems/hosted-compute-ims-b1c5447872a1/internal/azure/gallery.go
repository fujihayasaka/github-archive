package azure

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5"
	"github.com/github/hosted-compute-ims/internal/models"
)

const (
	createImageVersionTimeout            = 4 * time.Hour
	createImageVersionPollingInterval    = 20 * time.Second
	createGalleryTimeout                 = 1 * time.Minute
	createGalleryPollingInterval         = 1 * time.Second
	deleteImageVersionTimeout            = 5 * time.Minute
	deleteImageVersionPollingInterval    = 10 * time.Second
	deleteImageDefinitionTimeout         = 1 * time.Minute
	deleteImageDefinitionPollingInterval = 1 * time.Second
)

type ImageVersionRegionReplication struct {
	Region        string
	ReplicasCount int32
}

type ImageVersionReplications []ImageVersionRegionReplication

func (r ImageVersionReplications) ToArmComputeTargetRegions() []*armcompute.TargetRegion {
	result := []*armcompute.TargetRegion{}
	for _, regionData := range r {
		result = append(result, &armcompute.TargetRegion{
			Name:                 to.Ptr(regionData.Region),
			RegionalReplicaCount: to.Ptr(regionData.ReplicasCount),
			StorageAccountType:   to.Ptr(armcompute.StorageAccountTypeStandardLRS),
		})
	}
	return result
}

func (c *AzureClient) CreateImageVersionFromBlob(ctx context.Context, imageVersionKey *GalleryImageVersionKey, blob *StorageBlobKey, location string, replicationRegions ImageVersionReplications, progressReporter func(update OperationProgressUpdate)) error {
	operationCtx, cancelFunc := context.WithTimeout(ctx, createImageVersionTimeout)
	defer cancelFunc()

	client, err := c.clientBuilder.GalleryImageVersionsClient(imageVersionKey.SubscriptionId)
	if err != nil {
		return fmt.Errorf("failed to initialize compute gallery image versions client: %w", err)
	}

	isAlreadyStarted, err := c.checkImageVersionExistence(operationCtx, imageVersionKey)
	if err != nil {
		return fmt.Errorf("failed to check image version status: %w", err)
	}

	if !isAlreadyStarted {
		_, err = client.BeginCreateOrUpdate(
			ctx,
			imageVersionKey.ResourceGroup,
			imageVersionKey.GalleryName,
			imageVersionKey.ImageDefinitionName,
			imageVersionKey.Version,
			armcompute.GalleryImageVersion{
				Location: &location,
				Properties: &armcompute.GalleryImageVersionProperties{
					PublishingProfile: &armcompute.GalleryImageVersionPublishingProfile{
						ReplicationMode:    to.Ptr(armcompute.ReplicationModeFull),
						StorageAccountType: to.Ptr(armcompute.StorageAccountTypeStandardLRS),
						TargetRegions:      replicationRegions.ToArmComputeTargetRegions(),
					},
					SafetyProfile: &armcompute.GalleryImageVersionSafetyProfile{
						AllowDeletionOfReplicatedLocations: to.Ptr(true),
					},
					StorageProfile: &armcompute.GalleryImageVersionStorageProfile{
						OSDiskImage: &armcompute.GalleryOSDiskImage{
							Source: &armcompute.GalleryDiskImageSource{
								StorageAccountID: to.Ptr(blob.StorageResourceId()),
								URI:              to.Ptr(blob.BlobUrl()),
							},
						},
					},
				},
			},
			nil,
		)
		if err != nil {
			return fmt.Errorf("failed to create image version from blob: %w", err)
		}
	}

	// Don't use default poller because it doesn't provide enough information about progress (detailed replication status is missed)
	for {
		select {
		case <-operationCtx.Done():
			return fmt.Errorf("creating image version from blob failed: %w", operationCtx.Err())
		default:
			resp, err := client.Get(
				operationCtx,
				imageVersionKey.ResourceGroup,
				imageVersionKey.GalleryName,
				imageVersionKey.ImageDefinitionName,
				imageVersionKey.Version,
				&armcompute.GalleryImageVersionsClientGetOptions{
					Expand: to.Ptr(armcompute.ReplicationStatusTypesReplicationStatus),
				},
			)
			if err != nil {
				return fmt.Errorf("failed to poll image version creation status: %w", err)
			}

			switch {
			case resp.Properties.ProvisioningState != nil && *resp.Properties.ProvisioningState == armcompute.GalleryProvisioningStateSucceeded:
				return nil
			case resp.Properties.ProvisioningState != nil && *resp.Properties.ProvisioningState == armcompute.GalleryProvisioningStateFailed:
				return fmt.Errorf("failed to create image version from blob with status '%s'", *resp.Properties.ProvisioningState)
			default:
				progressReporter(galleryImageVersionDetailsToOperationProgressUpdate(&resp))
			}
		}

		time.Sleep(createImageVersionPollingInterval)
	}
}

func (c *AzureClient) CreateGalleryIfNotExists(ctx context.Context, galleryKey *GalleryKey, location string) error {
	operationCtx, cancelFunc := context.WithTimeout(ctx, createGalleryTimeout)
	defer cancelFunc()

	exist, err := c.checkResourceExistenceById(operationCtx, galleryKey.SubscriptionId, galleryKey.GalleryResourceId(), apiVersionGalleryResources)
	if err != nil {
		return fmt.Errorf("failed to check gallery existence: %w", err)
	} else if exist {
		return nil
	}

	client, err := c.clientBuilder.GalleriesClient(galleryKey.SubscriptionId)
	if err != nil {
		return fmt.Errorf("failed to initialize azure galleries client: %w", err)
	}

	poller, err := client.BeginCreateOrUpdate(
		ctx,
		galleryKey.ResourceGroup,
		galleryKey.GalleryName,
		armcompute.Gallery{
			Location: &location,
		},
		nil,
	)
	if err != nil {
		return fmt.Errorf("failed to create gallery: %w", err)
	}

	_, err = poller.PollUntilDone(operationCtx, &runtime.PollUntilDoneOptions{Frequency: createGalleryPollingInterval})
	if err != nil {
		return fmt.Errorf("failed to poll gallery creation status: %w", err)
	}

	return nil
}

func (c *AzureClient) CreateGalleryImageDefinitionIfNotExists(ctx context.Context, galleryImageDefinitionKey *GalleryImageDefinitionKey, osType models.OsType, architecture models.Architecture, location string) error {
	operationCtx, cancelFunc := context.WithTimeout(ctx, createGalleryTimeout)
	defer cancelFunc()

	exist, err := c.CheckGalleryImageDefinitionExists(operationCtx, galleryImageDefinitionKey)
	if err != nil {
		return err
	} else if exist {
		return nil
	}

	client, err := c.clientBuilder.GalleryImagesClient(galleryImageDefinitionKey.SubscriptionId)
	if err != nil {
		return fmt.Errorf("failed to initialize azure gallery images client: %w", err)
	}

	poller, err := client.BeginCreateOrUpdate(
		operationCtx,
		galleryImageDefinitionKey.ResourceGroup,
		galleryImageDefinitionKey.GalleryName,
		galleryImageDefinitionKey.ImageDefinitionName,
		armcompute.GalleryImage{
			Location: &location,
			Properties: &armcompute.GalleryImageProperties{
				Identifier: &armcompute.GalleryImageIdentifier{
					// TO-DO: Revisit these properties later
					// Runner service uses semi-random values here
					Publisher: to.Ptr("hosted-compute-ims"),
					Offer:     to.Ptr("images"),
					SKU:       to.Ptr(galleryImageDefinitionKey.ImageDefinitionName),
				},
				OSState:      to.Ptr(armcompute.OperatingSystemStateTypesGeneralized),
				OSType:       to.Ptr(osTypeToAzureOperatingSystem(osType)),
				Architecture: to.Ptr(architectureToAzureArchitecture(architecture)),
			},
		},
		nil,
	)
	if err != nil {
		return fmt.Errorf("failed to create gallery image definition: %w", err)
	}

	_, err = poller.PollUntilDone(operationCtx, &runtime.PollUntilDoneOptions{Frequency: createGalleryPollingInterval})
	if err != nil {
		return fmt.Errorf("failed to poll gallery image definition creation status: %w", err)
	}

	return nil
}

func (c *AzureClient) CheckGalleryImageDefinitionExists(ctx context.Context, galleryImageDefinitionKey *GalleryImageDefinitionKey) (bool, error) {
	exist, err := c.checkResourceExistenceById(ctx, galleryImageDefinitionKey.SubscriptionId, galleryImageDefinitionKey.GalleryImageDefinitionResourceId(), apiVersionGalleryResources)
	if err != nil {
		return false, fmt.Errorf("failed to check gallery image definition existence: %w", err)
	}

	return exist, nil
}

func (c *AzureClient) ListImageVersions(ctx context.Context, imageDefinitionKey *GalleryImageDefinitionKey, top int) ([]*armcompute.GalleryImageVersion, error) {
	client, err := c.clientBuilder.GalleryImageVersionsClient(imageDefinitionKey.SubscriptionId)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize azure gallery image versions client: %w", err)
	}

	result := make([]*armcompute.GalleryImageVersion, 0)
	pager := client.NewListByGalleryImagePager(imageDefinitionKey.ResourceGroup, imageDefinitionKey.GalleryName, imageDefinitionKey.ImageDefinitionName, nil)

pagerLoop:
	for pager.More() {
		page, err := pager.NextPage(ctx)
		if err != nil {
			return nil, fmt.Errorf("failed to advance page: %w", err)
		}

		for _, imageVersion := range page.Value {
			result = append(result, imageVersion)

			if len(result) >= top {
				break pagerLoop
			}
		}
	}

	return result, nil
}

func (c *AzureClient) DeleteImageVersion(ctx context.Context, imageVersionKey *GalleryImageVersionKey) error {
	operationCtx, cancelFunc := context.WithTimeout(ctx, deleteImageVersionTimeout)
	defer cancelFunc()

	exist, err := c.checkImageVersionExistence(operationCtx, imageVersionKey)
	if err != nil {
		return fmt.Errorf("failed to check image version status: %w", err)
	}

	if !exist {
		return nil
	}

	client, err := c.clientBuilder.GalleryImageVersionsClient(imageVersionKey.SubscriptionId)
	if err != nil {
		return fmt.Errorf("failed to initialize azure gallery image versions client: %w", err)
	}

	poller, err := client.BeginDelete(operationCtx, imageVersionKey.ResourceGroup, imageVersionKey.GalleryName, imageVersionKey.ImageDefinitionName, imageVersionKey.Version, nil)
	if err != nil {
		return fmt.Errorf("failed to begin gallery image version deletion: %w", err)
	}

	_, err = poller.PollUntilDone(operationCtx, &runtime.PollUntilDoneOptions{Frequency: deleteImageVersionPollingInterval})
	if err != nil {
		return fmt.Errorf("failed to poll image version deletion status: %w", err)
	}

	return nil
}

func (c *AzureClient) DeleteImageDefinition(ctx context.Context, imageDefinitionKey *GalleryImageDefinitionKey) error {
	operationCtx, cancelFunc := context.WithTimeout(ctx, deleteImageDefinitionTimeout)
	defer cancelFunc()

	exist, err := c.checkResourceExistenceById(operationCtx, imageDefinitionKey.SubscriptionId, imageDefinitionKey.GalleryImageDefinitionResourceId(), apiVersionGalleryResources)
	if err != nil {
		return fmt.Errorf("failed to check gallery image definition existence: %w", err)
	}

	if !exist {
		return nil
	}

	client, err := c.clientBuilder.GalleryImagesClient(imageDefinitionKey.SubscriptionId)
	if err != nil {
		return fmt.Errorf("failed to initialize azure gallery images client: %w", err)
	}

	poller, err := client.BeginDelete(operationCtx, imageDefinitionKey.ResourceGroup, imageDefinitionKey.GalleryName, imageDefinitionKey.ImageDefinitionName, nil)
	if err != nil {
		return fmt.Errorf("failed to begin gallery image definition deletion: %w", err)
	}

	_, err = poller.PollUntilDone(operationCtx, &runtime.PollUntilDoneOptions{Frequency: deleteImageDefinitionPollingInterval})
	if err != nil {
		return fmt.Errorf("failed to poll gallery image definition deletion status: %w", err)
	}

	return nil
}

func (c *AzureClient) GetGalleryImageVersionSize(ctx context.Context, imageVersionKey *GalleryImageVersionKey) (int32, error) {
	client, err := c.clientBuilder.GalleryImageVersionsClient(imageVersionKey.SubscriptionId)
	if err != nil {
		return 0, fmt.Errorf("failed to initialize compute gallery image versions client: %w", err)
	}

	resp, err := client.Get(ctx, imageVersionKey.ResourceGroup, imageVersionKey.GalleryName, imageVersionKey.ImageDefinitionName, imageVersionKey.Version, nil)
	if err != nil {
		return 0, fmt.Errorf("failed to get image version properties: %w", err)
	}

	sizeGB := resp.Properties.StorageProfile.OSDiskImage.SizeInGB
	if sizeGB == nil {
		return 0, fmt.Errorf("failed to get image version size: size is nil")
	}

	return *sizeGB, nil
}

func (c *AzureClient) UpdateImageVersionReplications(ctx context.Context, imageVersionKey *GalleryImageVersionKey, replicationRegions ImageVersionReplications) error {
	client, err := c.clientBuilder.GalleryImageVersionsClient(imageVersionKey.SubscriptionId)
	if err != nil {
		return fmt.Errorf("failed to initialize compute gallery image versions client: %w", err)
	}

	_, err = client.BeginUpdate(ctx, imageVersionKey.ResourceGroup, imageVersionKey.GalleryName, imageVersionKey.ImageDefinitionName, imageVersionKey.Version, armcompute.GalleryImageVersionUpdate{
		Properties: &armcompute.GalleryImageVersionProperties{
			PublishingProfile: &armcompute.GalleryImageVersionPublishingProfile{
				TargetRegions: replicationRegions.ToArmComputeTargetRegions(),
			},
		},
	}, nil)
	if err != nil {
		return fmt.Errorf("failed to update image version replications: %w", err)
	}

	// the method doesn't wait for all replications to be completed
	// so no need to poll for results

	return nil
}

func (c *AzureClient) checkImageVersionExistence(ctx context.Context, imageVersionKey *GalleryImageVersionKey) (bool, error) {
	client, err := c.clientBuilder.GalleryImageVersionsClient(imageVersionKey.SubscriptionId)
	if err != nil {
		return false, fmt.Errorf("failed to initialize azure gallery image versions client: %w", err)
	}

	_, err = client.Get(ctx, imageVersionKey.ResourceGroup, imageVersionKey.GalleryName, imageVersionKey.ImageDefinitionName, imageVersionKey.Version, nil)
	if err != nil {
		var azError *azcore.ResponseError
		if errors.As(err, &azError) {
			if azError.StatusCode == http.StatusNotFound {
				return false, nil
			}
		}

		return false, fmt.Errorf("failed to check image version existence: %w", err)
	}

	return true, nil
}

func osTypeToAzureOperatingSystem(osType models.OsType) armcompute.OperatingSystemTypes {
	switch osType {
	case models.OsType_Windows:
		return armcompute.OperatingSystemTypesWindows
	case models.OsType_Linux:
		return armcompute.OperatingSystemTypesLinux
	default:
		return armcompute.OperatingSystemTypes("")
	}
}

func architectureToAzureArchitecture(architecture models.Architecture) armcompute.Architecture {
	switch architecture {
	case models.Architecture_X64:
		return armcompute.ArchitectureX64
	case models.Architecture_Arm64:
		return armcompute.ArchitectureArm64
	default:
		return armcompute.Architecture("")
	}
}
