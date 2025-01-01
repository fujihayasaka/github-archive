package clientbuilder

import (
	"testing"

	azfake "github.com/Azure/azure-sdk-for-go/sdk/azcore/fake"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/assert"
)

func TestClients(t *testing.T) {
	builder := NewClientBuilder(&azfake.TokenCredential{})
	defaultSubscriptionId := "3538de02-1d18-4fca-bbef-4b7ac5920c3a"

	t.Run("ResourcesClient", func(t *testing.T) {
		client, err := builder.ResourcesClient(defaultSubscriptionId)
		assert.NoError(t, err)
		assert.NotNil(t, client)

		client, err = builder.ResourcesClient(utils.SharedDevImagesSubscriptionId)
		assert.Error(t, err, utils.SharedDevImagesErrorMessage)
		assert.Nil(t, client)
	})

	t.Run("ResourceGroupsClient", func(t *testing.T) {
		client, err := builder.ResourceGroupsClient(defaultSubscriptionId)
		assert.NoError(t, err)
		assert.NotNil(t, client)

		client, err = builder.ResourceGroupsClient(utils.SharedDevImagesSubscriptionId)
		assert.Error(t, err, utils.SharedDevImagesErrorMessage)
		assert.Nil(t, client)
	})

	t.Run("StorageAccountsClient", func(t *testing.T) {
		client, err := builder.StorageAccountsClient(defaultSubscriptionId)
		assert.NoError(t, err)
		assert.NotNil(t, client)

		client, err = builder.StorageAccountsClient(utils.SharedDevImagesSubscriptionId)
		assert.Error(t, err, utils.SharedDevImagesErrorMessage)
		assert.Nil(t, client)
	})

	t.Run("StorageContainersClient", func(t *testing.T) {
		client, err := builder.StorageContainersClient(defaultSubscriptionId)
		assert.NoError(t, err)
		assert.NotNil(t, client)

		client, err = builder.StorageContainersClient(utils.SharedDevImagesSubscriptionId)
		assert.Error(t, err, utils.SharedDevImagesErrorMessage)
		assert.Nil(t, client)
	})

	t.Run("PageBlobClient", func(t *testing.T) {
		client, err := builder.PageBlobClient(defaultSubscriptionId, "url")
		assert.NoError(t, err)
		assert.NotNil(t, client)

		client, err = builder.PageBlobClient(utils.SharedDevImagesSubscriptionId, "url")
		assert.Error(t, err, utils.SharedDevImagesErrorMessage)
		assert.Nil(t, client)
	})

	t.Run("GalleriesClient", func(t *testing.T) {
		client, err := builder.GalleriesClient(defaultSubscriptionId)
		assert.NoError(t, err)
		assert.NotNil(t, client)

		client, err = builder.GalleriesClient(utils.SharedDevImagesSubscriptionId)
		assert.Error(t, err, utils.SharedDevImagesErrorMessage)
		assert.Nil(t, client)
	})

	t.Run("GalleryImagesClient", func(t *testing.T) {
		client, err := builder.GalleryImagesClient(defaultSubscriptionId)
		assert.NoError(t, err)
		assert.NotNil(t, client)

		client, err = builder.GalleryImagesClient(utils.SharedDevImagesSubscriptionId)
		assert.Error(t, err, utils.SharedDevImagesErrorMessage)
		assert.Nil(t, client)
	})

	t.Run("GalleryImageVersionsClient", func(t *testing.T) {
		client, err := builder.GalleryImageVersionsClient(defaultSubscriptionId)
		assert.NoError(t, err)
		assert.NotNil(t, client)

		client, err = builder.GalleryImageVersionsClient(utils.SharedDevImagesSubscriptionId)
		assert.Error(t, err, utils.SharedDevImagesErrorMessage)
		assert.Nil(t, client)
	})
}
