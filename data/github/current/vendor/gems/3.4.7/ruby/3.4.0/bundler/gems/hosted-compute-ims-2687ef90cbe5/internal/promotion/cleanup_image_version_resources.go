package promotion

import (
	"context"
	"fmt"

	"github.com/github/hosted-compute-ims/internal/models"
)

func (c *ImagePromotionClient) CleanupImageVersionResources(ctx context.Context, imageVersionId uint64) *PromotionError {
	imageDefinition, imageVersion, err := c.utils.GetImageDefinitionAndVersionByVersionId(ctx, imageVersionId)
	if err != nil {
		return err
	}

	if err := c.utils.AssertImageVersionState(ctx, imageVersionId, models.ImageVersionState_Deleting, models.ImageVersionState_ProvisionFailed); err != nil {
		return err
	}

	var promErr *PromotionError
	switch {
	case imageDefinition.IsGalleryImageDefinition():
		promErr = c.galleryProvider.CleanupImageVersionResources(ctx, imageDefinition, imageVersion)
	case imageDefinition.OsType == models.OsType_MacOS:
		promErr = nil // clean up is not for macOS
	default:
		promErr = &PromotionError{Err: fmt.Errorf("unknown image type for operation"), UserErrorDetails: "", NonRetryable: true}
	}

	return promErr
}
