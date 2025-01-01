package azure

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"testing"

	azfake "github.com/Azure/azure-sdk-for-go/sdk/azcore/fake"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resources/armresources"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

func TestCreateGalleryIfNotExists(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	location := "westus2"
	galleryKey := &GalleryKey{
		GalleryName: "ims-gallery",
		ResourceGroupKey: ResourceGroupKey{
			SubscriptionId: subscriptionId,
			ResourceGroup:  "rgName",
		},
	}

	t.Run("already exists", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(galleryKey.GalleryResourceId(), true)

		err := azureClient.CreateGalleryIfNotExists(ctx, galleryKey, location)
		assert.NoError(t, err)
	})

	t.Run("created", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(galleryKey.GalleryResourceId(), false)

		fakeGalleriesServer.BeginCreateOrUpdate = func(ctx context.Context, resourceGroupName string, galleryName string, gallery armcompute.Gallery, options *armcompute.GalleriesClientBeginCreateOrUpdateOptions) (resp azfake.PollerResponder[armcompute.GalleriesClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			resp.SetTerminalResponse(http.StatusOK, armcompute.GalleriesClientCreateOrUpdateResponse{}, nil)
			return
		}

		err := azureClient.CreateGalleryIfNotExists(ctx, galleryKey, location)
		assert.NoError(t, err)
	})

	t.Run("failed to create", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(galleryKey.GalleryResourceId(), false)

		fakeGalleriesServer.BeginCreateOrUpdate = func(ctx context.Context, resourceGroupName string, galleryName string, gallery armcompute.Gallery, options *armcompute.GalleriesClientBeginCreateOrUpdateOptions) (resp azfake.PollerResponder[armcompute.GalleriesClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		err := azureClient.CreateGalleryIfNotExists(ctx, galleryKey, location)
		assert.ErrorContains(t, err, "failed to create gallery")
	})

	t.Run("failed to poll status", func(t *testing.T) {
		azureClient := setup()
		mockResourceExistence(galleryKey.GalleryResourceId(), false)

		fakeGalleriesServer.BeginCreateOrUpdate = func(ctx context.Context, resourceGroupName string, galleryName string, gallery armcompute.Gallery, options *armcompute.GalleriesClientBeginCreateOrUpdateOptions) (resp azfake.PollerResponder[armcompute.GalleriesClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			resp.AddNonTerminalResponse(http.StatusAccepted, nil)
			resp.AddPollingError(errors.New("Internal server error"))
			return
		}

		err := azureClient.CreateGalleryIfNotExists(ctx, galleryKey, location)
		assert.ErrorContains(t, err, "failed to poll gallery creation status")
	})
}

func TestCreateGalleryImageDefinitionIfNotExists(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	location := "westus2"
	galleryImageDefinitionKey := &GalleryImageDefinitionKey{
		ImageDefinitionName: "ims-gallery-image-definition",
		GalleryKey: GalleryKey{
			GalleryName: "ims-gallery",
			ResourceGroupKey: ResourceGroupKey{
				SubscriptionId: subscriptionId,
				ResourceGroup:  "rgName",
			},
		},
	}

	t.Run("already exists", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(galleryImageDefinitionKey.GalleryImageDefinitionResourceId(), true)

		err := azureClient.CreateGalleryImageDefinitionIfNotExists(ctx, galleryImageDefinitionKey, models.OsType_Linux, models.Architecture_X64, location)
		assert.NoError(t, err)
	})

	t.Run("created", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(galleryImageDefinitionKey.GalleryImageDefinitionResourceId(), false)

		fakeGalleryImagesServer.BeginCreateOrUpdate = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImage armcompute.GalleryImage, options *armcompute.GalleryImagesClientBeginCreateOrUpdateOptions) (resp azfake.PollerResponder[armcompute.GalleryImagesClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			resp.SetTerminalResponse(http.StatusOK, armcompute.GalleryImagesClientCreateOrUpdateResponse{}, nil)
			return
		}

		err := azureClient.CreateGalleryImageDefinitionIfNotExists(ctx, galleryImageDefinitionKey, models.OsType_Linux, models.Architecture_X64, location)
		assert.NoError(t, err)
	})

	t.Run("failed to create", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(galleryImageDefinitionKey.GalleryImageDefinitionResourceId(), false)

		fakeGalleryImagesServer.BeginCreateOrUpdate = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImage armcompute.GalleryImage, options *armcompute.GalleryImagesClientBeginCreateOrUpdateOptions) (resp azfake.PollerResponder[armcompute.GalleryImagesClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		err := azureClient.CreateGalleryImageDefinitionIfNotExists(ctx, galleryImageDefinitionKey, models.OsType_Linux, models.Architecture_X64, location)
		assert.ErrorContains(t, err, "failed to create gallery image definition")
	})

	t.Run("failed to poll status", func(t *testing.T) {
		azureClient := setup()
		mockResourceExistence(galleryImageDefinitionKey.GalleryImageDefinitionResourceId(), false)

		fakeGalleryImagesServer.BeginCreateOrUpdate = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImage armcompute.GalleryImage, options *armcompute.GalleryImagesClientBeginCreateOrUpdateOptions) (resp azfake.PollerResponder[armcompute.GalleryImagesClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			resp.AddNonTerminalResponse(http.StatusAccepted, nil)
			resp.AddPollingError(errors.New("Internal server error"))
			return
		}

		err := azureClient.CreateGalleryImageDefinitionIfNotExists(ctx, galleryImageDefinitionKey, models.OsType_Linux, models.Architecture_X64, location)
		assert.ErrorContains(t, err, "failed to poll gallery image definition creation status")
	})
}

