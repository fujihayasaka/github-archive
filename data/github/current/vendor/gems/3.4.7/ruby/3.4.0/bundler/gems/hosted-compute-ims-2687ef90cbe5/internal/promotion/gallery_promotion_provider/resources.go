package gallery_promotion_provider

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
	"github.com/github/hosted-compute-ims/internal/utils"
)

func (p *galleryPromotionProvider) GetAzureRegionsForReplication(image *models.ImageDefinition) []string {
	if image.ImageType == models.ImageType_Curated {
		return p.cfg.CuratedImageAzureRegions
	}

	return p.cfg.CustomImageAzureRegions
}

func (p *galleryPromotionProvider) getGalleryImageVersionKey(ctx context.Context, imageVersion *models.ImageVersion) (*azure.GalleryImageVersionKey, error) {
	if imageVersion.AzureSubscriptionId == nil {
		return nil, fmt.Errorf("azure subscription is not assigned to image version")
	}

	azureSubscription, err := p.imagesStore.GetAzureSubscriptionById(ctx, *imageVersion.AzureSubscriptionId)
	if err != nil {
		return nil, fmt.Errorf("failed to get azure subscription by id: %w", err)
	}

	if azureSubscription.SubscriptionId == utils.SharedDevImagesSubscriptionId {
		// if image is assigned to shared dev subscription, image version key is not available
		return nil, fmt.Errorf(utils.SharedDevImagesErrorMessage)
	}

	azureResourcesNaming := p.getAzureResourcesNames(imageVersion, azureSubscription)
	return azure.NewGalleryImageVersionKey(
		azureSubscription.SubscriptionId,
		azureResourcesNaming.ResourceGroupName,
		azureResourcesNaming.GalleryName,
		azureResourcesNaming.GalleryImageDefinitionName,
		azureResourcesNaming.GalleryImageVersion,
	), nil
}

func (p *galleryPromotionProvider) GetImageVersionResourceId(ctx context.Context, imageVersion *models.ImageVersion) (string, error) {
	imageVersionKey, err := p.getGalleryImageVersionKey(ctx, imageVersion)
	if err != nil {
		return "", fmt.Errorf("failed to get gallery image version key: %w", err)
	}

	return imageVersionKey.GalleryImageVersionResourceId(), nil
}

func (p *galleryPromotionProvider) getImageBlobKey(ctx context.Context, imageVersion *models.ImageVersion) (*azure.StorageBlobKey, error) {
	if imageVersion.AzureSubscriptionId == nil {
		return nil, fmt.Errorf("azure subscription is not assigned to image version")
	}

	azureSubscription, err := p.imagesStore.GetAzureSubscriptionById(ctx, *imageVersion.AzureSubscriptionId)
	if err != nil {
		return nil, fmt.Errorf("failed to get azure subscription by id: %w", err)
	}

	if azureSubscription.SubscriptionId == utils.SharedDevImagesSubscriptionId {
		// if image is assigned to shared dev subscription, image blob key is not available
		return nil, fmt.Errorf(utils.SharedDevImagesErrorMessage)
	}

	azureResourcesNaming := p.getAzureResourcesNames(imageVersion, azureSubscription)
	return azure.NewStorageBlobKey(
		azureSubscription.SubscriptionId,
		azureResourcesNaming.ResourceGroupName,
		azureResourcesNaming.StorageAccountName,
		azureResourcesNaming.StorageContainerName,
		azureResourcesNaming.StorageBlobName,
	), nil
}

func (p *galleryPromotionProvider) ensureAzureSubscriptionAssignedToImageVersion(ctx context.Context, imageVersion *models.ImageVersion) (*models.ImageVersion, error) {
	if imageVersion.AzureSubscriptionId != nil {
		return imageVersion, nil
	}

	logger.Info(ctx, "assigning azure subscription to image version", kvp.Uint64("image_version_id", imageVersion.Id))

	imageVersion, err := p.imagesStore.AssignAzureSubscriptionToImageVersion(ctx, imageVersion.Id)
	if err != nil {
		return nil, fmt.Errorf("failed to assign azure subscription to image version: %w", err)
	}

	if imageVersion.AzureSubscriptionId == nil {
		return nil, fmt.Errorf("azure subscription was assigned to image version but azure subscription id is not passed to image version")
	}

	logger.Info(ctx,
		"assigned azure subscription to image version",
		kvp.Uint64("image_version_id", imageVersion.Id),
		kvp.Uint64("azure_subscription_id", *imageVersion.AzureSubscriptionId),
	)
	statter.Increment(ctx, "azure.assign_to_subscription")

	return imageVersion, nil
}

