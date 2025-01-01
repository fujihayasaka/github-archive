package macos_promotion_provider

import (
	"testing"

	"github.com/github/hosted-compute-ims/gen/mocks/mocks_store"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/promotion/shared_promotion"
	"github.com/github/maccloud-go-core/maccloud/generated/mcp"
	"go.uber.org/mock/gomock"
)

var (
	mockImagesStore *mocks_store.MockIImagesStore
	mockMCPClient   *mcp.MockApi
)

func setup(t *testing.T) (*gomock.Controller, *macOSPromotionProvider) {
	ctrl := gomock.NewController(t)

	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)

	featureflags.TEST_SetupFeatureFlagsClient(t)

	mockMCPClient = mcp.NewMockApi(t)

	var mcpInstances []*MCPInstance
	mcpInstances = append(mcpInstances, &MCPInstance{
		InstanceURL: "https://mcp1",
		Client:      mockMCPClient,
	})

	return ctrl, &macOSPromotionProvider{
		utils:        shared_promotion.NewUtils(mockImagesStore),
		imagesStore:  mockImagesStore,
		mcpInstances: mcpInstances,
	}
}