func TestCheckGalleryImageDefinitionExists(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	galleryImageDefinitionKey := &GalleryImageDefinitionKey{
		ImageDefinitionName: "ims-gallery-image-definition",
		GalleryKey: GalleryKey{
			GalleryName: "ims-gallery",
			ResourceGroupKey: ResourceGroupKey{
				SubscriptionId: subscriptionId,
				ResourceGroup:  "rgName",
			},
		},
	}

	t.Run("exists", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(galleryImageDefinitionKey.GalleryImageDefinitionResourceId(), true)

		exist, err := azureClient.CheckGalleryImageDefinitionExists(ctx, galleryImageDefinitionKey)
		assert.NoError(t, err)
		assert.True(t, exist)
	})

	t.Run("not exists", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(galleryImageDefinitionKey.GalleryImageDefinitionResourceId(), false)

		exist, err := azureClient.CheckGalleryImageDefinitionExists(ctx, galleryImageDefinitionKey)
		assert.NoError(t, err)
		assert.False(t, exist)
	})

	t.Run("failed to check", func(t *testing.T) {
		azureClient := setup()

		fakeResourcesServer.GetByID = func(ctx context.Context, id string, apiVersion string, options *armresources.ClientGetByIDOptions) (resp azfake.Responder[armresources.ClientGetByIDResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		_, err := azureClient.CheckGalleryImageDefinitionExists(ctx, galleryImageDefinitionKey)
		assert.ErrorContains(t, err, "failed to check resource existence")
	})
}

func TestCreateImageVersionFromBlob(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	location := "westus2"
	imageVersionReplicationRegions := ImageVersionReplications{{Region: "eastus", ReplicasCount: 1}, {Region: "westus", ReplicasCount: 1}}
	imageVersionKey := &GalleryImageVersionKey{
		Version: "1.0.0",
		GalleryImageDefinitionKey: GalleryImageDefinitionKey{
			ImageDefinitionName: "ims-gallery-image-definition",
			GalleryKey: GalleryKey{
				GalleryName: "ims-gallery",
				ResourceGroupKey: ResourceGroupKey{
					SubscriptionId: subscriptionId,
					ResourceGroup:  "rgName",
				},
			},
		},
	}
	storageBlobKey := &StorageBlobKey{
		Blob: "image.vhd",
		StorageContainerKey: StorageContainerKey{
			Container: "container",
			StorageKey: StorageKey{
				StorageAccount: "storageaccount",
				ResourceGroupKey: ResourceGroupKey{
					SubscriptionId: subscriptionId,
					ResourceGroup:  "rgName",
				},
			},
		},
	}

	successfulImageVersionResponse := armcompute.GalleryImageVersion{
		Properties: &armcompute.GalleryImageVersionProperties{
			ReplicationStatus: &armcompute.ReplicationStatus{
				Summary: []*armcompute.RegionalReplicationStatus{
					{
						Progress: to.Ptr[int32](100),
						Region:   &location,
					},
				},
			},
			ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateSucceeded),
		},
		Location: &location,
	}

	t.Run("already exists", func(t *testing.T) {
		azureClient := setup()

		startedCreation := false

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			resp.SetResponse(http.StatusOK, armcompute.GalleryImageVersionsClientGetResponse{
				GalleryImageVersion: successfulImageVersionResponse,
			}, nil)
			return
		}

		fakeGalleryImageVersionsServer.BeginCreateOrUpdate = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, galleryImageVersion armcompute.GalleryImageVersion, options *armcompute.GalleryImageVersionsClientBeginCreateOrUpdateOptions) (resp azfake.PollerResponder[armcompute.GalleryImageVersionsClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			resp.SetTerminalResponse(http.StatusOK, armcompute.GalleryImageVersionsClientCreateOrUpdateResponse{}, nil)
			startedCreation = true
			return
		}

		err := azureClient.CreateImageVersionFromBlob(ctx, imageVersionKey, storageBlobKey, location, imageVersionReplicationRegions, func(update OperationProgressUpdate) {})
		assert.NoError(t, err)
		assert.False(t, startedCreation)
	})

	t.Run("created", func(t *testing.T) {
		azureClient := setup()

		startedCreation := false

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			if startedCreation {
				resp.SetResponse(http.StatusOK, armcompute.GalleryImageVersionsClientGetResponse{
					GalleryImageVersion: successfulImageVersionResponse,
				}, nil)
			} else {
				errResp.SetResponseError(http.StatusNotFound, "Not found")
			}

			return
		}

		fakeGalleryImageVersionsServer.BeginCreateOrUpdate = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, galleryImageVersion armcompute.GalleryImageVersion, options *armcompute.GalleryImageVersionsClientBeginCreateOrUpdateOptions) (resp azfake.PollerResponder[armcompute.GalleryImageVersionsClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			resp.SetTerminalResponse(http.StatusOK, armcompute.GalleryImageVersionsClientCreateOrUpdateResponse{}, nil)
			startedCreation = true
			return
		}

		err := azureClient.CreateImageVersionFromBlob(ctx, imageVersionKey, storageBlobKey, location, imageVersionReplicationRegions, func(update OperationProgressUpdate) {})
		assert.NoError(t, err)
		assert.True(t, startedCreation)
	})

	t.Run("failed to check image version existence", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		err := azureClient.CreateImageVersionFromBlob(ctx, imageVersionKey, storageBlobKey, location, imageVersionReplicationRegions, func(update OperationProgressUpdate) {})
		assert.ErrorContains(t, err, "failed to check image version existence")
	})

	t.Run("failed to create image version", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusNotFound, "Not found")
			return
		}

		fakeGalleryImageVersionsServer.BeginCreateOrUpdate = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, galleryImageVersion armcompute.GalleryImageVersion, options *armcompute.GalleryImageVersionsClientBeginCreateOrUpdateOptions) (resp azfake.PollerResponder[armcompute.GalleryImageVersionsClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		err := azureClient.CreateImageVersionFromBlob(ctx, imageVersionKey, storageBlobKey, location, imageVersionReplicationRegions, func(update OperationProgressUpdate) {})
		assert.ErrorContains(t, err, "failed to create image version")
	})

	t.Run("failed to poll image version creation status", func(t *testing.T) {
		azureClient := setup()
		startedCreation := false

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			if startedCreation {
				errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			} else {
				errResp.SetResponseError(http.StatusNotFound, "Not found")
			}
			return
		}

		fakeGalleryImageVersionsServer.BeginCreateOrUpdate = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, galleryImageVersion armcompute.GalleryImageVersion, options *armcompute.GalleryImageVersionsClientBeginCreateOrUpdateOptions) (resp azfake.PollerResponder[armcompute.GalleryImageVersionsClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			resp.SetTerminalResponse(http.StatusOK, armcompute.GalleryImageVersionsClientCreateOrUpdateResponse{}, nil)
			startedCreation = true
			return
		}

		err := azureClient.CreateImageVersionFromBlob(ctx, imageVersionKey, storageBlobKey, location, imageVersionReplicationRegions, func(update OperationProgressUpdate) {})
		assert.ErrorContains(t, err, "failed to poll image version creation status")
		assert.True(t, startedCreation)
	})

	t.Run("failed to provision image", func(t *testing.T) {
		azureClient := setup()
		startedCreation := false

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			if startedCreation {
				resp.SetResponse(http.StatusOK, armcompute.GalleryImageVersionsClientGetResponse{
					GalleryImageVersion: armcompute.GalleryImageVersion{
						Properties: &armcompute.GalleryImageVersionProperties{
							ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateFailed),
							ReplicationStatus: nil,
						},
					},
				}, nil)
			} else {
				errResp.SetResponseError(http.StatusNotFound, "Not found")
			}
			return
		}

		fakeGalleryImageVersionsServer.BeginCreateOrUpdate = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, galleryImageVersion armcompute.GalleryImageVersion, options *armcompute.GalleryImageVersionsClientBeginCreateOrUpdateOptions) (resp azfake.PollerResponder[armcompute.GalleryImageVersionsClientCreateOrUpdateResponse], errResp azfake.ErrorResponder) {
			resp.SetTerminalResponse(http.StatusOK, armcompute.GalleryImageVersionsClientCreateOrUpdateResponse{}, nil)
			startedCreation = true
			return
		}

		err := azureClient.CreateImageVersionFromBlob(ctx, imageVersionKey, storageBlobKey, location, imageVersionReplicationRegions, func(update OperationProgressUpdate) {})
		assert.ErrorContains(t, err, "failed to create image version from blob with status 'Failed'")
		assert.True(t, startedCreation)
	})
}

