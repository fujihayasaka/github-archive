package resources

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-core/telemetry"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/utils"
)

//go:generate mockgen -source=$GOFILE -destination=../../gen/mocks/mocks_manager/mock_manager.go -package mocks_manager
type IManager interface {
	EnsureAzureSubscriptionAssignedToImageDefinition(ctx context.Context, imageDefinition *models.ImageDefinition) error
	GetImageBlobKey(ctx context.Context, imageVersion *models.ImageVersion) (*azure.StorageBlobKey, error)
	GetImageReference(ctx context.Context, imageVersion *models.ImageVersion) (*armcompute.ImageReference, error)
	GetExactImageVersion(ctx context.Context, imageVersionKey *internalapi.ImageKey) (*models.ImageVersion, error)
	GetGalleryImageVersionKey(ctx context.Context, imageVersion *models.ImageVersion) (*azure.GalleryImageVersionKey, error)
	GetLocationForImageBlob() string
	GetLocationForGalleryImageVersion() string
	GetSupportedImageRegions(image *models.ImageDefinition) []string
}

type Manager struct {
	cfg         Config
	imagesStore store.IImagesStore
	logger      *telemetry.ReportingLogger
}

func NewManager(cfg Config, imagesStore store.IImagesStore, logger *telemetry.ReportingLogger) *Manager {
	return &Manager{
		cfg:         cfg,
		imagesStore: imagesStore,
		logger:      logger,
	}
}

func (m *Manager) EnsureAzureSubscriptionAssignedToImageDefinition(ctx context.Context, imageDefinition *models.ImageDefinition) error {
	if imageDefinition.AzureSubscriptionId != nil {
		return nil
	}

	m.logger.Info("assigning azure subscription to image definition", kvp.Uint64("image_definition_id", imageDefinition.Id))

	assignedSubscriptionId, err := m.imagesStore.AssignAzureSubscriptionToImageDefinition(ctx, imageDefinition.Id, m.cfg.MaxImageDefinitionsPerSubscription, m.cfg.MaxSubscriptionsToQueryInDb)
	if err != nil {
		return fmt.Errorf("failed to assign azure subscription to image definition: %w", err)
	}

	m.logger.Info(
		"assigned azure subscription to image definition",
		kvp.Uint64("image_definition_id", imageDefinition.Id),
		kvp.Uint64("azure_subscription_id", assignedSubscriptionId),
	)
	m.logger.Statter.Counter("azure.assign_to_subscription", nil, 1)

	return nil
}

func (m *Manager) GetImageBlobKey(ctx context.Context, imageVersion *models.ImageVersion) (*azure.StorageBlobKey, error) {
	imageDefinition, err := m.imagesStore.GetImageDefinitionById(ctx, imageVersion.ImageDefinitionId)
	if err != nil {
		return nil, fmt.Errorf("failed to get image definition by id: %w", err)
	}

	azureSubscriptionId := imageDefinition.AzureSubscriptionId
	if azureSubscriptionId == nil {
		return nil, fmt.Errorf("azure subscription is not assigned to image definition")
	}

	azureSubscription, err := m.imagesStore.GetAzureSubscriptionById(ctx, *azureSubscriptionId)
	if err != nil {
		return nil, fmt.Errorf("failed to get azure subscription by id: %w", err)
	}

	if azureSubscription.SubscriptionId == utils.SharedDevImagesSubscriptionId {
		// if image is assigned to shared dev subscription, image blob key is not available
		return nil, fmt.Errorf(utils.SharedDevImagesErrorMessage)
	}

	resourceGroup, storageAccountName, storageContainer := m.getResourceNamesForStorage(azureSubscription.ResourcesPrefix)

	return azure.NewStorageBlobKey(
		azureSubscription.SubscriptionId,
		resourceGroup,
		storageAccountName,
		storageContainer,
		fmt.Sprintf("image-%d-%s.vhd", imageVersion.ImageDefinitionId, imageVersion.Version),
	), nil
}

func (m *Manager) GetImageReference(ctx context.Context, imageVersion *models.ImageVersion) (*armcompute.ImageReference, error) {
	imageVersionKey, err := m.GetGalleryImageVersionKey(ctx, imageVersion)
	if err != nil {
		return nil, fmt.Errorf("failed to get gallery image version key: %w", err)
	}

	id := imageVersionKey.GalleryImageVersionResourceId()
	emptyString := ""

	return &armcompute.ImageReference{
		ID:        &id,
		Offer:     &emptyString,
		Publisher: &emptyString,
		SKU:       &emptyString,
		Version:   &emptyString,
	}, nil
}

