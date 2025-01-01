package promotion

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/github/hosted-compute-ims/internal/models"
)

func (c *ImagePromotionClient) DeleteImageVersion(ctx context.Context, imageVersionId uint64) *PromotionError {
	// Check if the image version exists before proceeding
	_, err := c.imagesStore.GetImageVersionById(ctx, imageVersionId)
	if err != nil {
		// If the image version doesn't exist, consider it already deleted and return success
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		return &PromotionError{
			Err:          fmt.Errorf("failed to get image version by id: %w", err),
			NonRetryable: true,
		}
	}

	if err := c.utils.AssertImageVersionState(ctx, imageVersionId, models.ImageVersionState_Deleting); err != nil {
		return &PromotionError{
			Err:          err.Err,
			NonRetryable: true,
		}
	}

	if err := c.CleanupImageVersionResources(ctx, imageVersionId); err != nil {
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
