package gallery_promotion_provider

import (
	"testing"

	"github.com/github/hosted-compute-ims/gen/mocks/mocks_azure"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_manager"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_store"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/promotion/shared_promotion"
	"go.uber.org/mock/gomock"
)

var (
	mockImagesStore     *mocks_store.MockIImagesStore
	mockAzureClient     *mocks_azure.MockIAzureClient
	mockResourceManager *mocks_manager.MockIManager
)

func setup(t *testing.T) (*gomock.Controller, *galleryPromotionProvider) {
	ctrl := gomock.NewController(t)

	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)
	mockAzureClient = mocks_azure.NewMockIAzureClient(ctrl)
	mockResourceManager = mocks_manager.NewMockIManager(ctrl)

	featureflags.TEST_SetupFeatureFlagsClient(t)

	return ctrl, &galleryPromotionProvider{
		utils:           shared_promotion.NewUtils(mockImagesStore),
		imagesStore:     mockImagesStore,
		azureClient:     mockAzureClient,
		resourceManager: mockResourceManager,
	}
}
