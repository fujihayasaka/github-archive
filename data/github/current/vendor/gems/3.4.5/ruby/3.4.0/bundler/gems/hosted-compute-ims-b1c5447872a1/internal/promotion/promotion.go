package promotion

import (
	"context"
	"fmt"

	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/promotion/gallery_promotion_provider"
	"github.com/github/hosted-compute-ims/internal/promotion/macos_promotion_provider"
	"github.com/github/hosted-compute-ims/internal/promotion/shared_promotion"
	"github.com/github/hosted-compute-ims/internal/resources"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/worker/aqueduct"
	"github.com/github/hosted-compute-ims/internal/worker/queue"
)

type PromotionError = shared_promotion.PromotionError

//go:generate mockgen -source=$GOFILE -destination=../../gen/mocks/mocks_promotion/mock_promotion.go -package mocks_promotion
type IImagePromotionClient interface {
	ProvisionImageVersion(ctx context.Context, logger *telemetry.ReportingLogger, imageVersionId uint64, sourceVhdUrl string) *PromotionError
	ProvisionImageVersionFailedAfterMaxRetries(ctx context.Context, logger *telemetry.ReportingLogger, imageVersionId uint64, failureDetails *PromotionError) error
	CleanupImageVersionResources(ctx context.Context, logger *telemetry.ReportingLogger, imageVersionId uint64) *PromotionError
	DeleteImageVersion(ctx context.Context, logger *telemetry.ReportingLogger, imageVersionId uint64) *PromotionError
}

type ImagePromotionClient struct {
	utils             *shared_promotion.SharedPromotionUtils
	imagesStore       store.IImagesStore
	workerQueueClient queue.IWorkerQueueClient
	galleryProvider   gallery_promotion_provider.Provider
	macOSProvider     macos_promotion_provider.Provider
}

func NewImagePromotionClient(cfg *aqueduct.Config, azureClient azure.IAzureClient, imagesStore store.IImagesStore, resourceManager resources.IManager) (*ImagePromotionClient, error) {
	workerQueueClient, err := queue.NewWorkerQueueClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create worker queue client: %w", err)
	}

	return &ImagePromotionClient{
		utils:             shared_promotion.NewUtils(imagesStore),
		imagesStore:       imagesStore,
		workerQueueClient: workerQueueClient,
		galleryProvider:   gallery_promotion_provider.New(imagesStore, azureClient, resourceManager),
		macOSProvider:     macos_promotion_provider.New(imagesStore),
	}, nil
}
