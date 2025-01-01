package promotion

import (
	"testing"

	mocks_promotion_gallery_provider "github.com/github/hosted-compute-ims/gen/mocks/mocks_promotion/gallery"
	mocks_promotion_macos_provider "github.com/github/hosted-compute-ims/gen/mocks/mocks_promotion/macos"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_store"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_worker"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/promotion/shared_promotion"
	"go.uber.org/mock/gomock"
)

var (
	mockImagesStore              *mocks_store.MockIImagesStore
	mockGalleryPromotionProvider *mocks_promotion_gallery_provider.MockProvider
	mockMacOSPromotionProvider   *mocks_promotion_macos_provider.MockProvider
	mockWorkerQueueClient        *mocks_worker.MockIWorkerQueueClient
)

func setup(t *testing.T) (*gomock.Controller, *ImagePromotionClient) {
	ctrl := gomock.NewController(t)

	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)
	mockGalleryPromotionProvider = mocks_promotion_gallery_provider.NewMockProvider(ctrl)
	mockMacOSPromotionProvider = mocks_promotion_macos_provider.NewMockProvider(ctrl)
	mockWorkerQueueClient = mocks_worker.NewMockIWorkerQueueClient(ctrl)

	featureflags.TEST_SetupFeatureFlagsClient(t)

	return ctrl, &ImagePromotionClient{
		utils:             shared_promotion.NewUtils(mockImagesStore),
		imagesStore:       mockImagesStore,
		galleryProvider:   mockGalleryPromotionProvider,
		macOSProvider:     mockMacOSPromotionProvider,
		workerQueueClient: mockWorkerQueueClient,
	}
}