func TestListImageVersions(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	galleryImageDefinitionKey := &GalleryImageDefinitionKey{
		ImageDefinitionName: "ims-gallery-image-definition",
		GalleryKey: GalleryKey{
			GalleryName: "ims-gallery",
			ResourceGroupKey: ResourceGroupKey{
				SubscriptionId: subscriptionId,
				ResourceGroup:  "rgName",
			},
		},
	}
	imageVersionIndex := 0
	buildFakeImageVersions := func(count int) []*armcompute.GalleryImageVersion {
		result := make([]*armcompute.GalleryImageVersion, count)

		for i := 0; i < count; i++ {
			imageVersionIndex++
			result[i] = &armcompute.GalleryImageVersion{
				Name: to.Ptr(fmt.Sprintf("%d.0.0", imageVersionIndex)),
			}
		}

		return result
	}

	t.Run("return all versions", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.NewListByGalleryImagePager = func(resourceGroupName string, galleryName string, galleryImageName string, options *armcompute.GalleryImageVersionsClientListByGalleryImageOptions) (resp azfake.PagerResponder[armcompute.GalleryImageVersionsClientListByGalleryImageResponse]) {
			resp.AddPage(http.StatusOK, armcompute.GalleryImageVersionsClientListByGalleryImageResponse{
				GalleryImageVersionList: armcompute.GalleryImageVersionList{
					Value: buildFakeImageVersions(5),
				},
			}, nil)
			resp.AddPage(http.StatusOK, armcompute.GalleryImageVersionsClientListByGalleryImageResponse{
				GalleryImageVersionList: armcompute.GalleryImageVersionList{
					Value: buildFakeImageVersions(5),
				},
			}, nil)
			resp.AddPage(http.StatusOK, armcompute.GalleryImageVersionsClientListByGalleryImageResponse{
				GalleryImageVersionList: armcompute.GalleryImageVersionList{
					Value: buildFakeImageVersions(3),
				},
			}, nil)
			return
		}

		versions, err := azureClient.ListImageVersions(ctx, galleryImageDefinitionKey, 100)
		assert.NoError(t, err)
		assert.Equal(t, 13, len(versions))
	})

	t.Run("limit number of versions", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.NewListByGalleryImagePager = func(resourceGroupName string, galleryName string, galleryImageName string, options *armcompute.GalleryImageVersionsClientListByGalleryImageOptions) (resp azfake.PagerResponder[armcompute.GalleryImageVersionsClientListByGalleryImageResponse]) {
			resp.AddPage(http.StatusOK, armcompute.GalleryImageVersionsClientListByGalleryImageResponse{
				GalleryImageVersionList: armcompute.GalleryImageVersionList{
					Value: buildFakeImageVersions(5),
				},
			}, nil)
			resp.AddPage(http.StatusOK, armcompute.GalleryImageVersionsClientListByGalleryImageResponse{
				GalleryImageVersionList: armcompute.GalleryImageVersionList{
					Value: buildFakeImageVersions(5),
				},
			}, nil)
			return
		}

		versions, err := azureClient.ListImageVersions(ctx, galleryImageDefinitionKey, 3)
		assert.NoError(t, err)
		assert.Equal(t, 3, len(versions))
	})

	t.Run("failed to list versions", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.NewListByGalleryImagePager = func(resourceGroupName string, galleryName string, galleryImageName string, options *armcompute.GalleryImageVersionsClientListByGalleryImageOptions) (resp azfake.PagerResponder[armcompute.GalleryImageVersionsClientListByGalleryImageResponse]) {
			resp.AddResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		_, err := azureClient.ListImageVersions(ctx, galleryImageDefinitionKey, 100)
		assert.ErrorContains(t, err, "failed to advance page")
	})
}

