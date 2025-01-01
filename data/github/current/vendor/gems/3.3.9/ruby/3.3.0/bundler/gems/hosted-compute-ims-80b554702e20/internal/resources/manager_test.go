package resources

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_store"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

var mockImagesStore *mocks_store.MockIImagesStore

func setup(t *testing.T) (*gomock.Controller, *Manager) {
	ctrl := gomock.NewController(t)
	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)
	mockLogger := telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)

	cfg := Config{
		MaxImageDefinitionsPerSubscription: 10,
		MaxSubscriptionsToQueryInDb:        10,
		DeveloperId:                        "test-developer-id",
		AzureImageLocation:                 "eastus",
	}

	return ctrl, NewManager(cfg, mockImagesStore, mockLogger)
}

// write a test for the EnsureAzureSubscriptionAssignedToImageDefinition method
// it should ensure that mocked AssignAzureSubscriptionToImageDefinition method is called with
// the correct parameters
// also we need a test for case when imageDefinition.AzureSubscriptionId is nil
func TestManager_EnsureAzureSubscriptionAssignedToImageDefinition(s *testing.T) {
	ctrl, manager := setup(s)
	imageDefinitionNoAzureId := &models.ImageDefinition{
		Id:                  1,
		AzureSubscriptionId: nil,
	}

	id := uint64(1)
	imageDefinitionAssignedAzureId := &models.ImageDefinition{
		Id:                  1,
		AzureSubscriptionId: &id,
	}

	s.Run("image definition has no azure subscription id should call into store", func(t *testing.T) {
		mockImagesStore.EXPECT().AssignAzureSubscriptionToImageDefinition(gomock.Any(), gomock.Any(), gomock.Any(), gomock.Any()).Return(id, nil).Times(1)
		err := manager.EnsureAzureSubscriptionAssignedToImageDefinition(context.Background(), imageDefinitionNoAzureId)
		assert.NoError(t, err, "error should be nil")
	})

	s.Run("image definition has azure subscription id should not call into store", func(t *testing.T) {
		err := manager.EnsureAzureSubscriptionAssignedToImageDefinition(context.Background(), imageDefinitionAssignedAzureId)
		assert.NoError(t, err, "error should be nil")
	})

	defer ctrl.Finish()
}

func TestManager_GetImageBlobKey(s *testing.T) {
	ctrl, manager := setup(s)
	id := uint64(1)
	azureSubscription := &models.AzureSubscription{
		Id:              id,
		SubscriptionId:  "test-subscription",
		ResourcesPrefix: "000000000000",
	}

	imageDefinition := &models.ImageDefinition{
		Id:                  1,
		AzureSubscriptionId: &id,
	}

	imageDefinitionNoSubscription := &models.ImageDefinition{
		Id:                  2,
		AzureSubscriptionId: nil,
	}

	imageVersion := &models.ImageVersion{
		Id:                1,
		ImageDefinitionId: 1,
		Version:           "v0.0.1",
	}

	s.Run("should build blob key from image version", func(t *testing.T) {
		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageVersion.ImageDefinitionId).Return(imageDefinition, nil).Times(1),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(gomock.Any(), *imageDefinition.AzureSubscriptionId).Return(azureSubscription, nil).Times(1),
		)
		azureBlobKey, err := manager.GetImageBlobKey(context.Background(), imageVersion)
		assert.NoError(t, err, "error should be nil")

		assert.Equal(t, azureBlobKey, &azure.StorageBlobKey{
			StorageContainerKey: azure.StorageContainerKey{
				StorageKey: azure.StorageKey{
					ResourceGroupKey: azure.ResourceGroupKey{
						SubscriptionId: "test-subscription",
						ResourceGroup:  "hostedcomputeims-testdeveloperid-000000000000",
					},
					StorageAccount: "imsb000000000000",
				},
				Container: "vhds",
			},
			Blob: "image-1-v0.0.1.vhd",
		}, "azure blob key should be equal")
	})

	s.Run("should return error if image definition has no azure subscription id", func(t *testing.T) {
		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageVersion.ImageDefinitionId).Return(imageDefinitionNoSubscription, nil).Times(1),
		)
		azureBlobKey, err := manager.GetImageBlobKey(context.Background(), imageVersion)
		assert.Error(t, err, "error should not be nil")
		assert.Nil(t, azureBlobKey, "azure blob key should be nil")
	})

	defer ctrl.Finish()
}

