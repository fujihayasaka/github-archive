package azure

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewStorageBlobKey(t *testing.T) {
	key := NewStorageBlobKey("952e77d2-b220-4105-9cb8-5a98bf1d4660", "ims-rg", "imsstorage", "ims-container", "ims-blob")
	assert.Equal(t, key.Blob, "ims-blob")
	assert.Equal(t, key.Container, "ims-container")
	assert.Equal(t, key.StorageAccount, "imsstorage")
	assert.Equal(t, key.ResourceGroup, "ims-rg")
	assert.Equal(t, key.SubscriptionId, "952e77d2-b220-4105-9cb8-5a98bf1d4660")
	assert.Equal(t, key.BlobUrl(), "https://imsstorage.blob.core.windows.net/ims-container/ims-blob")
	assert.Equal(t, key.StorageContainerResourceId(), "/subscriptions/952e77d2-b220-4105-9cb8-5a98bf1d4660/resourceGroups/ims-rg/providers/Microsoft.Storage/storageAccounts/imsstorage/blobServices/default/containers/ims-container")
	assert.Equal(t, key.StorageResourceId(), "/subscriptions/952e77d2-b220-4105-9cb8-5a98bf1d4660/resourceGroups/ims-rg/providers/Microsoft.Storage/storageAccounts/imsstorage")
	assert.Equal(t, key.ResourceGroupResourceId(), "/subscriptions/952e77d2-b220-4105-9cb8-5a98bf1d4660/resourceGroups/ims-rg")
}

func TestNewGalleryImageVersionKey(t *testing.T) {
	key := NewGalleryImageVersionKey("952e77d2-b220-4105-9cb8-5a98bf1d4660", "ims-rg", "ims-gallery", "ims-image", "1.0.0")
	assert.Equal(t, key.Version, "1.0.0")
	assert.Equal(t, key.ImageDefinitionName, "ims-image")
	assert.Equal(t, key.GalleryName, "ims-gallery")
	assert.Equal(t, key.ResourceGroup, "ims-rg")
	assert.Equal(t, key.SubscriptionId, "952e77d2-b220-4105-9cb8-5a98bf1d4660")
	assert.Equal(t, key.GalleryImageDefinitionResourceId(), "/subscriptions/952e77d2-b220-4105-9cb8-5a98bf1d4660/resourceGroups/ims-rg/providers/Microsoft.Compute/galleries/ims-gallery/images/ims-image")
	assert.Equal(t, key.GalleryResourceId(), "/subscriptions/952e77d2-b220-4105-9cb8-5a98bf1d4660/resourceGroups/ims-rg/providers/Microsoft.Compute/galleries/ims-gallery")
	assert.Equal(t, key.ResourceGroupResourceId(), "/subscriptions/952e77d2-b220-4105-9cb8-5a98bf1d4660/resourceGroups/ims-rg")
}
