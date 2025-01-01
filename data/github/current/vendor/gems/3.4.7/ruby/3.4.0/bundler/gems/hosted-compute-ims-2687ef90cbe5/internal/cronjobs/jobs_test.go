package cronjobs

import (
	"testing"

	mocks_promotion "github.com/github/hosted-compute-ims/gen/mocks/mocks_promotion"
	mocks_promotion_gallery_provider "github.com/github/hosted-compute-ims/gen/mocks/mocks_promotion/gallery"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_store"
	mocks_runner "github.com/github/hosted-compute-ims/gen/mocks/mocks_vssf_runner"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"go.uber.org/mock/gomock"
)

var (
	mockRunnerClient             *mocks_runner.MockClient
	mockImagesStore              *mocks_store.MockIImagesStore
	mockGalleryPromotionProvider *mocks_promotion_gallery_provider.MockProvider
	mockPromotionStartClient     *mocks_promotion.MockIImagePromotionStartClient
)

func setup(t *testing.T) (*gomock.Controller, BaseJob) {
	ctrl := gomock.NewController(t)

	mockRunnerClient = mocks_runner.NewMockClient(ctrl)
	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)
	mockGalleryPromotionProvider = mocks_promotion_gallery_provider.NewMockProvider(ctrl)
	mockPromotionStartClient = mocks_promotion.NewMockIImagePromotionStartClient(ctrl)

	mockPromotion := mocks_promotion.NewMockIImagePromotionClient(ctrl)
	mockPromotion.EXPECT().GalleryProvider().Return(mockGalleryPromotionProvider).AnyTimes()

	featureflags.TEST_SetupFeatureFlagsClient(t)

	baseJob := BaseJob{
		ImagesStore:          mockImagesStore,
		RunnerClient:         mockRunnerClient,
		PromotionClient:      mockPromotion,
		PromotionStartClient: mockPromotionStartClient,
	}

	return ctrl, baseJob
}
