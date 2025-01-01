package resources

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestManager_SharedDevImages(t *testing.T) {
	ctx := context.Background()

	id := uint64(1)
	azureSubscription := &models.AzureSubscription{SubscriptionId: utils.SharedDevImagesSubscriptionId}

	imageDefinition := &models.ImageDefinition{
		Id:                  1,
		AzureSubscriptionId: &id,
	}

	imageVersion := &models.ImageVersion{
		Id:                1,
		ImageDefinitionId: 1,
		Version:           "0.0.1",
	}

	t.Run("GetImageBlobKey", func(t *testing.T) {
		ctrl, manager := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageVersion.ImageDefinitionId).Return(imageDefinition, nil).Times(1),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(gomock.Any(), *imageDefinition.AzureSubscriptionId).Return(azureSubscription, nil).Times(1),
		)
		azureBlobKey, err := manager.GetImageBlobKey(ctx, imageVersion)
		require.Error(t, err, utils.SharedDevImagesErrorMessage)
		require.Nil(t, azureBlobKey)
	})

	t.Run("GetGalleryImageVersionKey - known image", func(t *testing.T) {
		ctrl, manager := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageVersion.ImageDefinitionId).Return(imageDefinition, nil).Times(1),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(gomock.Any(), *imageDefinition.AzureSubscriptionId).Return(azureSubscription, nil).Times(1),
		)
		galleryImageVersionKey, err := manager.GetGalleryImageVersionKey(ctx, imageVersion)
		require.NoError(t, err, "error should be nil")
		require.NotNil(t, galleryImageVersionKey)
		require.NotEmpty(t, galleryImageVersionKey.SubscriptionId)
		require.NotEmpty(t, galleryImageVersionKey.ResourceGroup)
		require.NotEmpty(t, galleryImageVersionKey.GalleryName)
		require.NotEmpty(t, galleryImageVersionKey.ImageDefinitionName)
		require.NotEmpty(t, galleryImageVersionKey.Version)
		require.Equal(t, galleryImageVersionKey.ImageDefinitionName, "Ubuntu20")
	})

	t.Run("GetGalleryImageVersionKey - unknown image", func(t *testing.T) {
		ctrl, manager := setup(t)
		defer ctrl.Finish()

		imageDefinition := &models.ImageDefinition{
			Id:                  150000,
			AzureSubscriptionId: &id,
		}

		imageVersion := &models.ImageVersion{
			Id:                1,
			ImageDefinitionId: 150000,
			Version:           "0.0.1",
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageVersion.ImageDefinitionId).Return(imageDefinition, nil).Times(1),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(gomock.Any(), *imageDefinition.AzureSubscriptionId).Return(azureSubscription, nil).Times(1),
		)
		galleryImageVersionKey, err := manager.GetGalleryImageVersionKey(ctx, imageVersion)
		require.ErrorContains(t, err, "failed to find curated shared image")
		require.Nil(t, galleryImageVersionKey)
	})

	t.Run("GetImageReference", func(t *testing.T) {
		ctrl, manager := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageVersion.ImageDefinitionId).Times(1).Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, *imageDefinition.AzureSubscriptionId).Times(1).Return(azureSubscription, nil)

		ref, err := manager.GetImageReference(ctx, imageVersion)

		require.NoError(t, err)
		require.NotNil(t, ref)
		require.NotNil(t, ref.ID)
		require.Contains(t, *ref.ID, fmt.Sprintf("/subscriptions/%s/resourceGroups", utils.SharedDevImagesSubscriptionId))
	})
}
