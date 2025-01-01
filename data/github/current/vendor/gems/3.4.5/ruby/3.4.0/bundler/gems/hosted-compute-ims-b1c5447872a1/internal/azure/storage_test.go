package azure

import (
	"context"
	"errors"
	"net/http"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/fake"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/storage/armstorage"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

func TestCreateStorageAccountIfNotExists(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	location := "westus2"
	storageKey := &StorageKey{
		StorageAccount: "ims-storage",
		ResourceGroupKey: ResourceGroupKey{
			SubscriptionId: subscriptionId,
			ResourceGroup:  "rgName",
		},
	}

	t.Run("already exists", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(storageKey.StorageResourceId(), true)

		err := azureClient.CreateStorageAccountIfNotExists(ctx, storageKey, location)
		assert.NoError(t, err)
	})

	t.Run("created", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(storageKey.StorageResourceId(), false)

		fakeStorageAccountsServer.BeginCreate = func(ctx context.Context, resourceGroupName string, accountName string, parameters armstorage.AccountCreateParameters, options *armstorage.AccountsClientBeginCreateOptions) (resp fake.PollerResponder[armstorage.AccountsClientCreateResponse], errResp fake.ErrorResponder) {
			resp.SetTerminalResponse(http.StatusOK, armstorage.AccountsClientCreateResponse{}, nil)
			return
		}

		err := azureClient.CreateStorageAccountIfNotExists(ctx, storageKey, location)
		assert.NoError(t, err)
	})

	t.Run("failed to create", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(storageKey.StorageResourceId(), false)

		fakeStorageAccountsServer.BeginCreate = func(ctx context.Context, resourceGroupName string, accountName string, parameters armstorage.AccountCreateParameters, options *armstorage.AccountsClientBeginCreateOptions) (resp fake.PollerResponder[armstorage.AccountsClientCreateResponse], errResp fake.ErrorResponder) {
			errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		err := azureClient.CreateStorageAccountIfNotExists(ctx, storageKey, location)
		assert.ErrorContains(t, err, "failed to create storage account")
	})

	t.Run("failed to poll status", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(storageKey.StorageResourceId(), false)

		fakeStorageAccountsServer.BeginCreate = func(ctx context.Context, resourceGroupName string, accountName string, parameters armstorage.AccountCreateParameters, options *armstorage.AccountsClientBeginCreateOptions) (resp fake.PollerResponder[armstorage.AccountsClientCreateResponse], errResp fake.ErrorResponder) {
			resp.AddNonTerminalResponse(http.StatusAccepted, nil)
			resp.AddPollingError(errors.New("Internal server error"))
			return
		}

		err := azureClient.CreateStorageAccountIfNotExists(ctx, storageKey, location)
		assert.ErrorContains(t, err, "failed to poll storage account creation status")
	})
}

func TestCreateStorageAccountContainerIfNotExists(t *testing.T) {
	ctx := context.Background()
	subscriptionId := uuid.New().String()
	containerKey := &StorageContainerKey{
		Container: "ims-container",
		StorageKey: StorageKey{
			StorageAccount: "ims-storage",
			ResourceGroupKey: ResourceGroupKey{
				SubscriptionId: subscriptionId,
				ResourceGroup:  "rgName",
			},
		},
	}

	t.Run("already exists", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(containerKey.StorageContainerResourceId(), true)

		err := azureClient.CreateStorageAccountContainerIfNotExists(ctx, containerKey)
		assert.NoError(t, err)
	})

	t.Run("created", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(containerKey.StorageContainerResourceId(), false)

		fakeStorageContainersServer.Create = func(ctx context.Context, resourceGroupName string, accountName string, containerName string, blobContainer armstorage.BlobContainer, options *armstorage.BlobContainersClientCreateOptions) (resp fake.Responder[armstorage.BlobContainersClientCreateResponse], errResp fake.ErrorResponder) {
			resp.SetResponse(http.StatusOK, armstorage.BlobContainersClientCreateResponse{}, nil)
			return
		}

		err := azureClient.CreateStorageAccountContainerIfNotExists(ctx, containerKey)
		assert.NoError(t, err)
	})

	t.Run("failed to create", func(t *testing.T) {
		azureClient := setup()

		mockResourceExistence(containerKey.StorageContainerResourceId(), false)

		fakeStorageContainersServer.Create = func(ctx context.Context, resourceGroupName string, accountName string, containerName string, blobContainer armstorage.BlobContainer, options *armstorage.BlobContainersClientCreateOptions) (resp fake.Responder[armstorage.BlobContainersClientCreateResponse], errResp fake.ErrorResponder) {
			errResp.SetResponseError(http.StatusInternalServerError, "Internal server error")
			return
		}

		err := azureClient.CreateStorageAccountContainerIfNotExists(ctx, containerKey)
		assert.ErrorContains(t, err, "failed to create storage container")
	})
}

func TestCopyImageToBlob(t *testing.T) {
	// azure-sdk-for-go does not provide a fake client for blob service yet
}

func TestCopyImageToBlobFastCopy(t *testing.T) {
	// azure-sdk-for-go does not provide a fake client for blob service yet
}
