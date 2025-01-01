package gallery_promotion_provider

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_EnsureAzureSubscriptionAssignedToImageVersion(t *testing.T) {
	var (
		ctx                        = context.Background()
		imageVersionNoSubscription = &models.ImageVersion{
			Id:                  1,
			AzureSubscriptionId: nil,
		}
		imageVersionWithSubscription = &models.ImageVersion{
			Id:                  1,
			AzureSubscriptionId: utils.ToPtr[uint64](1),
		}
	)

	t.Run("subscription is assigned successfully", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().AssignAzureSubscriptionToImageVersion(ctx, imageVersionNoSubscription.Id).Return(imageVersionWithSubscription, nil).Times(1)

		imageVersion, err := p.ensureAzureSubscriptionAssignedToImageVersion(ctx, imageVersionNoSubscription)
		require.NoError(t, err)
		require.NotNil(t, imageVersion)
		require.NotNil(t, imageVersion.AzureSubscriptionId)
	})

	t.Run("subscription is assigned successfully but no id", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().AssignAzureSubscriptionToImageVersion(ctx, imageVersionNoSubscription.Id).Return(imageVersionNoSubscription, nil).Times(1)

		_, err := p.ensureAzureSubscriptionAssignedToImageVersion(ctx, imageVersionNoSubscription)
		require.ErrorContains(t, err, "azure subscription was assigned to image version but azure subscription id is not passed to image version")
	})

	t.Run("failed to assign subscription", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().AssignAzureSubscriptionToImageVersion(ctx, imageVersionNoSubscription.Id).Return(nil, fmt.Errorf("test"))

		_, err := p.ensureAzureSubscriptionAssignedToImageVersion(ctx, imageVersionNoSubscription)
		require.ErrorContains(t, err, "failed to assign azure subscription to image version: test")
	})

	t.Run("image version is already assigned to azure subscription", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		imageVersion, err := p.ensureAzureSubscriptionAssignedToImageVersion(ctx, imageVersionWithSubscription)
		require.NoError(t, err)
		require.NotNil(t, imageVersion)
		require.NotNil(t, imageVersion.AzureSubscriptionId)
	})
}

func Test_GetImageBlobKey(t *testing.T) {
	var (
		ctx               = context.Background()
		id                = uint64(1)
		azureSubscription = &models.AzureSubscription{
			Id:              id,
			SubscriptionId:  "test-subscription",
			ResourcesPrefix: "000000000000",
		}
		imageVersionWithSubscription = &models.ImageVersion{
			Id:                  1,
			ImageDefinitionId:   1,
			Version:             "0.0.1",
			AzureSubscriptionId: utils.ToPtr[uint64](2),
		}
		imageVersionNoSubscription = &models.ImageVersion{
			Id:                1,
			ImageDefinitionId: 1,
			Version:           "0.0.1",
		}
	)

	t.Run("should build blob key when image version has azure subscription assigned", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, *imageVersionWithSubscription.AzureSubscriptionId).Return(azureSubscription, nil).Times(1)

		azureBlobKey, err := p.getImageBlobKey(ctx, imageVersionWithSubscription)
		assert.NoError(t, err, "error should be nil")

		assert.Equal(t, azureBlobKey, &azure.StorageBlobKey{
			StorageContainerKey: azure.StorageContainerKey{
				StorageKey: azure.StorageKey{
					ResourceGroupKey: azure.ResourceGroupKey{
						SubscriptionId: "test-subscription",
						ResourceGroup:  "hostedcomputeims-000000000000-rg",
					},
					StorageAccount: "ims000000000000",
				},
				Container: "vhds",
			},
			Blob: "image-1-0.0.1.vhd",
		}, "azure blob key should be equal")
	})

	t.Run("should return error if image version has no azure subscription id", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		azureBlobKey, err := p.getImageBlobKey(ctx, imageVersionNoSubscription)
		assert.ErrorContains(t, err, "azure subscription is not assigned to image version")
		assert.Nil(t, azureBlobKey, "azure blob key should be nil")
	})
}