func TestDeleteImageVersion(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	imageVersionKey := &GalleryImageVersionKey{
		Version: "1.0.0",
		GalleryImageDefinitionKey: GalleryImageDefinitionKey{
			ImageDefinitionName: "ims-gallery-image-definition",
			GalleryKey: GalleryKey{
				GalleryName: "ims-gallery",
				ResourceGroupKey: ResourceGroupKey{
					SubscriptionId: subscriptionId,
					ResourceGroup:  "rgName",
				},
			},
		},
	}

	t.Run("version doesn't exist", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusNotFound, "Not found")
			return
		}

		err := azureClient.DeleteImageVersion(ctx, imageVersionKey)
		assert.NoError(t, err)
	})

	t.Run("version is deleted", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			resp.SetResponse(http.StatusOK, armcompute.GalleryImageVersionsClientGetResponse{}, nil)
			return
		}

		fakeGalleryImageVersionsServer.BeginDelete = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientBeginDeleteOptions) (resp azfake.PollerResponder[armcompute.GalleryImageVersionsClientDeleteResponse], errResp azfake.ErrorResponder) {
			resp.SetTerminalResponse(http.StatusOK, armcompute.GalleryImageVersionsClientDeleteResponse{}, nil)
			return
		}

		err := azureClient.DeleteImageVersion(ctx, imageVersionKey)
		assert.NoError(t, err)
	})

	t.Run("failed to delete version", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			resp.SetResponse(http.StatusOK, armcompute.GalleryImageVersionsClientGetResponse{}, nil)
			return
		}

		fakeGalleryImageVersionsServer.BeginDelete = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientBeginDeleteOptions) (resp azfake.PollerResponder[armcompute.GalleryImageVersionsClientDeleteResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		err := azureClient.DeleteImageVersion(ctx, imageVersionKey)
		assert.ErrorContains(t, err, "failed to begin gallery image version deletion")
	})

	t.Run("failed to poll status", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			resp.SetResponse(http.StatusOK, armcompute.GalleryImageVersionsClientGetResponse{}, nil)
			return
		}

		fakeGalleryImageVersionsServer.BeginDelete = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientBeginDeleteOptions) (resp azfake.PollerResponder[armcompute.GalleryImageVersionsClientDeleteResponse], errResp azfake.ErrorResponder) {
			resp.AddNonTerminalResponse(http.StatusOK, nil)
			resp.AddPollingError(errors.New("failed to poll for gallery image version deletion"))
			return
		}

		err := azureClient.DeleteImageVersion(ctx, imageVersionKey)
		assert.ErrorContains(t, err, "failed to poll image version deletion status")
	})
}