func (m *Manager) GetExactImageVersion(ctx context.Context, imageKey *internalapi.ImageKey) (*models.ImageVersion, error) {
	var err error
	var imageVersion *models.ImageVersion

	if imageKey.Version == models.LatestImageVersion {
		imageVersion, err = m.imagesStore.GetLatestImageVersion(ctx, imageKey.Id)
		if err != nil {
			return nil, fmt.Errorf("failed to get latest image version: %w", err)
		}
	} else {
		imageVersion, err = m.imagesStore.GetImageVersionByDefinitionIdAndVersion(ctx, imageKey.Id, imageKey.Version)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return nil, nil
			}
			return nil, fmt.Errorf("failed to get specific image version: %w", err)
		}
	}
	return imageVersion, nil
}

func (m *Manager) GetGalleryImageVersionKey(ctx context.Context, imageVersion *models.ImageVersion) (*azure.GalleryImageVersionKey, error) {
	imageDefinition, err := m.imagesStore.GetImageDefinitionById(ctx, imageVersion.ImageDefinitionId)
	if err != nil {
		return nil, fmt.Errorf("failed to get image definition by id: %w", err)
	}

	azureSubscriptionId := imageDefinition.AzureSubscriptionId
	if azureSubscriptionId == nil {
		return nil, fmt.Errorf("azure subscription is not assigned to image definition")
	}

	azureSubscription, err := m.imagesStore.GetAzureSubscriptionById(ctx, *azureSubscriptionId)
	if err != nil {
		return nil, fmt.Errorf("failed to get azure subscription by id: %w", err)
	}

	if azureSubscription.SubscriptionId == utils.SharedDevImagesSubscriptionId {
		// if image is assigned to shared dev subscription, use alternative way to get image version key in dev environment
		return getGalleryImageVersionKeyForSharedDevImage(imageVersion)
	}

	resourceGroup, galleryName, galleryImageName := m.getResourceNamesForGallery(imageDefinition.Id, azureSubscription.ResourcesPrefix)

	return azure.NewGalleryImageVersionKey(
		azureSubscription.SubscriptionId,
		resourceGroup,
		galleryName,
		galleryImageName,
		imageVersion.Version,
	), nil
}

func (m *Manager) GetLocationForImageBlob() string {
	return m.cfg.AzureImageLocation
}

func (m *Manager) GetLocationForGalleryImageVersion() string {
	return m.cfg.AzureImageLocation
}

func (m *Manager) GetSupportedImageRegions(image *models.ImageDefinition) []string {
	if image.ImageType == models.ImageType_Curated {
		return m.cfg.CuratedImageAzureRegions
	}

	return m.cfg.CustomImageAzureRegions
}

func (m *Manager) getResourceNamesForStorage(resourcesPrefix string) (resourceGroup, storageAccountName, storageContainer string) {
	// azure constraints for resource group names:
	// 1-90 symbols. Underscores, hyphens, periods, parentheses, and letters or digits
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftresources
	resourceGroup = fmt.Sprintf("hostedcomputeims-%s", m.getResourceGroupPostfix(resourcesPrefix))

	// azure constraints for storage account names:
	// 3-24 symbols. Lowercase letters and numbers.
	// storage name must be unique across azure
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftstorage
	storageAccountName = fmt.Sprintf("imsb%s", resourcesPrefix)

	// azure constraints for container names:
	// 3-63 symbols. Lowercase letters, numbers, and hyphens. Start with lowercase letter or number. Can't use consecutive hyphens.
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftstorages
	storageContainer = "vhds"

	return
}

func (m *Manager) getResourceNamesForGallery(imageDefinitionId uint64, resourcesPrefix string) (resourceGroup, galleryName, galleryImageName string) {
	// azure constraints for resource group names:
	// 1-90 symbols. Underscores, hyphens, periods, parentheses, and letters or digits
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftresources
	resourceGroup = fmt.Sprintf("hostedcomputeims-%s", m.getResourceGroupPostfix(resourcesPrefix))

	// azure constraints for gallery names:
	// 1-80 symbols. Alphanumerics and periods. Start and end with alphanumeric.
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftcompute
	galleryName = fmt.Sprintf("imsgallery%s", resourcesPrefix)

	// azure constraints for image definition name:
	// 1-80 symbols. Alphanumerics, underscores, hyphens, and periods. Start and end with alphanumeric.
	// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftcompute
	galleryImageName = fmt.Sprintf("image-%d", imageDefinitionId)

	return
}

func (m *Manager) getResourceGroupPostfix(resourcesPrefix string) string {
	if m.cfg.DeveloperId != "" {
		// DeveloperId is only set in development environment
		// To make sure that every developer will have own resource group, storage account and gallery
		return fmt.Sprintf("%s-%s", strings.ToLower(strings.ReplaceAll(m.cfg.DeveloperId, "-", "")), resourcesPrefix)
	}

	// Using ResourcesPrefix from DB
	return resourcesPrefix
}
