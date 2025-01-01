package gallery_promotion_provider

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestProvisionImageVersion(t *testing.T) {
	var (
		ctx             = context.Background()
		logger          = telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)
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
			State:             models.ImageVersionState_Provisioning,
			Enabled:           true,
		}
		azureBlobKey                   = azure.NewStorageBlobKey("test-subscription", "rg", "account", "container", "blob.vhd")
		azureGalleryKey                = azure.NewGalleryImageVersionKey("test-subscription", "rg", "gallery", "image", "version")
		replicationRegions             = []string{"eastus", "westus"}
		imageVersionReplicationRegions = azure.ImageVersionReplications{{Region: "eastus", ReplicasCount: 1}, {Region: "westus", ReplicasCount: 1}}

		imageVersionReplicationData = &models.ImageVersionReplicationData{
			Id:                1,
			ImageDefinitionId: 1,
			ImageVersion:      "1.0.0",
			RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
				"eastus": {VMCount: 200, ReplicaCount: 4},
				"westus": {VMCount: 200, ReplicaCount: 4},
			},
		}

		imageVersionReplicationRegions2 = azure.ImageVersionReplications{{Region: "eastus", ReplicasCount: 4}, {Region: "westus", ReplicasCount: 4}}
	)

	t.Run("source VHD url is not reachable", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, "")
		assert.ErrorContains(t, err.Err, "source VHD url is not reachable")
	})

	t.Run("failed to assign azure subscription to image definition", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(200)
		}))
		defer server.Close()

		mockResourceManager.EXPECT().EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition).Return(fmt.Errorf("test"))

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err.Err, "failed to ensure azure subscription assigned to image definition: test")
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

		gomock.InOrder(
			mockResourceManager.EXPECT().EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition).Return(nil),
			mockResourceManager.EXPECT().GetImageBlobKey(ctx, imageVersion).Return(nil, fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, server.URL)
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
			mockResourceManager.EXPECT().EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition).Return(nil),
			mockResourceManager.EXPECT().GetImageBlobKey(ctx, imageVersion).Return(azureBlobKey, nil),
			mockResourceManager.EXPECT().GetLocationForImageBlob().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, server.URL)
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
			mockResourceManager.EXPECT().EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition).Return(nil),
			mockResourceManager.EXPECT().GetImageBlobKey(ctx, imageVersion).Return(azureBlobKey, nil),
			mockResourceManager.EXPECT().GetLocationForImageBlob().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, server.URL)
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
			mockResourceManager.EXPECT().EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition).Return(nil),
			mockResourceManager.EXPECT().GetImageBlobKey(ctx, imageVersion).Return(azureBlobKey, nil),
			mockResourceManager.EXPECT().GetLocationForImageBlob().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockResourceManager.EXPECT().GetGalleryImageVersionKey(ctx, imageVersion).Return(nil, fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, server.URL)
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
			mockResourceManager.EXPECT().EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition).Return(nil),
			mockResourceManager.EXPECT().GetImageBlobKey(ctx, imageVersion).Return(azureBlobKey, nil),
			mockResourceManager.EXPECT().GetLocationForImageBlob().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockResourceManager.EXPECT().GetGalleryImageVersionKey(ctx, imageVersion).Return(azureGalleryKey, nil),
			mockResourceManager.EXPECT().GetLocationForGalleryImageVersion().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, server.URL)
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
			mockResourceManager.EXPECT().EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition).Return(nil),
			mockResourceManager.EXPECT().GetImageBlobKey(ctx, imageVersion).Return(azureBlobKey, nil),
			mockResourceManager.EXPECT().GetLocationForImageBlob().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockResourceManager.EXPECT().GetGalleryImageVersionKey(ctx, imageVersion).Return(azureGalleryKey, nil),
			mockResourceManager.EXPECT().GetLocationForGalleryImageVersion().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, server.URL)
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
			mockResourceManager.EXPECT().EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition).Return(nil),
			mockResourceManager.EXPECT().GetImageBlobKey(ctx, imageVersion).Return(azureBlobKey, nil),
			mockResourceManager.EXPECT().GetLocationForImageBlob().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockResourceManager.EXPECT().GetGalleryImageVersionKey(ctx, imageVersion).Return(azureGalleryKey, nil),
			mockResourceManager.EXPECT().GetLocationForGalleryImageVersion().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, nil),
			mockResourceManager.EXPECT().GetSupportedImageRegions(imageDefinition).Return(replicationRegions),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions, gomock.Any()).Return(fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, server.URL)
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
			mockResourceManager.EXPECT().EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition).Return(nil),
			mockResourceManager.EXPECT().GetImageBlobKey(ctx, imageVersion).Return(azureBlobKey, nil),
			mockResourceManager.EXPECT().GetLocationForImageBlob().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockResourceManager.EXPECT().GetGalleryImageVersionKey(ctx, imageVersion).Return(azureGalleryKey, nil),
			mockResourceManager.EXPECT().GetLocationForGalleryImageVersion().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, nil),
			mockResourceManager.EXPECT().GetSupportedImageRegions(imageDefinition).Return(replicationRegions),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().GetGalleryImageVersionSize(ctx, azureGalleryKey).Return(int32(0), fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, server.URL)
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
			mockResourceManager.EXPECT().EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition).Return(nil),
			mockResourceManager.EXPECT().GetImageBlobKey(ctx, imageVersion).Return(azureBlobKey, nil),
			mockResourceManager.EXPECT().GetLocationForImageBlob().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockResourceManager.EXPECT().GetGalleryImageVersionKey(ctx, imageVersion).Return(azureGalleryKey, nil),
			mockResourceManager.EXPECT().GetLocationForGalleryImageVersion().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, nil),
			mockResourceManager.EXPECT().GetSupportedImageRegions(imageDefinition).Return(replicationRegions),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().GetGalleryImageVersionSize(ctx, azureGalleryKey).Return(int32(30), nil),
			mockImagesStore.EXPECT().UpdateImageVersionSize(ctx, imageVersion.Id, gomock.Any()).Return(fmt.Errorf("test")),
		)

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, server.URL)
		assert.ErrorContains(t, err.Err, "failed to save image version size to database")
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
			mockResourceManager.EXPECT().EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition).Return(nil),
			mockResourceManager.EXPECT().GetImageBlobKey(ctx, imageVersion).Return(azureBlobKey, nil),
			mockResourceManager.EXPECT().GetLocationForImageBlob().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockResourceManager.EXPECT().GetGalleryImageVersionKey(ctx, imageVersion).Return(azureGalleryKey, nil),
			mockResourceManager.EXPECT().GetLocationForGalleryImageVersion().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(nil, nil),
			mockResourceManager.EXPECT().GetSupportedImageRegions(imageDefinition).Return(replicationRegions),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().GetGalleryImageVersionSize(ctx, azureGalleryKey).Return(int32(30), nil),
			mockImagesStore.EXPECT().UpdateImageVersionSize(ctx, imageVersion.Id, gomock.Any()).Return(nil),
		)

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, server.URL)
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
			mockResourceManager.EXPECT().EnsureAzureSubscriptionAssignedToImageDefinition(ctx, imageDefinition).Return(nil),
			mockResourceManager.EXPECT().GetImageBlobKey(ctx, imageVersion).Return(azureBlobKey, nil),
			mockResourceManager.EXPECT().GetLocationForImageBlob().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureBlobKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountIfNotExists(ctx, &azureBlobKey.StorageKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateStorageAccountContainerIfNotExists(ctx, &azureBlobKey.StorageContainerKey).Return(nil),
			mockAzureClient.EXPECT().CopyImageToBlob(ctx, azureBlobKey, server.URL, gomock.Any()).Return(nil),
			mockResourceManager.EXPECT().GetGalleryImageVersionKey(ctx, imageVersion).Return(azureGalleryKey, nil),
			mockResourceManager.EXPECT().GetLocationForGalleryImageVersion().Return("eastus"),
			mockAzureClient.EXPECT().CreateResourceGroupIfNotExists(ctx, &azureGalleryKey.ResourceGroupKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryIfNotExists(ctx, &azureGalleryKey.GalleryKey, "eastus").Return(nil),
			mockAzureClient.EXPECT().CreateGalleryImageDefinitionIfNotExists(ctx, &azureGalleryKey.GalleryImageDefinitionKey, imageDefinition.OsType, imageDefinition.Architecture, "eastus").Return(nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, imageDefinition.Id).Return(imageVersion, nil),
			mockImagesStore.EXPECT().GetImageReplicationsByImageIdAndVersion(ctx, imageDefinition.Id, imageVersion.Version).Return(imageVersionReplicationData, nil),
			mockResourceManager.EXPECT().GetSupportedImageRegions(imageDefinition).Return(replicationRegions),
			mockAzureClient.EXPECT().CreateImageVersionFromBlob(ctx, azureGalleryKey, azureBlobKey, "eastus", imageVersionReplicationRegions2, gomock.Any()).Return(nil),
			mockAzureClient.EXPECT().GetGalleryImageVersionSize(ctx, azureGalleryKey).Return(int32(30), nil),
			mockImagesStore.EXPECT().UpdateImageVersionSize(ctx, imageVersion.Id, gomock.Any()).Return(nil),
		)

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, server.URL)
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
