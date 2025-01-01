package cronjobs

import (
	"context"

	"github.com/github/hosted-compute-ims/internal/promotion"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_runner"
)

type Job interface {
	Perform(ctx context.Context) error
	GetName() string
}

type BaseJob struct {
	ImagesStore          store.IImagesStore
	RunnerClient         vssf_runner.Client
	PromotionClient      promotion.IImagePromotionClient
	PromotionStartClient promotion.IImagePromotionStartClient
}
