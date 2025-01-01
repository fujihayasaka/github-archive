package macos_promotion_provider

import (
	"context"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/promotion/shared_promotion"
	"github.com/github/hosted-compute-ims/internal/store"
)

type PromotionError = shared_promotion.PromotionError

//go:generate mockgen -source=$GOFILE -destination=../../../gen/mocks/mocks_promotion/macos/mock_provider.go -package mocks_macos_promotion_provider
type Provider interface {
	ProvisionImageVersion(ctx context.Context, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion, resourceId string) *PromotionError
}

type macOSPromotionProvider struct {
	utils       *shared_promotion.SharedPromotionUtils
	imagesStore store.IImagesStore

	mcpInstances []*MCPInstance
}

func New(imagesStore store.IImagesStore, mcpInstances []*MCPInstance) *macOSPromotionProvider {
	return &macOSPromotionProvider{
		utils:        shared_promotion.NewUtils(imagesStore),
		imagesStore:  imagesStore,
		mcpInstances: mcpInstances,
	}
}
