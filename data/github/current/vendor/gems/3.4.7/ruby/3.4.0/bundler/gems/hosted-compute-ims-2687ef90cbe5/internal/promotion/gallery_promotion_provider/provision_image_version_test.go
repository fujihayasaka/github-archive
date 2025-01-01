package gallery_promotion_provider

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestProvisionImageVersion(t *testing.T) {
	var (
		ctx             = context.Background()
		imageDefinition = &models.ImageDefinition{
			Id:        1,
			OwnerId:   "github",
			ImageType: models.ImageType_Curated,
			Name:      "test-image",
			OsType:    models.OsType_Linux,
		}
		imageVersionWithoutAzureSubscription = &models.ImageVersion{
			Id:                  1,
			Version:             "1.0.0",
			ImageDefinitionId:   1,
			State:               models.ImageVersionState_Provisioning,
			Enabled:             true,
			VmGeneration:        models.VmGeneration_Gen1,
			OsState:             models.OsState_Generalized,
			AzureSubscriptionId: nil,
		}
		imageVersion = &models.ImageVersion{
			Id:                  1,
			Version:             "1.0.0",
			ImageDefinitionId:   1,
			State:               models.ImageVersionState_Provisioning,
			Enabled:             true,
			VmGeneration:        models.VmGeneration_Gen1,
			OsState:             models.OsState_Generalized,
			AzureSubscriptionId: utils.ToPtr[uint64](1),
		}
		azureSubscription = &models.AzureSubscription{
			Id:             1,
			SubscriptionId: "test-subscription",
		}
		azureBlobKey                   = azure.NewStorageBlobKey("test-subscription", "hostedcomputeims--rg", "ims", "vhds", "image-1-1.0.0.vhd")
		azureGalleryKey                = azure.NewGalleryImageVersionKey("test-subscription", "hostedcomputeims--rg", "imsgallery.", "image-1-gen1", "1.0.0")
		imageVersionReplicationRegions = azure.ImageVersionReplications{{Region: "eastus", ReplicasCount: 1}, {Region: "westus", ReplicasCount: 1}}
	)

	t.Run("source VHD url is not reachable", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, "")
		assert.ErrorContains(t, err.Err, "source VHD url is not reachable")
	})

	t.Run("failed to assign azure subscription to image definition", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().AssignAzureSubscriptionToImageVersion(ctx, imageVersion.Id).Return(imageVersion, fmt.Errorf("test"))

		err := p.ProvisionImageVersion(ctx, &models.ImageDefinition{Id: imageDefinition.Id}, imageVersionWithoutAzureSubscription, server.URL)
		assert.ErrorContains(t, err.Err, "failed to assign azure subscription to image version: test")
	})

	t.Run("failed to get image blob key for image version", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(nil, fmt.Errorf("test"))

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err.Err, "failed to get image blob key")
	})

	t.Run("failed to ensure azure storage container exists", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err.Err, "failed to ensure azure storage container exists: failed to create storage account")
	})

	t.Run("failed to copy image to blob", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err.Err, "failed to copy image to blob")
	})

	t.Run("failed to get gallery image version key", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(nil, fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err.Err, "failed to get gallery image version key")
	})

	t.Run("failed to ensure azure gallery image definition exists", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err.Err, "failed to ensure azure gallery image definition exists")
	})

	t.Run("failed to get previous image version", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, imageVersion.VmGeneration, imageVersion.OsState, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err.Err, "failed to get latest image version: test")
	})

	t.Run("failed to create image version from blob", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, imageVersion.VmGeneration, imageVersion.OsState, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, nil),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions, gomock.Any()).Return(fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err.Err, "failed to create image version from blob")
	})

	t.Run("failed to get gallery image version size", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, imageVersion.VmGeneration, imageVersion.OsState, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, nil),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().GetGalleryImageVersionSize(ctx, azureGalleryKey).Return(int32(0), fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err.Err, "failed to get gallery image version size")
	})

	t.Run("failed to save gallery image version size to database", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, imageVersion.VmGeneration, imageVersion.OsState, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, nil),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().GetGalleryImageVersionSize(ctx, azureGalleryKey).Return(int32(30), nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err.Err, "failed to save image version size to database")
	})

	t.Run("failed to update image version resource id", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, imageVersion.VmGeneration, imageVersion.OsState, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, nil),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().GetGalleryImageVersionSize(ctx, azureGalleryKey).Return(int32(30), nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err, "failed to set resource id for image version")
	})

	t.Run("failed to delete blob", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, imageVersion.VmGeneration, imageVersion.OsState, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, nil),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().GetGalleryImageVersionSize(ctx, azureGalleryKey).Return(int32(30), nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().DeleteBlob(ctx, azureBlobKey).Return(fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err, "failed to delete blob after image version creation")
	})

	t.Run("success when previous version doesn't exist", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, imageVersion.VmGeneration, imageVersion.OsState, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, nil),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().GetGalleryImageVersionSize(ctx, azureGalleryKey).Return(int32(30), nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().DeleteBlob(ctx, azureBlobKey).Return(nil),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.Nil(t, err)
	})

	t.Run("success when previous version exist", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, imageVersion.VmGeneration, imageVersion.OsState, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, nil),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().GetGalleryImageVersionSize(ctx, azureGalleryKey).Return(int32(30), nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().DeleteBlob(ctx, azureBlobKey).Return(nil),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, server.URL)
		assert.Nil(t, err)
	})

	t.Run("success and assign image version to azure subscription", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageDefinition.Id).AnyTimes().Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionById(ctx, imageVersion.Id).AnyTimes().Return(imageVersion, nil)

		gomock.InOrder(
			mockImagesStore.EXPECT().AssignAzureSubscriptionToImageVersion(ctx, imageVersion.Id).Return(imageVersion, nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, imageVersion.VmGeneration, imageVersion.OsState, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, nil),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().GetGalleryImageVersionSize(ctx, azureGalleryKey).Return(int32(30), nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().DeleteBlob(ctx, azureBlobKey).Return(nil),
		)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersionWithoutAzureSubscription, server.URL)
		assert.Nil(t, err)
	})
}