func TestDeleteImageDefinition(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	imageDefinitionKey := &GalleryImageDefinitionKey{
		ImageDefinitionName: "ims-gallery-image-definition",
		GalleryKey: GalleryKey{
			GalleryName: "ims-gallery",
			ResourceGroupKey: ResourceGroupKey{
				SubscriptionId: subscriptionId,
				ResourceGroup:  "rgName",
			},
		},
	}

	t.Run("definition doesn't exist", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(imageDefinitionKey.GalleryImageDefinitionResourceId(), false)

		err := azureClient.DeleteImageDefinition(ctx, imageDefinitionKey)
		assert.NoError(t, err)
	})

	t.Run("definition is deleted", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(imageDefinitionKey.GalleryImageDefinitionResourceId(), true)

		fakeGalleryImagesServer.BeginDelete = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, options *armcompute.GalleryImagesClientBeginDeleteOptions) (resp azfake.PollerResponder[armcompute.GalleryImagesClientDeleteResponse], errResp azfake.ErrorResponder) {
			resp.SetTerminalResponse(http.StatusOK, armcompute.GalleryImagesClientDeleteResponse{}, nil)
			return
		}

		err := azureClient.DeleteImageDefinition(ctx, imageDefinitionKey)
		assert.NoError(t, err)
	})

	t.Run("failed to delete definition", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(imageDefinitionKey.GalleryImageDefinitionResourceId(), true)

		fakeGalleryImagesServer.BeginDelete = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, options *armcompute.GalleryImagesClientBeginDeleteOptions) (resp azfake.PollerResponder[armcompute.GalleryImagesClientDeleteResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		err := azureClient.DeleteImageDefinition(ctx, imageDefinitionKey)
		assert.ErrorContains(t, err, "failed to begin gallery image definition deletion")
	})

	t.Run("failed to poll status", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(imageDefinitionKey.GalleryImageDefinitionResourceId(), true)

		fakeGalleryImagesServer.BeginDelete = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, options *armcompute.GalleryImagesClientBeginDeleteOptions) (resp azfake.PollerResponder[armcompute.GalleryImagesClientDeleteResponse], errResp azfake.ErrorResponder) {
			resp.AddNonTerminalResponse(http.StatusOK, nil)
			resp.AddPollingError(errors.New("failed to poll for gallery image definition deletion"))
			return
		}

		err := azureClient.DeleteImageDefinition(ctx, imageDefinitionKey)
		assert.ErrorContains(t, err, "failed to poll gallery image definition deletion status")
	})
}

