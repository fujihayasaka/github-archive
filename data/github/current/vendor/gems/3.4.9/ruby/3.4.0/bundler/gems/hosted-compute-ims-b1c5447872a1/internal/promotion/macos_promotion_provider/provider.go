package macos_promotion_provider

import (
	"context"

	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/promotion/shared_promotion"
	"github.com/github/hosted-compute-ims/internal/store"
)

type PromotionError = shared_promotion.PromotionError

//go:generate mockgen -source=$GOFILE -destination=../../../gen/mocks/mocks_promotion/macos/mock_provider.go -package mocks_macos_promotion_provider
type Provider interface {
	ProvisionImageVersion(ctx context.Context, logger *telemetry.ReportingLogger, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion, sourceVhdUrl string) *PromotionError
}

type macOSPromotionProvider struct {
	utils       *shared_promotion.SharedPromotionUtils
	imagesStore store.IImagesStore
}

func New(imagesStore store.IImagesStore) *macOSPromotionProvider {
	return &macOSPromotionProvider{
		utils:       shared_promotion.NewUtils(imagesStore),
		imagesStore: imagesStore,
	}
}
