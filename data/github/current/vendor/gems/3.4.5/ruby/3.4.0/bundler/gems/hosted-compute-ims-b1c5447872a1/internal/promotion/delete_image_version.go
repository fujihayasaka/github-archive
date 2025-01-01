package promotion

import (
	"context"
	"fmt"

	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
)

func (c *ImagePromotionClient) DeleteImageVersion(ctx context.Context, logger *telemetry.ReportingLogger, imageVersionId uint64) *PromotionError {
	if err := c.utils.AssertImageVersionState(ctx, imageVersionId, models.ImageVersionState_Deleting); err != nil {
		return &PromotionError{
			Err:          err.Err,
			NonRetryable: true,
		}
	}

	if err := c.CleanupImageVersionResources(ctx, logger, imageVersionId); err != nil {
		return err
	}

	if err := c.utils.AssertImageVersionState(ctx, imageVersionId, models.ImageVersionState_Deleting); err != nil {
		return &PromotionError{
			Err:          err.Err,
			NonRetryable: true,
		}
	}

	if err := c.imagesStore.DeleteImageVersionById(ctx, imageVersionId); err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to delete image version from database: %w", err),
			NonRetryable: false,
		}
	}

	return nil
}
