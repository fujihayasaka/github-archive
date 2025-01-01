package macos_promotion_provider

import (
	"context"
	"fmt"

	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
)

func (p *macOSPromotionProvider) ProvisionImageVersion(ctx context.Context, logger *telemetry.ReportingLogger, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion, resourceId string) *PromotionError {
	_, err := p.imagesStore.UpdateImageVersion(ctx, imageVersion.Id, &models.ImageVersionUpdate{
		Enabled:    imageVersion.Enabled,
		ResourceId: resourceId,
	})
	if err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to set resource id for image version"),
			NonRetryable: false,
		}
	}

	return nil
}
