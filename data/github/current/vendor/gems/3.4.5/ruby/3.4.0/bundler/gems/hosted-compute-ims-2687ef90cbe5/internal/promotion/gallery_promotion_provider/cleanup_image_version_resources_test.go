package gallery_promotion_provider

import (
	"context"
	"fmt"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestCleanupImageVersionResources(t *testing.T) {
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
			Id:                  1,
			Version:             "1.0.0",
			ImageDefinitionId:   1,
			State:               models.ImageVersionState_ProvisionFailed,
			Enabled:             true,
			AzureSubscriptionId: utils.ToPtr[uint64](1),
			VmGeneration:        models.VmGeneration_Gen1,
		}
		azureSubscription = &models.AzureSubscription{
			Id:             1,
			SubscriptionId: "test-subscription",
		}
		storageBlobKey  = azure.NewStorageBlobKey("test-subscription", "hostedcomputeims--rg", "ims", "vhds", "image-1-1.0.0.vhd")
		azureGalleryKey = azure.NewGalleryImageVersionKey("test-subscription", "hostedcomputeims--rg", "imsgallery.", "image-1-gen1", "1.0.0")
	)

	t.Run("success if azure subscription is not assigned to image definition", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		imageVersionWithoutSubscriptionAssigned := &models.ImageVersion{
			Id:                  imageVersion.Id,
			AzureSubscriptionId: nil,
		}

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersionWithoutSubscriptionAssigned, nil)

		err := p.CleanupImageVersionResources(ctx, imageDefinition, imageVersionWithoutSubscriptionAssigned)
		assert.Nil(t, err)
	})

	t.Run("failed to get image version gallery key", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(nil, fmt.Errorf("test"))

		err := p.CleanupImageVersionResources(ctx, imageDefinition, imageVersion)
		assert.ErrorContains(t, err.Err, "failed to get gallery image version key")
	})

	t.Run("failed to delete image version from azure", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().DeleteImageVersion(ctx, azureGalleryKey).Return(fmt.Errorf("test")),
		)

		err := p.CleanupImageVersionResources(ctx, imageDefinition, imageVersion)
		assert.ErrorContains(t, err.Err, "failed to delete image version from azure")
	})

	t.Run("failed to delete blob", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().DeleteImageVersion(ctx, azureGalleryKey).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().DeleteBlob(ctx, storageBlobKey).Return(fmt.Errorf("test")),
		)

		err := p.CleanupImageVersionResources(ctx, imageDefinition, imageVersion)
		assert.ErrorContains(t, err.Err, "failed to delete blob after image version deletion")
	})

	t.Run("failed to delete image version parent resources from azure", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().DeleteImageVersion(ctx, azureGalleryKey).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().DeleteBlob(ctx, storageBlobKey).Return(nil),
			mockAzureClient.EXPECT().CheckGalleryImageDefinitionExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(true, nil),
			mockAzureClient.EXPECT().ListImageVersions(ctx, &azureGalleryKey.GalleryImageDefinitionKey, 1).Return(nil, fmt.Errorf("test")),
		)

		err := p.CleanupImageVersionResources(ctx, imageDefinition, imageVersion)
		assert.ErrorContains(t, err.Err, "failed to list image versions for compute gallery image definition")
	})

	t.Run("failed to unassign azure subscription", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().DeleteImageVersion(ctx, azureGalleryKey).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().DeleteBlob(ctx, storageBlobKey).Return(nil),
			mockAzureClient.EXPECT().CheckGalleryImageDefinitionExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(false, nil),
			mockImagesStore.EXPECT().UnassignAzureSubscriptionFromImageVersion(ctx, imageVersion.Id).Return(fmt.Errorf("test")),
		)

		err := p.CleanupImageVersionResources(ctx, imageDefinition, imageVersion)
		assert.ErrorContains(t, err, "failed to unassign azure subscription from image version: test")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().DeleteImageVersion(ctx, azureGalleryKey).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().DeleteBlob(ctx, storageBlobKey).Return(nil),
			mockAzureClient.EXPECT().CheckGalleryImageDefinitionExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(false, nil),
			mockImagesStore.EXPECT().UnassignAzureSubscriptionFromImageVersion(ctx, imageVersion.Id).Return(nil),
		)

		err := p.CleanupImageVersionResources(ctx, imageDefinition, imageVersion)
		assert.Nil(t, err)
	})
}

