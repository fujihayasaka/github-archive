package gallery_promotion_provider

import (
	"context"

	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/promotion/shared_promotion"
	"github.com/github/hosted-compute-ims/internal/store"
)

type PromotionError = shared_promotion.PromotionError

//go:generate mockgen -source=$GOFILE -destination=../../../gen/mocks/mocks_promotion/gallery/mock_provider.go -package mocks_gallery_promotion_provider
type Provider interface {
	ProvisionImageVersion(ctx context.Context, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion, sourceVhdUrl string) *PromotionError
	CleanupImageVersionResources(ctx context.Context, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion) *PromotionError
	UpdateImageVersionReplications(ctx context.Context, imageVersion *models.ImageVersion, replications azure.ImageVersionReplications) error
	GetImageVersionResourceId(ctx context.Context, imageVersion *models.ImageVersion) (string, error)
	GetAzureRegionsForReplication(image *models.ImageDefinition) []string
}

type galleryPromotionProvider struct {
	cfg         *Config
	utils       *shared_promotion.SharedPromotionUtils
	imagesStore store.IImagesStore
	azureClient azure.IAzureClient
}

func New(cfg *Config, imagesStore store.IImagesStore, azureClient azure.IAzureClient) *galleryPromotionProvider {
	return &galleryPromotionProvider{
		cfg:         cfg,
		utils:       shared_promotion.NewUtils(imagesStore),
		imagesStore: imagesStore,
		azureClient: azureClient,
	}
}
