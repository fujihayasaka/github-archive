package gallery_promotion_provider

import (
	"context"
	"fmt"

	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
)

func (p *galleryPromotionProvider) CleanupImageVersionResources(ctx context.Context, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion) *PromotionError {
	if imageVersion.AzureSubscriptionId == nil {
		// if image version is not assigned to azure subscription, it means image promotion wasn't started for the image version yet
		// and no resources allocated in Azure yet so nothing to clean up
		return nil
	}

	imageVersionKey, err := p.getGalleryImageVersionKey(ctx, imageVersion)
	if err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to get gallery image version key: %w", err),
			NonRetryable: false,
		}
	}

	if err = p.azureClient.DeleteImageVersion(ctx, imageVersionKey); err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to delete image version from azure: %w", err),
			NonRetryable: false,
		}
	}

	targetBlobKey, err := p.getImageBlobKey(ctx, imageVersion)
	if err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to get image blob key: %w", err),
			NonRetryable: false,
		}
	}

	if err := p.azureClient.DeleteBlob(ctx, targetBlobKey); err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to delete blob after image version deletion: %w", err),
			NonRetryable: false,
		}
	}

	// trying to delete parent resources of image version and unassign azure subscription from image definition if possible
	if err := p.deleteImageVersionParentResourcesFromAzureIfPossible(ctx, imageVersion, imageVersionKey); err != nil {
		return err
	}

	if err := p.imagesStore.UnassignAzureSubscriptionFromImageVersion(ctx, imageVersion.Id); err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to unassign azure subscription from image version: %w", err),
			NonRetryable: false,
		}
	}

	return nil
}

func (p *galleryPromotionProvider) deleteImageVersionParentResourcesFromAzureIfPossible(ctx context.Context, imageVersion *models.ImageVersion, imageVersionKey *azure.GalleryImageVersionKey) *PromotionError {
	imageDefinitionKey := &imageVersionKey.GalleryImageDefinitionKey

	if galleryDefinitionExist, err := p.azureClient.CheckGalleryImageDefinitionExists(ctx, imageDefinitionKey); err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to check gallery image definition existence: %w", err),
			NonRetryable: false,
		}
	} else if !galleryDefinitionExist {
		// nothing to clean up
		return nil
	}

	remainAzureImageVersionsInDefinition, err := p.azureClient.ListImageVersions(ctx, imageDefinitionKey, 1)
	if err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to list image versions for compute gallery image definition: %w", err),
			NonRetryable: false,
		}
	}
	if len(remainAzureImageVersionsInDefinition) > 0 {
		return nil
	}

	// azure image definition state is not synchronized with image definition in database
	// azure image definition is created on demand when first image version is uploaded
	// and should be removed when last image version is deleted
	if err := p.azureClient.DeleteImageDefinition(ctx, imageDefinitionKey); err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to delete image definition: %w", err),
			NonRetryable: false,
		}
	}

	return nil
}