func TestDeleteImageVersionParentResourcesFromAzureIfPossible(t *testing.T) {
	var (
		ctx          = context.Background()
		imageVersion = &models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_ProvisionFailed,
			Enabled:           true,
		}

		azureGalleryKey = azure.NewGalleryImageVersionKey("test-subscription", "rg", "gallery", "image", "version")
	)

	t.Run("failed to check gallery image definition existence", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockAzureClient.EXPECT().CheckGalleryImageDefinitionExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(false, fmt.Errorf("test"))

		err := s.deleteImageVersionParentResourcesFromAzureIfPossible(ctx, imageVersion, azureGalleryKey)
		assert.ErrorContains(t, err.Err, "failed to check gallery image definition existence")
	})

	t.Run("success if gallery image definition doesn't exist", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockAzureClient.EXPECT().CheckGalleryImageDefinitionExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(false, nil)

		err := s.deleteImageVersionParentResourcesFromAzureIfPossible(ctx, imageVersion, azureGalleryKey)
		assert.Nil(t, err)
	})

	t.Run("failed to list gallery image versions", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockAzureClient.EXPECT().CheckGalleryImageDefinitionExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(true, nil),
			mockAzureClient.EXPECT().ListImageVersions(ctx, &azureGalleryKey.GalleryImageDefinitionKey, 1).Return(nil, fmt.Errorf("test")),
		)

		err := s.deleteImageVersionParentResourcesFromAzureIfPossible(ctx, imageVersion, azureGalleryKey)
		assert.ErrorContains(t, err.Err, "failed to list image versions for compute gallery image definition")
	})

	t.Run("success if gallery image definition has some versions", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockAzureClient.EXPECT().CheckGalleryImageDefinitionExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(true, nil),
			mockAzureClient.EXPECT().ListImageVersions(ctx, &azureGalleryKey.GalleryImageDefinitionKey, 1).Return([]*armcompute.GalleryImageVersion{{}}, nil),
		)

		err := s.deleteImageVersionParentResourcesFromAzureIfPossible(ctx, imageVersion, azureGalleryKey)
		assert.Nil(t, err)
	})

	t.Run("failed to delete gallery image definition", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockAzureClient.EXPECT().CheckGalleryImageDefinitionExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(true, nil),
			mockAzureClient.EXPECT().ListImageVersions(ctx, &azureGalleryKey.GalleryImageDefinitionKey, 1).Return([]*armcompute.GalleryImageVersion{}, nil),
			mockAzureClient.EXPECT().DeleteImageDefinition(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(fmt.Errorf("test")),
		)

		err := s.deleteImageVersionParentResourcesFromAzureIfPossible(ctx, imageVersion, azureGalleryKey)
		assert.ErrorContains(t, err.Err, "failed to delete image definition")
	})

	t.Run("success if azure subscription is not assigned to image definition", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockAzureClient.EXPECT().CheckGalleryImageDefinitionExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(true, nil),
			mockAzureClient.EXPECT().ListImageVersions(ctx, &azureGalleryKey.GalleryImageDefinitionKey, 1).Return([]*armcompute.GalleryImageVersion{}, nil),
			mockAzureClient.EXPECT().DeleteImageDefinition(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(nil),
		)

		err := s.deleteImageVersionParentResourcesFromAzureIfPossible(ctx, imageVersion, azureGalleryKey)
		assert.Nil(t, err)
	})

	t.Run("success", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockAzureClient.EXPECT().CheckGalleryImageDefinitionExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(true, nil),
			mockAzureClient.EXPECT().ListImageVersions(ctx, &azureGalleryKey.GalleryImageDefinitionKey, 1).Return([]*armcompute.GalleryImageVersion{}, nil),
			mockAzureClient.EXPECT().DeleteImageDefinition(ctx, &azureGalleryKey.GalleryImageDefinitionKey).Return(nil),
		)

		err := s.deleteImageVersionParentResourcesFromAzureIfPossible(ctx, imageVersion, azureGalleryKey)
		assert.Nil(t, err)
	})
}
