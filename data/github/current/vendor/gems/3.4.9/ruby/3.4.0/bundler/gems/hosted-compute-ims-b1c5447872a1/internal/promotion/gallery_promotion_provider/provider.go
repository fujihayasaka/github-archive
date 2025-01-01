package gallery_promotion_provider

import (
	"context"

	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/promotion/shared_promotion"
	"github.com/github/hosted-compute-ims/internal/resources"
	"github.com/github/hosted-compute-ims/internal/store"
)

type PromotionError = shared_promotion.PromotionError

//go:generate mockgen -source=$GOFILE -destination=../../../gen/mocks/mocks_promotion/gallery/mock_provider.go -package mocks_gallery_promotion_provider
type Provider interface {
	ProvisionImageVersion(ctx context.Context, logger *telemetry.ReportingLogger, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion, sourceVhdUrl string) *PromotionError
	CleanupImageVersionResources(ctx context.Context, logger *telemetry.ReportingLogger, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion) *PromotionError
}

type galleryPromotionProvider struct {
	utils           *shared_promotion.SharedPromotionUtils
	imagesStore     store.IImagesStore
	azureClient     azure.IAzureClient
	resourceManager resources.IManager
}

func New(imagesStore store.IImagesStore, azureClient azure.IAzureClient, resourceManager resources.IManager) *galleryPromotionProvider {
	return &galleryPromotionProvider{
		utils:           shared_promotion.NewUtils(imagesStore),
		imagesStore:     imagesStore,
		azureClient:     azureClient,
		resourceManager: resourceManager,
	}
}
