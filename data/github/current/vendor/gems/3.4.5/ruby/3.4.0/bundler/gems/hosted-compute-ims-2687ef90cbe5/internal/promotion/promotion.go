package promotion

import (
	"context"
	"fmt"

	"github.com/github/go-config"
	"github.com/github/hosted-compute-core/asymmjwt"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/promotion/gallery_promotion_provider"
	"github.com/github/hosted-compute-ims/internal/promotion/macos_promotion_provider"
	"github.com/github/hosted-compute-ims/internal/promotion/shared_promotion"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/worker/aqueduct"
	"github.com/github/hosted-compute-ims/internal/worker/queue"
)

type PromotionError = shared_promotion.PromotionError

//go:generate mockgen -source=$GOFILE -destination=../../gen/mocks/mocks_promotion/mock_promotion.go -package mocks_promotion
type IImagePromotionClient interface {
	GalleryProvider() gallery_promotion_provider.Provider
	PromotionStartClient() IImagePromotionStartClient

	ProvisionImageVersion(ctx context.Context, imageVersionId uint64, sourceVhdUrl string, workflowOwnerId string) *PromotionError
	ProvisionImageVersionFailedAfterMaxRetries(ctx context.Context, imageVersionId uint64, failureDetails *PromotionError) error
	CleanupImageVersionResources(ctx context.Context, imageVersionId uint64) *PromotionError
	DeleteImageDefinitionWithAllVersions(ctx context.Context, imageDefinitionId uint64) *PromotionError
	DeleteImageVersion(ctx context.Context, imageVersionId uint64) *PromotionError
}

//go:generate mockgen -source=$GOFILE -destination=../../gen/mocks/mocks_promotion/mock_promotion.go -package mocks_promotion
type IImagePromotionStartClient interface {
	StartAsyncImageVersionProvision(ctx context.Context, imageVersionId uint64, sourceVhdUrl string, workflowOwnerId string) error
	StartAsyncImageVersionDeletion(ctx context.Context, imageVersionId uint64) error
	StartAsyncImageDefinitionDeletion(ctx context.Context, imageDefinitionId uint64) error
	StartAsyncOwnerResourcesCleanup(ctx context.Context, ownerId string) error
}

type ImagePromotionClient struct {
	utils             *shared_promotion.SharedPromotionUtils
	imagesStore       store.IImagesStore
	workerQueueClient queue.IWorkerQueueClient
	galleryProvider   gallery_promotion_provider.Provider
	macOSProvider     macos_promotion_provider.Provider
}

type ImagePromotionStartClient struct {
	imagesStore       store.IImagesStore
	workerQueueClient queue.IWorkerQueueClient
}

func NewImagePromotionClient(ctx context.Context, aqueductCfg *aqueduct.Config, azureCfg *azure.Config, mcpCfg *macos_promotion_provider.Config, jwtCfg *asymmjwt.Config, imagesStore store.IImagesStore) (*ImagePromotionClient, error) {
	workerQueueClient, err := queue.NewWorkerQueueClient(ctx, aqueductCfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create worker queue client: %w", err)
	}

	azureClient, err := azure.NewAzureClient(azureCfg)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize azure client: %w", err)
	}

	galleryPromotionProviderCfg := &gallery_promotion_provider.Config{}
	if err := config.Load(galleryPromotionProviderCfg); err != nil {
		return nil, fmt.Errorf("failed to load gallery promotion provider config: %w", err)
	}

	mcpInstances, err := macos_promotion_provider.NewMacInstances(mcpCfg, jwtCfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create mcp instance clients: %w", err)
	}

	return &ImagePromotionClient{
		utils:             shared_promotion.NewUtils(imagesStore),
		imagesStore:       imagesStore,
		workerQueueClient: workerQueueClient,
		galleryProvider:   gallery_promotion_provider.New(galleryPromotionProviderCfg, imagesStore, azureClient),
		macOSProvider:     macos_promotion_provider.New(imagesStore, mcpInstances),
	}, nil
}

func (p *ImagePromotionClient) GalleryProvider() gallery_promotion_provider.Provider {
	return p.galleryProvider
}

func (p *ImagePromotionClient) PromotionStartClient() IImagePromotionStartClient {
	return &ImagePromotionStartClient{
		imagesStore:       p.imagesStore,
		workerQueueClient: p.workerQueueClient,
	}
}
