package macos_promotion_provider

import (
	"context"

	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
)

func (p *macOSPromotionProvider) ProvisionImageVersion(ctx context.Context, logger *telemetry.ReportingLogger, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion, sourceVhdUrl string) *PromotionError {
	return nil
}
