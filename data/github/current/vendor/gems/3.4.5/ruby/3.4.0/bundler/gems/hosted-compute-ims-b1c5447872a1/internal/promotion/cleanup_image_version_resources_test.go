package promotion

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestCleanupImageVersionResources(t *testing.T) {
	var (
		ctx             = context.Background()
		logger          = telemetry.NewReportingLogger(log.NewNullLogger(), nil, nil)
		imageDefinition = &models.ImageDefinition{
			Id:                  1,
			OwnerId:             "github",
			ImageType:           models.ImageType_Curated,
			Name:                "test-image",
			OsType:              models.OsType_Linux,
			AzureSubscriptionId: utils.ToPtr[uint64](1),
		}
		imageVersion = &models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_ProvisionFailed,
			Enabled:           true,
		}
	)

	t.Run("failed to retrieve image version", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).Return(nil, fmt.Errorf("test"))

		err := s.CleanupImageVersionResources(ctx, logger, imageVersion.Id)
		assert.ErrorContains(t, err.Err, "failed to get image version by id")
	})

	t.Run("failed to process image is in invalid state", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		imageVersion := &models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Ready,
			Enabled:           true,
		}
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)

		err := s.CleanupImageVersionResources(ctx, logger, imageVersion.Id)
		assert.ErrorContains(t, err.Err, "image version is in invalid state")
	})

	t.Run("failed to retrieve image definition", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(nil, fmt.Errorf("test"))

		err := s.CleanupImageVersionResources(ctx, logger, imageVersion.Id)
		assert.ErrorContains(t, err.Err, "failed to get image definition by id")
	})

	t.Run("failed if clean up fails", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)

		mockGalleryPromotionProvider.EXPECT().CleanupImageVersionResources(ctx, gomock.Any(), gomock.Any(), gomock.Any()).Times(1).Return(&PromotionError{Err: fmt.Errorf("test")})

		err := s.CleanupImageVersionResources(ctx, logger, imageVersion.Id)
		assert.ErrorContains(t, err, "test")
	})

	t.Run("success and calls gallery provider if image os is linux", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		imageDefinitionLinux := &models.ImageDefinition{
			Id:           1,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
		}

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinitionLinux.Id).AnyTimes().Return(imageDefinitionLinux, nil)

		mockGalleryPromotionProvider.EXPECT().CleanupImageVersionResources(ctx, gomock.Any(), gomock.Any(), gomock.Any()).Times(1).Return(nil)

		err := s.CleanupImageVersionResources(ctx, logger, imageVersion.Id)
		assert.Nil(t, err)
	})

	t.Run("success and calls gallery provider if image os is windows", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		imageDefinitionWindows := &models.ImageDefinition{
			Id:           1,
			OsType:       models.OsType_Windows,
			Architecture: models.Architecture_X64,
		}

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinitionWindows.Id).AnyTimes().Return(imageDefinitionWindows, nil)

		mockGalleryPromotionProvider.EXPECT().CleanupImageVersionResources(ctx, gomock.Any(), gomock.Any(), gomock.Any()).Times(1).Return(nil)

		err := s.CleanupImageVersionResources(ctx, logger, imageVersion.Id)
		assert.Nil(t, err)
	})

	t.Run("success and no calls if image os is macos", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		imageDefinitionMacOS := &models.ImageDefinition{
			Id:           1,
			OsType:       models.OsType_MacOS,
			Architecture: models.Architecture_X64,
		}

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinitionMacOS.Id).AnyTimes().Return(imageDefinitionMacOS, nil)

		err := s.CleanupImageVersionResources(ctx, logger, imageVersion.Id)
		assert.Nil(t, err)
	})
}