func TestGetGalleryImageVersionSize(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	imageVersionKey := &GalleryImageVersionKey{
		Version: "1.0.0",
		GalleryImageDefinitionKey: GalleryImageDefinitionKey{
			ImageDefinitionName: "ims-gallery-image-definition",
			GalleryKey: GalleryKey{
				GalleryName: "ims-gallery",
				ResourceGroupKey: ResourceGroupKey{
					SubscriptionId: subscriptionId,
					ResourceGroup:  "rgName",
				},
			},
		},
	}

	t.Run("version doesn't exist", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusNotFound, "Not found")
			return
		}

		size, err := azureClient.GetGalleryImageVersionSize(ctx, imageVersionKey)
		assert.ErrorContains(t, err, "failed to get image version properties")
		assert.Equal(t, int32(0), size)
	})

	t.Run("version doesn't contain size", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			resp.SetResponse(http.StatusOK, armcompute.GalleryImageVersionsClientGetResponse{
				GalleryImageVersion: armcompute.GalleryImageVersion{
					Properties: &armcompute.GalleryImageVersionProperties{
						StorageProfile: &armcompute.GalleryImageVersionStorageProfile{
							OSDiskImage: &armcompute.GalleryOSDiskImage{
								SizeInGB: nil,
							},
						},
					},
				},
			}, nil)
			return
		}

		size, err := azureClient.GetGalleryImageVersionSize(ctx, imageVersionKey)
		assert.ErrorContains(t, err, "failed to get image version size: size is nil")
		assert.Equal(t, int32(0), size)
	})

	t.Run("returns correct size", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			resp.SetResponse(http.StatusOK, armcompute.GalleryImageVersionsClientGetResponse{
				GalleryImageVersion: armcompute.GalleryImageVersion{
					Properties: &armcompute.GalleryImageVersionProperties{
						StorageProfile: &armcompute.GalleryImageVersionStorageProfile{
							OSDiskImage: &armcompute.GalleryOSDiskImage{
								SizeInGB: to.Ptr[int32](30),
							},
						},
					},
				},
			}, nil)
			return
		}

		size, err := azureClient.GetGalleryImageVersionSize(ctx, imageVersionKey)
		assert.NoError(t, err)
		assert.Equal(t, int32(30), size)
	})
}

