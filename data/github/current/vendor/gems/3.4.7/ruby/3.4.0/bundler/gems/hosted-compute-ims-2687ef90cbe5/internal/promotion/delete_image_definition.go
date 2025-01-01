package promotion

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/github/hosted-compute-ims/internal/models"
)

func (c *ImagePromotionClient) DeleteImageDefinitionWithAllVersions(ctx context.Context, imageDefinitionId uint64) *PromotionError {
	// Check if the image definition exists before proceeding
	_, err := c.imagesStore.GetImageDefinitionById(ctx, imageDefinitionId)
	if err != nil {
		// If the image definition doesn't exist, consider it already deleted and return success
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		return &PromotionError{
			Err:          fmt.Errorf("failed to get image definition by id: %w", err),
			NonRetryable: true,
		}
	}

	if err := c.utils.AssertImageDefinitionState(ctx, imageDefinitionId, models.ImageDefinitionState_Deleting); err != nil {
		return err
	}

	imageVersions, err := c.imagesStore.ListImageVersionsByDefinitionId(ctx, imageDefinitionId)
	if err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to list image versions by definition id: %w", err),
			NonRetryable: false,
		}
	}

	for _, imageVersion := range imageVersions {
		if err = c.imagesStore.UpdateImageVersionState(ctx, imageVersion.Id, models.ImageVersionState_Deleting, ""); err != nil {
			return &PromotionError{
				Err:          fmt.Errorf("failed to set image version to deleting: %w", err),
				NonRetryable: false,
			}
		}

		if err := c.DeleteImageVersion(ctx, imageVersion.Id); err != nil {
			return err
		}
	}

	if err := c.utils.AssertImageDefinitionState(ctx, imageDefinitionId, models.ImageDefinitionState_Deleting); err != nil {
		return err
	}

	if err := c.imagesStore.DeleteImageDefinition(ctx, imageDefinitionId); err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to delete image definition from database: %w", err),
			NonRetryable: false,
		}
	}

	return nil
}
