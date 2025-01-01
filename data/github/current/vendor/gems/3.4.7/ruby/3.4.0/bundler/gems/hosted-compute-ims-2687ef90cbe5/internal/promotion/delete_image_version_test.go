package promotion

import (
	"context"
	"database/sql"
	"fmt"
	"testing"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestDeleteImageVersion(t *testing.T) {
	var (
		ctx             = context.Background()
		imageDefinition = &models.ImageDefinition{
			Id:        1,
			OwnerId:   "github",
			ImageType: models.ImageType_Curated,
			Name:      "test-image",
			OsType:    models.OsType_Linux,
		}
		imageVersion = &models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Deleting,
			Enabled:           true,
		}
	)

	t.Run("success when image version doesn't exist", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).Return(nil, sql.ErrNoRows)

		err := s.DeleteImageVersion(ctx, imageVersion.Id)
		assert.Nil(t, err, "DeleteImageVersion should succeed when the image version doesn't exist")
	})

	t.Run("failed to retrieve image version with other error", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).Return(nil, fmt.Errorf("test"))

		err := s.DeleteImageVersion(ctx, imageVersion.Id)
		assert.ErrorContains(t, err.Err, "failed to get image version by id")
	})

	t.Run("failed to process image is in invalid state", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		imageVersion := models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_ProvisionFailed,
			Enabled:           true,
		}
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(&imageVersion, nil)

		err := s.DeleteImageVersion(ctx, imageVersion.Id)
		assert.ErrorContains(t, err.Err, "image version is in invalid state")
	})

	t.Run("failed to clean up resources", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)

		mockGalleryPromotionProvider.EXPECT().CleanupImageVersionResources(ctx, gomock.Any(), gomock.Any()).Times(1).Return(&PromotionError{Err: fmt.Errorf("test")})

		err := s.DeleteImageVersion(ctx, imageVersion.Id)
		assert.ErrorContains(t, err.Err, "test")
	})

	t.Run("failed to delete image version from db", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)

		mockGalleryPromotionProvider.EXPECT().CleanupImageVersionResources(ctx, gomock.Any(), gomock.Any()).Times(1).Return(nil)
		mockImagesStore.EXPECT().DeleteImageVersionById(ctx, imageVersion.Id).Return(fmt.Errorf("test"))

		err := s.DeleteImageVersion(ctx, imageVersion.Id)
		assert.ErrorContains(t, err.Err, "test")
	})

	t.Run("success and no calls if image os is macos", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)

		mockGalleryPromotionProvider.EXPECT().CleanupImageVersionResources(ctx, gomock.Any(), gomock.Any()).Times(1).Return(nil)
		mockImagesStore.EXPECT().DeleteImageVersionById(ctx, imageVersion.Id).Return(nil)

		err := s.DeleteImageVersion(ctx, imageVersion.Id)
		assert.Nil(t, err)
	})
}
