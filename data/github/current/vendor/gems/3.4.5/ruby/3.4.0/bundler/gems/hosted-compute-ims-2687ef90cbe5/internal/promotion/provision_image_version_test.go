package promotion

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestProvisionImageVersion(t *testing.T) {
	var (
		ctx = context.Background()

		imageDefinition = &models.ImageDefinition{
			Id:           1,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
		}
		imageVersion = &models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Provisioning,
			Enabled:           true,
			CreatedAt:         time.Now(),
		}
	)

	t.Run("failed to get image version", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).Return(nil, fmt.Errorf("test"))

		err := p.ProvisionImageVersion(ctx, imageVersion.Id, "test-url", "")
		assert.ErrorContains(t, err.Err, "failed to get image version by id: test")
	})

	t.Run("failed to get image version", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).Return(imageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).Return(nil, fmt.Errorf("test"))

		err := p.ProvisionImageVersion(ctx, imageVersion.Id, "test-url", "")
		assert.ErrorContains(t, err.Err, "failed to get image definition by id: test")
	})

	t.Run("failed when version is in invalid state", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		imageVersionInvalidState := &models.ImageVersion{
			Id:                1,
			ImageDefinitionId: imageDefinition.Id,
			State:             models.ImageVersionState_Deleting,
		}

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).Return(imageVersionInvalidState, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).Return(nil, fmt.Errorf("test"))

		err := p.ProvisionImageVersion(ctx, imageVersionInvalidState.Id, "test-url", "")
		assert.ErrorContains(t, err.Err, "failed to get image definition by id: test")
	})

	t.Run("update image version state to Provisioning if required", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		imageVersionPending := &models.ImageVersion{
			Id:                1,
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Pending,
		}

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), imageVersionPending.Id).AnyTimes().Return(imageVersionPending, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().UpdateImageVersionState(gomock.Any(), imageVersionPending.Id, models.ImageVersionState_Provisioning, ""),
			mockGalleryPromotionProvider.EXPECT().ProvisionImageVersion(gomock.Any(), gomock.Any(), gomock.Any(), gomock.Any()).Times(1).Return(&PromotionError{Err: fmt.Errorf("called")}),
		)

		err := p.ProvisionImageVersion(ctx, imageVersion.Id, "test-url", "")
		assert.ErrorContains(t, err.Err, "called")
	})

	t.Run("failed if promotion fails", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockGalleryPromotionProvider.EXPECT().ProvisionImageVersion(gomock.Any(), gomock.Any(), gomock.Any(), gomock.Any()).Times(1).Return(&PromotionError{Err: fmt.Errorf("called")}),
			mockImagesStore.EXPECT().UpdateImageVersionState(gomock.Any(), imageVersion.Id, models.ImageVersionState_Pending, ""),
		)

		err := p.ProvisionImageVersion(ctx, imageVersion.Id, "test-url", "")
		assert.ErrorContains(t, err.Err, "called")
	})

	t.Run("success and calls gallery provider when image os is linux", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		imageDefinitionLinux := &models.ImageDefinition{
			Id:           1,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
		}

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).AnyTimes().Return(imageDefinitionLinux, nil)
		mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockGalleryPromotionProvider.EXPECT().ProvisionImageVersion(gomock.Any(), gomock.Any(), gomock.Any(), gomock.Any()).Times(1).Return(nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(gomock.Any(), imageVersion.Id, models.ImageVersionState_Ready, ""),
		)

		err := p.ProvisionImageVersion(ctx, imageVersion.Id, "test-url", "")
		assert.Nil(t, err)
	})

	// This tests that if we pull the power after finishing the last operation, but
	// before acknowledging the completion it will succeed on the next run.
	t.Run("idempotency success", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		imageDefinitionLinux := &models.ImageDefinition{
			Id:           1,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
		}

		imageVersionReady := &models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Ready,
			Enabled:           true,
		}

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).AnyTimes().Return(imageDefinitionLinux, nil)
		mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), imageVersionReady.Id).AnyTimes().Return(imageVersionReady, nil)

		// We should not call either of these.
		gomock.InOrder(
			mockGalleryPromotionProvider.EXPECT().ProvisionImageVersion(gomock.Any(), gomock.Any(), gomock.Any(), gomock.Any()).Times(0).Return(nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(gomock.Any(), imageVersionReady.Id, models.ImageVersionState_Ready, "").Times(0),
		)

		err := p.ProvisionImageVersion(ctx, imageVersionReady.Id, "test-url", "")
		assert.Nil(t, err)
	})

	t.Run("success and calls gallery provider when image os is windows", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		imageDefinitionWindows := &models.ImageDefinition{
			Id:           1,
			OsType:       models.OsType_Windows,
			Architecture: models.Architecture_X64,
		}

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).AnyTimes().Return(imageDefinitionWindows, nil)
		mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockGalleryPromotionProvider.EXPECT().ProvisionImageVersion(gomock.Any(), gomock.Any(), gomock.Any(), gomock.Any()).Times(1).Return(nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(gomock.Any(), imageVersion.Id, models.ImageVersionState_Ready, ""),
		)

		err := p.ProvisionImageVersion(ctx, imageVersion.Id, "test-url", "")
		assert.Nil(t, err)
	})

	t.Run("success and calls macos provider when image os is macos", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		imageDefinitionMacOS := &models.ImageDefinition{
			Id:           1,
			OsType:       models.OsType_MacOS,
			Architecture: models.Architecture_X64,
		}

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).AnyTimes().Return(imageDefinitionMacOS, nil)
		mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockMacOSPromotionProvider.EXPECT().ProvisionImageVersion(gomock.Any(), gomock.Any(), gomock.Any(), gomock.Any()).Times(1).Return(nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(gomock.Any(), imageVersion.Id, models.ImageVersionState_Ready, ""),
		)

		err := p.ProvisionImageVersion(ctx, imageVersion.Id, "test-url", "")
		assert.Nil(t, err)
	})
}