func Test_GetGalleryImageVersionKey(t *testing.T) {
	var (
		ctx               = context.Background()
		id                = uint64(1)
		azureSubscription = &models.AzureSubscription{
			Id:              id,
			SubscriptionId:  "test-subscription",
			ResourcesPrefix: "00000000000000",
		}
		imageVersionWithSubscription = &models.ImageVersion{
			Id:                  1,
			ImageDefinitionId:   1,
			Version:             "0.0.1",
			AzureSubscriptionId: utils.ToPtr[uint64](2),
			VmGeneration:        models.VmGeneration_Gen1,
		}
		imageVersionNoSubscription = &models.ImageVersion{
			Id:                1,
			ImageDefinitionId: 1,
			Version:           "0.0.1",
		}
	)

	t.Run("should build gallery image version key when image version has azure subscription assigned", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, *imageVersionWithSubscription.AzureSubscriptionId).Return(azureSubscription, nil).Times(1)

		galleryImageVersionKey, err := p.getGalleryImageVersionKey(ctx, imageVersionWithSubscription)
		assert.NoError(t, err, "error should be nil")

		assert.Equal(t, galleryImageVersionKey, &azure.GalleryImageVersionKey{
			GalleryImageDefinitionKey: azure.GalleryImageDefinitionKey{
				GalleryKey: azure.GalleryKey{
					ResourceGroupKey: azure.ResourceGroupKey{
						SubscriptionId: "test-subscription",
						ResourceGroup:  "hostedcomputeims-00000000000000-rg",
					},
					GalleryName: "imsgallery.00000000000000",
				},
				ImageDefinitionName: "image-1-gen1",
			},
			Version: "0.0.1",
		}, "gallery image version key should be equal")
	})

	t.Run("should return error if image version has no azure subscription id", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		galleryImageVersionKey, err := p.getGalleryImageVersionKey(ctx, imageVersionNoSubscription)
		assert.ErrorContains(t, err, "azure subscription is not assigned to image version")
		assert.Nil(t, galleryImageVersionKey, "gallery image version key should be nil")
	})
}

func Test_GetImageVersionResourceId(t *testing.T) {
	subscriptionId := uint64(1)
	ctrl, p := setup(t)
	defer ctrl.Finish()

	var (
		ctx               = context.Background()
		azureSubscription = &models.AzureSubscription{
			Id:             subscriptionId,
			SubscriptionId: "test-subscription",
		}
		curatedImageVersion = &models.ImageVersion{
			Id:                  2,
			Version:             "1.0.0",
			ImageDefinitionId:   1,
			State:               models.ImageVersionState_Ready,
			StateDetails:        "enabled",
			Enabled:             true,
			AzureSubscriptionId: &subscriptionId,
			VmGeneration:        models.VmGeneration_Gen1,
		}
		galleryImageKey = azure.GalleryImageVersionKey{
			GalleryImageDefinitionKey: azure.GalleryImageDefinitionKey{
				GalleryKey: azure.GalleryKey{
					ResourceGroupKey: azure.ResourceGroupKey{
						SubscriptionId: "test-subscription",
						ResourceGroup:  "hostedcomputeims--rg",
					},
					GalleryName: "imsgallery.",
				},
				ImageDefinitionName: "image-1-gen1",
			},
			Version: "1.0.0",
		}
	)

	t.Run("fail to get azure subscription because image version is not assigned to subscription yet", func(t *testing.T) {
		imageVersion := &models.ImageVersion{
			Id:                  2,
			Version:             "1.0.0",
			ImageDefinitionId:   1,
			State:               models.ImageVersionState_Ready,
			StateDetails:        "enabled",
			Enabled:             true,
			AzureSubscriptionId: nil,
		}
		res, err := p.GetImageVersionResourceId(ctx, imageVersion)

		assert.ErrorContains(t, err, "failed to get gallery image version key: azure subscription is not assigned to image version")
		assert.Empty(t, res)
	})

	t.Run("fail to get azure subscription because azure subscription is not found", func(t *testing.T) {
		mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, subscriptionId).Return(nil, fmt.Errorf("test"))

		res, err := p.GetImageVersionResourceId(ctx, curatedImageVersion)

		assert.ErrorContains(t, err, "failed to get azure subscription by id: test")
		assert.Empty(t, res)
	})

	t.Run("successfully get image reference", func(t *testing.T) {
		mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, subscriptionId).Return(azureSubscription, nil)

		resourceId, err := p.GetImageVersionResourceId(ctx, curatedImageVersion)
		assert.NoError(t, err)
		assert.Equal(
			t,
			fmt.Sprintf("/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Compute/galleries/%s/images/%s/versions/%s",
				galleryImageKey.SubscriptionId,
				galleryImageKey.ResourceGroup,
				galleryImageKey.GalleryName,
				galleryImageKey.ImageDefinitionName,
				galleryImageKey.Version),
			resourceId)
	})
}