func TestManager_GetGalleryImageVersionKey(s *testing.T) {
	ctrl, manager := setup(s)
	id := uint64(1)
	azureSubscription := &models.AzureSubscription{
		Id:              id,
		SubscriptionId:  "test-subscription",
		ResourcesPrefix: "00000000000000",
	}

	imageDefinition := &models.ImageDefinition{
		Id:                  1,
		AzureSubscriptionId: &id,
	}

	imageDefinitionNoSubscription := &models.ImageDefinition{
		Id:                  2,
		AzureSubscriptionId: nil,
	}

	imageVersion := &models.ImageVersion{
		Id:                1,
		ImageDefinitionId: 1,
		Version:           "v0.0.1",
	}

	s.Run("should build gallery image version key from image version", func(t *testing.T) {
		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageVersion.ImageDefinitionId).Return(imageDefinition, nil).Times(1),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(gomock.Any(), *imageDefinition.AzureSubscriptionId).Return(azureSubscription, nil).Times(1),
		)
		galleryImageVersionKey, err := manager.GetGalleryImageVersionKey(context.Background(), imageVersion)
		assert.NoError(t, err, "error should be nil")

		assert.Equal(t, galleryImageVersionKey, &azure.GalleryImageVersionKey{
			GalleryImageDefinitionKey: azure.GalleryImageDefinitionKey{
				GalleryKey: azure.GalleryKey{
					ResourceGroupKey: azure.ResourceGroupKey{
						SubscriptionId: "test-subscription",
						ResourceGroup:  "hostedcomputeims-testdeveloperid-00000000000000",
					},
					GalleryName: "imsgallery00000000000000",
				},
				ImageDefinitionName: "image-1",
			},
			Version: "v0.0.1",
		}, "gallery image version key should be equal")
	})

	s.Run("should return error if image definition has no azure subscription id", func(t *testing.T) {
		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageVersion.ImageDefinitionId).Return(imageDefinitionNoSubscription, nil).Times(1),
		)
		galleryImageVersionKey, err := manager.GetGalleryImageVersionKey(context.Background(), imageVersion)
		assert.Error(t, err, "error should not be nil")
		assert.Nil(t, galleryImageVersionKey, "gallery image version key should be nil")
	})

	defer ctrl.Finish()
}

func TestManager_GetExactImageVersion(t *testing.T) {
	ctrl, manager := setup(t)
	defer ctrl.Finish()

	var (
		ctx            = context.Background()
		latestImageKey = &internalapi.ImageKey{
			Source:  "Curated",
			Id:      1,
			Version: "latest",
		}
		versionedImageKey = &internalapi.ImageKey{
			Source:  "Curated",
			Id:      1,
			Version: "1.0.0",
		}
		curatedImageVersion = &models.ImageVersion{
			Id:                2,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Ready,
			StateDetails:      "enabled",
			Enabled:           true,
		}
	)

	t.Run("fail to resolve latest image version", func(t *testing.T) {
		mockImagesStore.EXPECT().GetLatestImageVersion(ctx, latestImageKey.Id).Times(1).Return(nil, fmt.Errorf("test-error"))

		res, err := manager.GetExactImageVersion(ctx, latestImageKey)

		assert.ErrorContains(t, err, "failed to get latest image version: test-error")
		assert.Nil(t, res)
	})

	t.Run("latest image version is not found", func(t *testing.T) {
		mockImagesStore.EXPECT().GetLatestImageVersion(ctx, latestImageKey.Id).Times(1).Return(nil, nil)

		res, err := manager.GetExactImageVersion(ctx, latestImageKey)

		assert.NoError(t, err)
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved latest version", func(t *testing.T) {
		mockImagesStore.EXPECT().GetLatestImageVersion(ctx, latestImageKey.Id).Times(1).Return(curatedImageVersion, nil)

		res, err := manager.GetExactImageVersion(ctx, latestImageKey)

		assert.NoError(t, err)
		assert.Equal(t, curatedImageVersion.Id, res.Id)
	})

	t.Run("fail to get specific image version", func(t *testing.T) {
		mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, versionedImageKey.Id, versionedImageKey.Version).Times(1).Return(nil, fmt.Errorf("test-error"))

		res, err := manager.GetExactImageVersion(ctx, versionedImageKey)

		assert.ErrorContains(t, err, "failed to get specific image version: test-error")
		assert.Nil(t, res)
	})

	t.Run("specific image version is not found", func(t *testing.T) {
		mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, versionedImageKey.Id, versionedImageKey.Version).Times(1).Return(nil, nil)

		res, err := manager.GetExactImageVersion(ctx, versionedImageKey)

		assert.NoError(t, err)
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved specific image version", func(t *testing.T) {
		mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, versionedImageKey.Id, versionedImageKey.Version).Times(1).Return(curatedImageVersion, nil)

		res, err := manager.GetExactImageVersion(ctx, versionedImageKey)

		assert.NoError(t, err)
		assert.Equal(t, curatedImageVersion.Id, res.Id)
	})
}