func TestEnsureAzureStorageContainerExist(t *testing.T) {
	var (
		ctx                 = context.Background()
		storageContainerKey = azure.StorageContainerKey{
			StorageKey: azure.StorageKey{
				ResourceGroupKey: azure.ResourceGroupKey{
					SubscriptionId: "test_subscription_id",
					ResourceGroup:  "test_resource_group",
				},
				StorageAccount: "test_storage_account",
			},
			Container: "test_container",
		}
	)

	t.Run("failed to create resource group", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, gomock.Any(), gomock.Any()).Times(1).Return(fmt.Errorf("test")),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, gomock.Any(), gomock.Any()).Times(0),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, gomock.Any()).Times(0),
		)

		err := s.ensureAzureStorageContainerExist(ctx, &storageContainerKey, "eastus")
		assert.ErrorContains(t, err, "failed to create resource group: test")
	})

	t.Run("failed to create storage account", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, gomock.Any(), gomock.Any()).Times(1).Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, gomock.Any(), gomock.Any()).Times(1).Return(fmt.Errorf("test")),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, gomock.Any()).Times(0),
		)

		err := s.ensureAzureStorageContainerExist(ctx, &storageContainerKey, "eastus")
		assert.ErrorContains(t, err, "failed to create storage account: test")
	})

	t.Run("failed to create storage account container", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, gomock.Any(), gomock.Any()).Times(1).Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, gomock.Any(), gomock.Any()).Times(1).Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, gomock.Any()).Times(1).Return(fmt.Errorf("test")),
		)

		err := s.ensureAzureStorageContainerExist(ctx, &storageContainerKey, "eastus")
		assert.ErrorContains(t, err, "failed to create storage account container: test")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, gomock.Any(), gomock.Any()).Times(1).Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, gomock.Any(), gomock.Any()).Times(1).Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, gomock.Any()).Times(1).Return(nil),
		)

		err := s.ensureAzureStorageContainerExist(ctx, &storageContainerKey, "eastus")
		assert.NoError(t, err)
	})
}

func TestUpdateImageVersionReplications(t *testing.T) {
	var (
		ctx          = context.Background()
		imageVersion = &models.ImageVersion{
			Id:                  1,
			Version:             "1.0.0",
			ImageDefinitionId:   1,
			State:               models.ImageVersionState_Provisioning,
			Enabled:             true,
			AzureSubscriptionId: utils.ToPtr[uint64](1),
		}
		azureSubscription = &models.AzureSubscription{
			Id:             1,
			SubscriptionId: "test-subscription",
		}
		defaultReplications = azure.ImageVersionReplications{
			azure.ImageVersionRegionReplication{
				Region:        "eastus",
				ReplicasCount: 1,
			},
			azure.ImageVersionRegionReplication{
				Region:        "westus",
				ReplicasCount: 1,
			},
		}
	)

	t.Run("failed to get gallery image version key", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(nil, fmt.Errorf("test"))

		err := s.UpdateImageVersionReplications(ctx, imageVersion, defaultReplications)
		assert.ErrorContains(t, err, "failed to get gallery image version key")
	})

	t.Run("failed to update gallery image version replicas", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().UpdateImageVersionReplications(ctx, gomock.Any(), defaultReplications).Return(fmt.Errorf("test")),
		)

		err := s.UpdateImageVersionReplications(ctx, imageVersion, defaultReplications)
		assert.ErrorContains(t, err, "failed to update image version replications")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, s := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetAzureSubscriptionById(ctx, azureSubscription.Id).Return(azureSubscription, nil),
			mockAzureClient.EXPECT().UpdateImageVersionReplications(ctx, gomock.Any(), defaultReplications).Return(nil),
		)

		err := s.UpdateImageVersionReplications(ctx, imageVersion, defaultReplications)
		assert.NoError(t, err)
	})
}
