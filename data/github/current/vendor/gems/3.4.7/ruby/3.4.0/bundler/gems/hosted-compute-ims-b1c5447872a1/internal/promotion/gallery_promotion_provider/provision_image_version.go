package gallery_promotion_provider

import (
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
)

func (p *galleryPromotionProvider) ProvisionImageVersion(ctx context.Context, logger *telemetry.ReportingLogger, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion, sourceVhdUrl string) *PromotionError {
	if isUrlReachable := utils.CheckUrlReachability(ctx, logger, sourceVhdUrl); !isUrlReachable {
		return &PromotionError{
			Err:              fmt.Errorf("source VHD url is not reachable"),
			UserErrorDetails: "Source VHD URL is invalid",
			NonRetryable:     true,
		}
	}

	if err := p.resourceManager.EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition); err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to ensure azure subscription assigned to image definition: %w", err),
			UserErrorDetails: "failed to provision image",
			NonRetryable:     false,
		}
	}

	targetBlobKey, err := p.resourceManager.GetImageBlobKey(ctx, imageVersion)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to get image blob key: %w", err),
			UserErrorDetails: "failed to copy image",
			NonRetryable:     false,
		}
	}

	if err := p.copyVhdImage(ctx, logger, imageDefinition, imageVersion, targetBlobKey, sourceVhdUrl); err != nil {
		return err
	}

	targetImageVersionKey, err := p.resourceManager.GetGalleryImageVersionKey(ctx, imageVersion)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to get gallery image version key: %w", err),
			UserErrorDetails: "failed to provision image",
			NonRetryable:     false,
		}
	}

	if err := p.createImageVersion(ctx, logger, imageDefinition, imageVersion, targetBlobKey, targetImageVersionKey); err != nil {
		return err
	}

	if err := p.saveImageVersionSize(ctx, logger, imageVersion, targetImageVersionKey); err != nil {
		return err
	}

	if featureflags.IsFeatureFlagEnabledGlobally(ctx, featureflags.FeatureFlag_VhdCleanUpAfterCreate) {
		if err := p.azureClient.DeleteBlob(ctx, targetBlobKey); err != nil {
			return &PromotionError{
				Err:              fmt.Errorf("failed to delete blob after image version creation: %w", err),
				UserErrorDetails: "failed to provision image",
				NonRetryable:     false,
			}
		}
	}

	return nil
}

func (p *galleryPromotionProvider) copyVhdImage(ctx context.Context, logger *telemetry.ReportingLogger, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion, targetBlobKey *azure.StorageBlobKey, sourceVhdUrl string) *PromotionError {
	targetBlobLocation := p.resourceManager.GetLocationForImageBlob()

	if err := p.ensureAzureStorageContainerExist(ctx, &targetBlobKey.StorageContainerKey, targetBlobLocation); err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to ensure azure storage container exists: %w", err),
			UserErrorDetails: "failed to copy image",
			NonRetryable:     false,
		}
	}

	progressHandler := func(update azure.OperationProgressUpdate) {
		logger.Info("copying vhd image to blob", kvp.String("state_details", update.String()))
		if statusError := p.imagesStore.UpdateImageVersionStateDetailsForState(ctx, imageVersion.Id, models.ImageVersionState_Provisioning, update.String()); statusError != nil {
			logger.ErrorWithReport("failed to update image version state details", statusError)
		}
	}

	// validating image version state before starting image copying to storage account
	if err := p.utils.AssertImageVersionState(ctx, imageVersion.Id, models.ImageVersionState_Provisioning); err != nil {
		return &PromotionError{
			Err:              err.Err,
			UserErrorDetails: "failed to copy image",
			NonRetryable:     true,
		}
	}

	copyStartTime := time.Now()

	var err error
	if featureflags.IsFeatureFlagEnabledGlobally(ctx, featureflags.FeatureFlag_ImagePromotionFastCopy) {
		err = p.azureClient.CopyImageToBlobFastCopy(ctx, targetBlobKey, sourceVhdUrl, progressHandler)
	} else {
		err = p.azureClient.CopyImageToBlob(ctx, targetBlobKey, sourceVhdUrl, progressHandler)
	}
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to copy image to blob: %w", err),
			UserErrorDetails: "failed to copy image",
			NonRetryable:     false,
		}
	}

	// track copy image duration only if operation is successful
	logger.Info("copying vhd image to blob finished", kvp.Duration("duration", time.Since(copyStartTime)))
	logger.Statter.DistributionMs("promotion.provision_image_version.copy_image.duration", p.utils.GetStatterTagsForImageDefinition(imageDefinition), time.Since(copyStartTime))

	return nil
}