func TestProvisionImageVersionFailedAfterMaxRetries(t *testing.T) {
	var (
		ctx                           = context.Background()
		imageVersionId         uint64 = 5
		defaultImageDefinition        = models.ImageDefinition{
			Id:     1,
			OsType: models.OsType_Linux,
		}
		defaultImageVersion = models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
		}
		defaultImageVersionReady = models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Ready,
			Enabled:           true,
		}
	)

	t.Run("failed to retrieve image version", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersionId).Return(nil, fmt.Errorf("test"))

		promotionErr := PromotionError{
			Err:              fmt.Errorf("none"),
			UserErrorDetails: "none",
		}

		err := s.ProvisionImageVersionFailedAfterMaxRetries(ctx, imageVersionId, &promotionErr)
		assert.ErrorContains(t, err, "failed to get image version")
	})

	t.Run("image version is in unexpected state", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersionId).Return(&defaultImageVersionReady, nil)

		promotionErr := PromotionError{
			Err:              fmt.Errorf("none"),
			UserErrorDetails: "none",
		}

		err := s.ProvisionImageVersionFailedAfterMaxRetries(ctx, imageVersionId, &promotionErr)
		assert.ErrorContains(t, err, "image version is in invalid state")
	})

	t.Run("failed to update image version state", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersionId).Return(&defaultImageVersion, nil)
		mockImagesStore.EXPECT().UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_ProvisionFailed, gomock.Any()).Return(fmt.Errorf("test"))

		promotionErr := PromotionError{
			Err:              fmt.Errorf("none"),
			UserErrorDetails: "none",
		}

		err := s.ProvisionImageVersionFailedAfterMaxRetries(ctx, imageVersionId, &promotionErr)
		assert.ErrorContains(t, err, "failed to update image version state")
	})

	t.Run("failed to queue resources clean up job", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersionId).AnyTimes().Return(&defaultImageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, defaultImageDefinition.Id).Return(&defaultImageDefinition, nil)
		mockImagesStore.EXPECT().UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_ProvisionFailed, gomock.Any()).Return(nil)
		mockWorkerQueueClient.EXPECT().QueueProvisionCleanupJob(ctx, imageVersionId).Return(fmt.Errorf("test"))

		promotionErr := PromotionError{
			Err:              fmt.Errorf("none"),
			UserErrorDetails: "none",
		}

		err := s.ProvisionImageVersionFailedAfterMaxRetries(ctx, imageVersionId, &promotionErr)
		assert.ErrorContains(t, err, "failed to queue provision clean up job")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersionId).AnyTimes().Return(&defaultImageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, defaultImageDefinition.Id).Return(&defaultImageDefinition, nil)
		mockImagesStore.EXPECT().UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_ProvisionFailed, gomock.Any()).Return(nil)
		mockWorkerQueueClient.EXPECT().QueueProvisionCleanupJob(ctx, imageVersionId).Return(nil)

		promotionErr := PromotionError{
			Err:              fmt.Errorf("none"),
			UserErrorDetails: "none",
		}

		err := s.ProvisionImageVersionFailedAfterMaxRetries(ctx, imageVersionId, &promotionErr)
		assert.NoError(t, err)
	})
}