func TestManager_GetImageReference(t *testing.T) {
	subscriptionId := uint64(1)
	ctrl, manager := setup(t)
	defer ctrl.Finish()

	var (
		ctx               = context.Background()
		azureSubscription = &models.AzureSubscription{
			Id:             subscriptionId,
			SubscriptionId: "test-subscription",
		}
		imageDefinition = &models.ImageDefinition{
			Id:                  1,
			AzureSubscriptionId: &subscriptionId,
		}
		curatedImageVersion = &models.ImageVersion{
			Id:                2,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Ready,
			StateDetails:      "enabled",
			Enabled:           true,
		}
		galleryImageKey = azure.GalleryImageVersionKey{
			GalleryImageDefinitionKey: azure.GalleryImageDefinitionKey{
				GalleryKey: azure.GalleryKey{
					ResourceGroupKey: azure.ResourceGroupKey{
						SubscriptionId: "test-subscription",
						ResourceGroup:  "hostedcomputeims-testdeveloperid-",
					},
					GalleryName: "imsgallery",
				},
				ImageDefinitionName: "image-1",
			},
			Version: "1.0.0",
		}
	)

	t.Run("fail to get image definition", func(t *testing.T) {
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageVersion.ImageDefinitionId).Times(1).Return(nil, fmt.Errorf("test-error"))

		res, err := manager.GetImageReference(ctx, curatedImageVersion)

		assert.ErrorContains(t, err, "failed to get gallery image version key: failed to get image definition by id: test-error")
		assert.Nil(t, res)
	})

	t.Run("fail to get azure subscription because image definition is not assigned to subscription yet", func(t *testing.T) {
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageVersion.ImageDefinitionId).Times(1).Return(&models.ImageDefinition{Id: 1, AzureSubscriptionId: nil}, nil)

		res, err := manager.GetImageReference(ctx, curatedImageVersion)

		assert.ErrorContains(t, err, "failed to get gallery image version key: azure subscription is not assigned to image definition")
		assert.Nil(t, res)
	})

	t.Run("fail to get azure subscription because azure subscription is not found", func(t *testing.T) {
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageVersion.ImageDefinitionId).Times(1).Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, *imageDefinition.AzureSubscriptionId).Return(nil, fmt.Errorf("test"))

		res, err := manager.GetImageReference(ctx, curatedImageVersion)

		assert.ErrorContains(t, err, "failed to get azure subscription by id: test")
		assert.Nil(t, res)
	})

	t.Run("successfully get image reference", func(t *testing.T) {
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageVersion.ImageDefinitionId).Times(1).Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, *imageDefinition.AzureSubscriptionId).Return(azureSubscription, nil)

		res, err := manager.GetImageReference(ctx, curatedImageVersion)
		assert.NoError(t, err)
		assert.Equal(
			t,
			fmt.Sprintf("/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Compute/galleries/%s/images/%s/versions/%s",
				galleryImageKey.SubscriptionId,
				galleryImageKey.ResourceGroup,
				galleryImageKey.GalleryName,
				galleryImageKey.ImageDefinitionName,
				galleryImageKey.Version),
			*res.ID)
	})
}
