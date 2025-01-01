package gallery_promotion_provider

import (
	"testing"

	"github.com/github/hosted-compute-ims/gen/mocks/mocks_azure"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_store"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/promotion/shared_promotion"
	"go.uber.org/mock/gomock"
)

var (
	mockImagesStore *mocks_store.MockIImagesStore
	mockAzureClient *mocks_azure.MockIAzureClient
)

func setup(t *testing.T) (*gomock.Controller, *galleryPromotionProvider) {
	ctrl := gomock.NewController(t)

	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)
	mockAzureClient = mocks_azure.NewMockIAzureClient(ctrl)

	featureflags.TEST_SetupFeatureFlagsClient(t)

	return ctrl, &galleryPromotionProvider{
		cfg: &Config{
			AzureImageLocation:       "eastus",
			CuratedImageAzureRegions: []string{"eastus", "westus"},
			CustomImageAzureRegions:  []string{"eastus", "westus"},
		},
		utils:       shared_promotion.NewUtils(mockImagesStore),
		imagesStore: mockImagesStore,
		azureClient: mockAzureClient,
	}
}
