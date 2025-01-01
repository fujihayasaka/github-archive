package twirp

import (
	"testing"

	mocks_promotion "github.com/github/hosted-compute-ims/gen/mocks/mocks_promotion"
	mocks_promotion_gallery_provider "github.com/github/hosted-compute-ims/gen/mocks/mocks_promotion/gallery"

	"github.com/github/hosted-compute-ims/gen/mocks/mocks_store"
	"go.uber.org/mock/gomock"
)

var (
	mockImagesStore              *mocks_store.MockIImagesStore
	mockPromotionClient          *mocks_promotion.MockIImagePromotionClient
	mockPromotionStartClient     *mocks_promotion.MockIImagePromotionStartClient
	mockGalleryPromotionProvider *mocks_promotion_gallery_provider.MockProvider
)

func setupImagesApiHandler(t *testing.T) (*gomock.Controller, *ImagesApiHandler) {
	ctrl := gomock.NewController(t)

	return ctrl, &ImagesApiHandler{
		baseApiHandler: setupBaseHandlers(ctrl),
	}
}

func setupImagesAdminApiHandler(t *testing.T) (*gomock.Controller, *ImagesAdminApiHandler) {
	ctrl := gomock.NewController(t)

	return ctrl, &ImagesAdminApiHandler{
		baseApiHandler: setupBaseHandlers(ctrl),
	}
}

func setupInternalImagesApiHandler(t *testing.T) (*gomock.Controller, *InternalImagesApiHandler) {
	ctrl := gomock.NewController(t)

	return ctrl, &InternalImagesApiHandler{
		baseApiHandler: setupBaseHandlers(ctrl),
	}
}

func setupBaseHandlers(ctrl *gomock.Controller) baseApiHandler {
	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)
	mockPromotionClient = mocks_promotion.NewMockIImagePromotionClient(ctrl)
	mockPromotionStartClient = mocks_promotion.NewMockIImagePromotionStartClient(ctrl)
	mockGalleryPromotionProvider = mocks_promotion_gallery_provider.NewMockProvider(ctrl)

	mockPromotionClient.EXPECT().GalleryProvider().Return(mockGalleryPromotionProvider).AnyTimes()

	return baseApiHandler{
		imageStore:           mockImagesStore,
		promotionClient:      mockPromotionClient,
		promotionStartClient: mockPromotionStartClient,
	}
}