func Test_GetAzureResourcesNames_Prod(t *testing.T) {
	// !!! WARNING !!!
	// if result values in these tests are changed, it could be a sign of introducing breaking changes which can break existing images on production
	// consult with the team to be sure that the changes are safe

	var (
		azureSubscription = &models.AzureSubscription{
			Id:              3,
			SubscriptionId:  "00000000-0000-0000-0000-000000000000",
			ResourcesPrefix: "0123456789",
		}
		baseImageVersion = models.ImageVersion{
			Id:                  35,
			ImageDefinitionId:   8,
			Version:             "1.2.3",
			AzureSubscriptionId: &azureSubscription.Id,
			VmGeneration:        models.VmGeneration_Gen1,
		}
		provider = &galleryPromotionProvider{cfg: &Config{DeveloperId: ""}}
	)

	t.Run("base case", func(t *testing.T) {
		result := provider.getAzureResourcesNames(&baseImageVersion, azureSubscription)
		assert.Equal(t, "hostedcomputeims-0123456789-rg", result.ResourceGroupName)
		assert.Equal(t, "ims0123456789", result.StorageAccountName)
		assert.Equal(t, "vhds", result.StorageContainerName)
		assert.Equal(t, "image-8-1.2.3.vhd", result.StorageBlobName)
		assert.Equal(t, "imsgallery.0123456789", result.GalleryName)
		assert.Equal(t, "image-8-gen1", result.GalleryImageDefinitionName)
		assert.Equal(t, "1.2.3", result.GalleryImageVersion)
	})

	t.Run("gen 2", func(t *testing.T) {
		imageVersion := baseImageVersion
		imageVersion.VmGeneration = models.VmGeneration_Gen2

		result := provider.getAzureResourcesNames(&imageVersion, azureSubscription)
		assert.Equal(t, "hostedcomputeims-0123456789-rg", result.ResourceGroupName)
		assert.Equal(t, "ims0123456789", result.StorageAccountName)
		assert.Equal(t, "vhds", result.StorageContainerName)
		assert.Equal(t, "image-8-1.2.3.vhd", result.StorageBlobName)
		assert.Equal(t, "imsgallery.0123456789", result.GalleryName)
		assert.Equal(t, "image-8-gen2", result.GalleryImageDefinitionName)
		assert.Equal(t, "1.2.3", result.GalleryImageVersion)
	})

	t.Run("specialized os state", func(t *testing.T) {
		imageVersion := baseImageVersion
		imageVersion.OsState = models.OsState_Specialized

		result := provider.getAzureResourcesNames(&imageVersion, azureSubscription)
		assert.Equal(t, "hostedcomputeims-0123456789-rg", result.ResourceGroupName)
		assert.Equal(t, "ims0123456789", result.StorageAccountName)
		assert.Equal(t, "vhds", result.StorageContainerName)
		assert.Equal(t, "image-8-1.2.3.vhd", result.StorageBlobName)
		assert.Equal(t, "imsgallery.0123456789", result.GalleryName)
		assert.Equal(t, "image-8-gen1-sp", result.GalleryImageDefinitionName)
		assert.Equal(t, "1.2.3", result.GalleryImageVersion)
	})
}

func Test_GetAzureResourcesNames_Dev(t *testing.T) {
	var (
		azureSubscription = &models.AzureSubscription{
			Id:              3,
			SubscriptionId:  "00000000-0000-0000-0000-000000000000",
			ResourcesPrefix: "0123456789",
		}
		imageVersion = &models.ImageVersion{
			Id:                  35,
			ImageDefinitionId:   8,
			Version:             "1.2.3",
			AzureSubscriptionId: &azureSubscription.Id,
			VmGeneration:        models.VmGeneration_Gen1,
		}
		provider = &galleryPromotionProvider{cfg: &Config{DeveloperId: "user1"}}
	)

	t.Run("dev env", func(t *testing.T) {
		result := provider.getAzureResourcesNames(imageVersion, azureSubscription)
		assert.Equal(t, "hostedcomputeims-user1-0123456789-rg", result.ResourceGroupName)
		assert.Equal(t, "ims0123456789", result.StorageAccountName)
		assert.Equal(t, "vhds", result.StorageContainerName)
		assert.Equal(t, "image-8-1.2.3.vhd", result.StorageBlobName)
		assert.Equal(t, "imsgallery.0123456789", result.GalleryName)
		assert.Equal(t, "image-8-gen1", result.GalleryImageDefinitionName)
		assert.Equal(t, "1.2.3", result.GalleryImageVersion)
	})
}