type azureResourcesNaming struct {
	ResourceGroupName          string
	StorageAccountName         string
	StorageContainerName       string
	StorageBlobName            string
	GalleryName                string
	GalleryImageDefinitionName string
	GalleryImageVersion        string
}

func (p *galleryPromotionProvider) getAzureResourcesNames(imageVersion *models.ImageVersion, azureSubscription *models.AzureSubscription) azureResourcesNaming {
	result := azureResourcesNaming{}

	// resources prefix is:
	// 		production: 32-bit integer up to 4294967296 (10 symbols)
	// 		dev: timestamp like 20250124155718 (14 symbols)
	resourcesPrefix := azureSubscription.ResourcesPrefix

	// azure constraints for resource group names:
	// 1-90 symbols. Underscores, hyphens, periods, parentheses, and letters or digits
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftresources
	result.ResourceGroupName = fmt.Sprintf("hostedcomputeims-%s-rg", p.getResourceGroupPrefix(resourcesPrefix))

	// azure constraints for storage account names:
	// 3-24 symbols. Lowercase letters and numbers.
	// storage name MUST be unique across azure
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftstorage
	result.StorageAccountName = fmt.Sprintf("ims%s", resourcesPrefix)

	// azure constraints for container names:
	// 3-63 symbols. Lowercase letters, numbers, and hyphens. Start with lowercase letter or number. Can't use consecutive hyphens.
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftstorages
	result.StorageContainerName = "vhds"

	// azure constraints for blob names:
	// Any URL characters, case sensitive
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftstorage
	result.StorageBlobName = fmt.Sprintf("image-%d-%s.vhd", imageVersion.ImageDefinitionId, imageVersion.Version)

	// azure constraints for gallery names:
	// 1-80 symbols. Alphanumerics and periods. Start and end with alphanumeric.
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftcompute
	result.GalleryName = fmt.Sprintf("imsgallery.%s", resourcesPrefix)

	// azure constraints for gallery image definition name:
	// 1-80 symbols. Alphanumerics, underscores, hyphens, and periods. Start and end with alphanumeric.
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftcompute
	result.GalleryImageDefinitionName = fmt.Sprintf("image-%d-%s", imageVersion.ImageDefinitionId, strings.ToLower(string(imageVersion.VmGeneration)))
	if imageVersion.OsState == models.OsState_Specialized {
		result.GalleryImageDefinitionName += "-sp"
	}

	// azure constraints for gallery image versions:
	// Numbers and periods. (Each segment is converted to an int32. So each segment has a max value of 2,147,483,647.)
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftcompute
	result.GalleryImageVersion = imageVersion.Version

	// Summary:
	//		ResourceGroupName:              hostedcomputeims-1658309489-rg (or hostedcomputeims-<alias>-20250124161048-rg in dev env)
	// 		StorageAccountName:             ims1658309489
	//		StorageContainerName:           vhds
	//		StorageBlobName:                image-35-1.0.0.vhd
	//		GalleryName:                    imsgallery.1658309489
	//		GalleryImageDefinitionName:     image-1-gen1
	//		GalleryImageVersion:            1.0.0
	return result
}

func (p *galleryPromotionProvider) getResourceGroupPrefix(resourcesPrefix string) string {
	if p.cfg.DeveloperId != "" {
		// DeveloperId is only set in development environment
		// To make sure that every developer will have own resource group, storage account and gallery
		return fmt.Sprintf("%s-%s", strings.ToLower(strings.ReplaceAll(p.cfg.DeveloperId, "-", "")), resourcesPrefix)
	}

	// Using ResourcesPrefix from DB
	return resourcesPrefix
}
