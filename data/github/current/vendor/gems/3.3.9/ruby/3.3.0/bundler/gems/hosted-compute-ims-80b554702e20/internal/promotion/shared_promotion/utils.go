package shared_promotion

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store"
	"go.uber.org/zap/zapcore"
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

func (c *SharedPromotionUtils) GetStatterTagsForImageDefinition(imageDefinition *models.ImageDefinition) stats.Tags {
	return stats.Tags{
		"image_type":         string(imageDefinition.ImageType),
		"image_architecture": string(imageDefinition.Architecture),
		"image_os":           string(imageDefinition.OsType),
	}
}

func (c *SharedPromotionUtils) GetLoggerFieldsForImageDefinition(imageDefinition *models.ImageDefinition) []zapcore.Field {
	return []zapcore.Field{
		kvp.Uint64("image_definition_id", imageDefinition.Id),
		kvp.String("image_type", string(imageDefinition.ImageType)),
		kvp.String("image_architecture", string(imageDefinition.Architecture)),
		kvp.String("image_os", string(imageDefinition.OsType)),
	}
}
