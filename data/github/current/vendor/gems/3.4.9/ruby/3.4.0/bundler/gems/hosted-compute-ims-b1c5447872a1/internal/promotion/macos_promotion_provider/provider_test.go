package macos_promotion_provider

import (
	"testing"

	"github.com/github/hosted-compute-ims/gen/mocks/mocks_store"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/promotion/shared_promotion"
	"go.uber.org/mock/gomock"
)

var mockImagesStore *mocks_store.MockIImagesStore

func setup(t *testing.T) (*gomock.Controller, *macOSPromotionProvider) {
	ctrl := gomock.NewController(t)

	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)

	featureflags.TEST_SetupFeatureFlagsClient(t)

	return ctrl, &macOSPromotionProvider{
		utils:       shared_promotion.NewUtils(mockImagesStore),
		imagesStore: mockImagesStore,
	}
}
