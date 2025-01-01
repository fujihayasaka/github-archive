package promotion

import (
	"context"
	"fmt"

	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
)

func (c *ImagePromotionClient) CleanupImageVersionResources(ctx context.Context, logger *telemetry.ReportingLogger, imageVersionId uint64) *PromotionError {
	imageVersion, err := c.imagesStore.GetImageVersionById(ctx, imageVersionId)
	if err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to get image version by id: %w", err),
			NonRetryable: true,
		}
	}

	if err := c.utils.AssertImageVersionState(ctx, imageVersionId, models.ImageVersionState_Deleting, models.ImageVersionState_ProvisionFailed); err != nil {
		return err
	}

	imageDefinition, err := c.imagesStore.GetImageDefinitionById(ctx, imageVersion.ImageDefinitionId)
	if err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to get image definition by id: %w", err),
			NonRetryable: true,
		}
	}

	var promErr *PromotionError
	switch {
	case imageDefinition.OsType == models.OsType_Linux || imageDefinition.OsType == models.OsType_Windows:
		promErr = c.galleryProvider.CleanupImageVersionResources(ctx, logger, imageDefinition, imageVersion)
	case imageDefinition.OsType == models.OsType_MacOS:
		promErr = nil // clean up is not for macOS
	default:
		promErr = &PromotionError{Err: fmt.Errorf("unknown image type for operation"), UserErrorDetails: "", NonRetryable: true}
	}

	return promErr
}