func (p *galleryPromotionProvider) createImageVersion(ctx context.Context, logger *telemetry.ReportingLogger, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion, sourceBlobKey *azure.StorageBlobKey, targetImageVersionKey *azure.GalleryImageVersionKey) *PromotionError {
	targetImageVersionLocation := p.resourceManager.GetLocationForGalleryImageVersion()

	if err := p.ensureAzureGalleryImageDefinitionExist(ctx, &targetImageVersionKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, targetImageVersionLocation); err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to ensure azure gallery image definition exists: %w", err),
			UserErrorDetails: "failed to provision image",
			NonRetryable:     true,
		}
	}

	defaultReplications, err := p.getDefaultReplications(ctx, logger, imageDefinition, imageVersion)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to get default replications: %w", err),
			UserErrorDetails: "failed to provision image",
			NonRetryable:     false,
		}
	}

	progressHandler := func(update azure.OperationProgressUpdate) {
		logger.Info("creating image version from blob", kvp.String("state_details", update.String()))
		if statusError := p.imagesStore.UpdateImageVersionStateDetailsForState(ctx, imageVersion.Id, models.ImageVersionState_Provisioning, update.String()); statusError != nil {
			logger.ErrorWithReport("failed to update image version state details", statusError)
		}
	}

	// validating image version state before starting image version creation
	if err := p.utils.AssertImageVersionState(ctx, imageVersion.Id, models.ImageVersionState_Provisioning); err != nil {
		return &PromotionError{
			Err:              err.Err,
			UserErrorDetails: "failed to provision image",
			NonRetryable:     true,
		}
	}

	createStartTime := time.Now()

	if err := p.azureClient.CreateImageVersionFromBlob(ctx, targetImageVersionKey, sourceBlobKey, targetImageVersionLocation, defaultReplications, progressHandler); err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to create image version from blob: %w", err),
			UserErrorDetails: "failed to provision image",
			NonRetryable:     false,
		}
	}

	// track create image version duration only if operation is successful
	logger.Info("creating image version from blob finished", kvp.Duration("duration", time.Since(createStartTime)))
	logger.Statter.DistributionMs("promotion.provision_image_version.create_image_version.duration", p.utils.GetStatterTagsForImageDefinition(imageDefinition), time.Since(createStartTime))

	return nil
}

func (p *galleryPromotionProvider) saveImageVersionSize(ctx context.Context, logger *telemetry.ReportingLogger, imageVersion *models.ImageVersion, targetImageVersionKey *azure.GalleryImageVersionKey) *PromotionError {
	if err := p.utils.AssertImageVersionState(ctx, imageVersion.Id, models.ImageVersionState_Provisioning); err != nil {
		return &PromotionError{
			Err:              err.Err,
			UserErrorDetails: "failed to provision image",
			NonRetryable:     true,
		}
	}

	sizeGB, err := p.azureClient.GetGalleryImageVersionSize(ctx, targetImageVersionKey)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to get gallery image version size: %w", err),
			UserErrorDetails: "failed to provision image",
			NonRetryable:     false,
		}
	}

	logger.Info("saving azure image version size", kvp.Int32("size_gb", sizeGB))

	if err := p.imagesStore.UpdateImageVersionSize(ctx, imageVersion.Id, sizeGB); err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to save image version size to database: %w", err),
			UserErrorDetails: "failed to provision image",
			NonRetryable:     false,
		}
	}

	return nil
}