func TestCheckImageVersionExistence(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	imageVersionKey := &GalleryImageVersionKey{
		Version: "1.0.0",
		GalleryImageDefinitionKey: GalleryImageDefinitionKey{
			ImageDefinitionName: "ims-gallery-image-definition",
			GalleryKey: GalleryKey{
				GalleryName: "ims-gallery",
				ResourceGroupKey: ResourceGroupKey{
					SubscriptionId: subscriptionId,
					ResourceGroup:  "rgName",
				},
			},
		},
	}

	t.Run("version doesn't exist", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusNotFound, "Not found")
			return
		}

		exists, err := azureClient.checkImageVersionExistence(ctx, imageVersionKey)
		assert.NoError(t, err)
		assert.False(t, exists)
	})

	t.Run("version exists", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			resp.SetResponse(http.StatusOK, armcompute.GalleryImageVersionsClientGetResponse{}, nil)
			return
		}

		exists, err := azureClient.checkImageVersionExistence(ctx, imageVersionKey)
		assert.NoError(t, err)
		assert.True(t, exists)
	})

	t.Run("failed to get version", func(t *testing.T) {
		azureClient := setup()

		fakeGalleryImageVersionsServer.Get = func(ctx context.Context, resourceGroupName string, galleryName string, galleryImageName string, galleryImageVersionName string, options *armcompute.GalleryImageVersionsClientGetOptions) (resp azfake.Responder[armcompute.GalleryImageVersionsClientGetResponse], errResp azfake.ErrorResponder) {
			errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		_, err := azureClient.checkImageVersionExistence(ctx, imageVersionKey)
		assert.ErrorContains(t, err, "failed to check image version existence")
	})
}

func TestImageVersionReplicationsToArmComputeTargetRegions(t *testing.T) {
	replications := ImageVersionReplications{
		{Region: "westus", ReplicasCount: 1},
		{Region: "westus2", ReplicasCount: 10},
		{Region: "eastus", ReplicasCount: 31},
	}
	expectedTargetRegions := []*armcompute.TargetRegion{
		{Name: to.Ptr("westus"), RegionalReplicaCount: to.Ptr[int32](1), StorageAccountType: to.Ptr(armcompute.StorageAccountTypeStandardLRS)},
		{Name: to.Ptr("westus2"), RegionalReplicaCount: to.Ptr[int32](10), StorageAccountType: to.Ptr(armcompute.StorageAccountTypeStandardLRS)},
		{Name: to.Ptr("eastus"), RegionalReplicaCount: to.Ptr[int32](31), StorageAccountType: to.Ptr(armcompute.StorageAccountTypeStandardLRS)},
	}
	assert.Equal(t, expectedTargetRegions, replications.ToArmComputeTargetRegions())
}
