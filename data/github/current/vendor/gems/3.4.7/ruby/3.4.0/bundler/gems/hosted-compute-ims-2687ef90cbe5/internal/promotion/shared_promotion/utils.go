package shared_promotion

import (
	"context"
	"fmt"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store"
)

// SharedUtils methods are shared with all promotion structs: ImagePromotionClient, galleryPromotionProvider, macOSPromotionProvider, etc
type SharedPromotionUtils struct {
	imagesStore store.IImagesStore
}

func NewUtils(imagesStore store.IImagesStore) *SharedPromotionUtils {
	return &SharedPromotionUtils{
		imagesStore: imagesStore,
	}
}

func (c *SharedPromotionUtils) GetImageDefinitionAndVersionByVersionId(ctx context.Context, imageVersionId uint64) (*models.ImageDefinition, *models.ImageVersion, *PromotionError) {
	imageVersion, err := c.imagesStore.GetImageVersionById(ctx, imageVersionId)
	if err != nil {
		return nil, nil, &PromotionError{
			Err:              fmt.Errorf("failed to get image version by id: %w", err),
			UserErrorDetails: "failed to provision image",
			NonRetryable:     true,
		}
	}

	imageDefinition, err := c.imagesStore.GetImageDefinitionById(ctx, imageVersion.ImageDefinitionId)
	if err != nil {
		return nil, nil, &PromotionError{
			Err:              fmt.Errorf("failed to get image definition by id: %w", err),
			UserErrorDetails: "failed to provision image",
			NonRetryable:     true,
		}
	}

	return imageDefinition, imageVersion, nil
}

func (c *SharedPromotionUtils) AssertImageDefinitionState(ctx context.Context, imageDefinitionId uint64, expectedStates ...models.ImageDefinitionState) *PromotionError {
	imageDefinition, err := c.imagesStore.GetImageDefinitionById(ctx, imageDefinitionId)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to get image definition by id: %w", err),
			UserErrorDetails: "Failed to get image definition",
			NonRetryable:     true,
		}
	}

	for _, expectedState := range expectedStates {
		if imageDefinition.State == expectedState {
			return nil
		}
	}

	return &PromotionError{
		Err:              fmt.Errorf("image definition is in invalid state: %s, expected state: %v", imageDefinition.State, expectedStates),
		UserErrorDetails: "Image definition is in invalid state",
		NonRetryable:     true,
	}
}

func (c *SharedPromotionUtils) AssertImageVersionState(ctx context.Context, imageVersionId uint64, expectedStates ...models.ImageVersionState) *PromotionError {
	imageVersion, err := c.imagesStore.GetImageVersionById(ctx, imageVersionId)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to get image version by id: %w", err),
			UserErrorDetails: "Failed to get image version",
			NonRetryable:     true,
		}
	}

	for _, expectedState := range expectedStates {
		if imageVersion.State == expectedState {
			return nil
		}
	}

	return &PromotionError{
		Err:              fmt.Errorf("image version is in invalid state: %s, expected state: %v", imageVersion.State, expectedStates),
		UserErrorDetails: "Image version is in invalid state",
		NonRetryable:     true,
	}
}

func (c *SharedPromotionUtils) UpdateImageVersionState(ctx context.Context, imageVersionId uint64, expectedCurrentState models.ImageVersionState, newState models.ImageVersionState, newStateDetails string) error {
	if err := c.AssertImageVersionState(ctx, imageVersionId, expectedCurrentState); err != nil {
		return err
	}

	if err := c.imagesStore.UpdateImageVersionState(ctx, imageVersionId, newState, newStateDetails); err != nil {
		return fmt.Errorf("failed to update image version state: %w", err)
	}

	return nil
}