func (p *galleryPromotionProvider) getDefaultReplications(ctx context.Context, logger *telemetry.ReportingLogger, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion) (azure.ImageVersionReplications, error) {
	latest, err := p.imagesStore.GetLatestImageVersion(ctx, imageDefinition.Id)
	if err != nil {
		return nil, &PromotionError{
			Err:              fmt.Errorf("failed to get latest image version: %w", err),
			UserErrorDetails: "failed to provision image",
			NonRetryable:     false,
		}
	}

	replicationData := &models.ImageVersionReplicationData{
		RegionReplicationData: make(map[string]models.ImageVersionRegionalReplicationData),
	}

	if latest != nil {
		replicationData, err = p.imagesStore.GetImageReplicationsByImageIdAndVersion(ctx, imageDefinition.Id, latest.Version)
		if err != nil {
			return nil, &PromotionError{
				Err:              fmt.Errorf("failed to get image replications by image id and version: %w", err),
				UserErrorDetails: "failed to provision image",
				NonRetryable:     false,
			}
		}
	}

	supportedRegions := p.resourceManager.GetSupportedImageRegions(imageDefinition)
	for _, region := range supportedRegions {
		if _, found := replicationData.RegionReplicationData[region]; !found {
			replicationData.RegionReplicationData[region] = models.ImageVersionRegionalReplicationData{
				VMCount:      0,
				ReplicaCount: 1,
			}
		}
	}

	defaultReplications := azure.ImageVersionReplications{}

	for region, replicationData := range replicationData.RegionReplicationData {
		defaultReplications = append(defaultReplications, azure.ImageVersionRegionReplication{
			Region:        region,
			ReplicasCount: replicationData.ReplicaCount,
		})
	}

	slices.SortFunc(defaultReplications, func(a, b azure.ImageVersionRegionReplication) int { return cmp.Compare(a.Region, b.Region) })

	if azureReplicationsToSetSerialized, err := json.Marshal(defaultReplications); err != nil {
		logger.ErrorWithReport("failed to serialize azure replication data", err)
	} else {
		logger.Info("setting initial image replication in Azure", kvp.String("image_version_replicas", string(azureReplicationsToSetSerialized)))
	}

	return defaultReplications, nil
}

func (p *galleryPromotionProvider) ensureAzureStorageContainerExist(ctx context.Context, containerKey *azure.StorageContainerKey, location string) error {
	err := p.azureClient.CreateResourceGroupIfNotExists(ctx, &containerKey.ResourceGroupKey, location)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to create resource group: %w", err),
			UserErrorDetails: "failed to create image",
			NonRetryable:     false,
		}
	}

	err = p.azureClient.CreateStorageAccountIfNotExists(ctx, &containerKey.StorageKey, location)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to create storage account: %w", err),
			UserErrorDetails: "failed to create image",
			NonRetryable:     false,
		}
	}

	err = p.azureClient.CreateStorageAccountContainerIfNotExists(ctx, containerKey)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to create storage account container: %w", err),
			UserErrorDetails: "failed to create image",
			NonRetryable:     false,
		}
	}

	return nil
}

func (p *galleryPromotionProvider) ensureAzureGalleryImageDefinitionExist(ctx context.Context, galleryImageDefinitionKey *azure.GalleryImageDefinitionKey, osType models.OsType, architecture models.Architecture, location string) error {
	err := p.azureClient.CreateResourceGroupIfNotExists(ctx, &galleryImageDefinitionKey.ResourceGroupKey, location)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to create resource group: %w", err),
			UserErrorDetails: "failed to create gallery",
			NonRetryable:     false,
		}
	}

	err = p.azureClient.CreateGalleryIfNotExists(ctx, &galleryImageDefinitionKey.GalleryKey, location)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to create gallery: %w", err),
			UserErrorDetails: "failed to create gallery",
			NonRetryable:     false,
		}
	}

	err = p.azureClient.CreateGalleryImageDefinitionIfNotExists(ctx, galleryImageDefinitionKey, osType, architecture, location)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to create gallery image definition: %w", err),
			UserErrorDetails: "failed to create gallery",
			NonRetryable:     false,
		}
	}

	return nil
}
