package shared_promotion

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/hosted-compute-ims/gen/mocks/mocks_store"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

var mockImagesStore *mocks_store.MockIImagesStore

func setup(t *testing.T) (*gomock.Controller, *SharedPromotionUtils) {
	ctrl := gomock.NewController(t)

	featureflags.TEST_SetupFeatureFlagsClient(t)

	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)

	return ctrl, &SharedPromotionUtils{
		imagesStore: mockImagesStore,
	}
}

func TestAssertImageVersionState(t *testing.T) {
	var (
		ctx                        = context.Background()
		imageVersionId      uint64 = 5
		defaultImageVersion        = models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
		}
	)

	t.Run("failed to retrieve image version", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersionId).Return(nil, fmt.Errorf("test"))

		err := s.AssertImageVersionState(ctx, imageVersionId, models.ImageVersionState_Pending)
		assert.ErrorContains(t, err, "failed to get image version")
	})

	t.Run("unexpected state", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersionId).Return(&defaultImageVersion, nil).AnyTimes()

		err := s.AssertImageVersionState(ctx, imageVersionId, models.ImageVersionState_Ready)
		assert.ErrorContains(t, err, "image version is in invalid state: Pending, expected state: [Ready]")

		err = s.AssertImageVersionState(ctx, imageVersionId, models.ImageVersionState_Deleting, models.ImageVersionState_ProvisionFailed)
		assert.ErrorContains(t, err, "image version is in invalid state: Pending, expected state: [Deleting ProvisionFailed]")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersionId).Return(&defaultImageVersion, nil).AnyTimes()

		err := s.AssertImageVersionState(ctx, imageVersionId, models.ImageVersionState_Pending)
		assert.Nil(t, err)

		err = s.AssertImageVersionState(ctx, imageVersionId, models.ImageVersionState_ProvisionFailed, models.ImageVersionState_Pending)
		assert.Nil(t, err)
	})
}

func TestUpdateImageVersionState(t *testing.T) {
	var (
		ctx                        = context.Background()
		imageVersionId      uint64 = 5
		defaultImageVersion        = models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
		}
	)

	t.Run("unexpected state", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersionId).Return(&defaultImageVersion, nil)

		err := s.UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Ready, models.ImageVersionState_Deleting, "")
		assert.ErrorContains(t, err, "image version is in invalid state: Pending, expected state: [Ready]")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersionId).Return(&defaultImageVersion, nil)
		mockImagesStore.EXPECT().UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Deleting, "")

		err := s.UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Pending, models.ImageVersionState_Deleting, "")
		assert.NoError(t, err)
	})
}

func TestGetImageDefinitionAndVersionByVersionId(t *testing.T) {
	var (
		ctx          = context.Background()
		imageVersion = &models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 2,
		}
		imageDefinition = &models.ImageDefinition{
			Id: 2,
		}
	)

	t.Run("failed to get image version by id", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).Return(nil, fmt.Errorf("test"))

		def, ver, err := s.GetImageDefinitionAndVersionByVersionId(ctx, imageVersion.Id)
		assert.ErrorContains(t, err, "failed to get image version by id: test")
		assert.Nil(t, def)
		assert.Nil(t, ver)
	})

	t.Run("failed to get image definition by id", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).Return(imageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).Return(nil, fmt.Errorf("test"))

		def, ver, err := s.GetImageDefinitionAndVersionByVersionId(ctx, imageVersion.Id)
		assert.ErrorContains(t, err, "failed to get image definition by id: test")
		assert.Nil(t, def)
		assert.Nil(t, ver)
	})

	t.Run("success", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).Return(imageVersion, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).Return(imageDefinition, nil)

		def, ver, err := s.GetImageDefinitionAndVersionByVersionId(ctx, imageVersion.Id)
		assert.Nil(t, err)
		assert.Equal(t, uint64(2), def.Id)
		assert.Equal(t, uint64(1), ver.Id)
	})
}
