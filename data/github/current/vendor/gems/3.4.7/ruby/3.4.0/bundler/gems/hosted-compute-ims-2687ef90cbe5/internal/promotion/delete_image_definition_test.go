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

func TestDeleteImageDefinition(t *testing.T) {
	var (
		ctx             = context.Background()
		imageDefinition = &models.ImageDefinition{
			Id:        1,
			OwnerId:   "github",
			ImageType: models.ImageType_Curated,
			Name:      "test-image",
			OsType:    models.OsType_Linux,
			State:     models.ImageDefinitionState_Deleting,
		}
		imageVersion = &models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Deleting,
			Enabled:           true,
		}
	)

	t.Run("success when image definition doesn't exist", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageVersion.Id).Return(nil, sql.ErrNoRows)

		err := s.DeleteImageDefinitionWithAllVersions(ctx, imageVersion.Id)
		assert.Nil(t, err, "DeleteImageDefinitionWithAllVersions should succeed when the image definition doesn't exist")
	})

	t.Run("failed to retrieve image definition with other error", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageVersion.Id).Times(1).Return(nil, fmt.Errorf("test"))

		err := s.DeleteImageDefinitionWithAllVersions(ctx, imageVersion.Id)
		assert.ErrorContains(t, err.Err, "failed to get image definition by id")
	})

	t.Run("failed to process image is in invalid state", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		imageDefinition := models.ImageDefinition{
			Id:      1,
			State:   models.ImageDefinitionState_Ready,
			Enabled: true,
		}
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(&imageDefinition, nil)

		err := s.DeleteImageDefinitionWithAllVersions(ctx, imageDefinition.Id)
		assert.ErrorContains(t, err.Err, "image definition is in invalid state")
	})

	t.Run("failed to delete image version", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageVersion.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, imageDefinition.Id).Times(1).Return([]*models.ImageVersion{imageVersion}, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)
		mockImagesStore.EXPECT().UpdateImageVersionState(ctx, imageVersion.Id, models.ImageVersionState_Deleting, "").Times(1).Return(nil)

		mockGalleryPromotionProvider.EXPECT().CleanupImageVersionResources(ctx, gomock.Any(), gomock.Any()).Times(1).Return(&PromotionError{Err: fmt.Errorf("test")})

		err := s.DeleteImageDefinitionWithAllVersions(ctx, imageVersion.Id)
		assert.ErrorContains(t, err.Err, "test")
	})

	t.Run("failed to delete image definition from db", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageVersion.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, imageDefinition.Id).Times(1).Return([]*models.ImageVersion{imageVersion}, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)
		mockImagesStore.EXPECT().UpdateImageVersionState(ctx, imageVersion.Id, models.ImageVersionState_Deleting, "").Times(1).Return(nil)
		mockGalleryPromotionProvider.EXPECT().CleanupImageVersionResources(ctx, gomock.Any(), gomock.Any()).Times(1).Return(nil)
		mockImagesStore.EXPECT().DeleteImageVersionById(ctx, imageVersion.Id).Times(1).Return(nil)

		mockImagesStore.EXPECT().DeleteImageDefinition(ctx, imageVersion.Id).Times(1).Return(fmt.Errorf("test"))

		err := s.DeleteImageDefinitionWithAllVersions(ctx, imageVersion.Id)
		assert.ErrorContains(t, err.Err, "test")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageVersion.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, imageDefinition.Id).Times(1).Return([]*models.ImageVersion{imageVersion}, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)
		mockImagesStore.EXPECT().UpdateImageVersionState(ctx, imageVersion.Id, models.ImageVersionState_Deleting, "").Times(1).Return(nil)
		mockGalleryPromotionProvider.EXPECT().CleanupImageVersionResources(ctx, gomock.Any(), gomock.Any()).Times(1).Return(nil)
		mockImagesStore.EXPECT().DeleteImageVersionById(ctx, imageVersion.Id).Times(1).Return(nil)
		mockImagesStore.EXPECT().DeleteImageDefinition(ctx, imageVersion.Id).Times(1).Return(nil)

		err := s.DeleteImageDefinitionWithAllVersions(ctx, imageVersion.Id)
		assert.Nil(t, err)
	})
}
