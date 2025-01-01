package macos_promotion_provider

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestProvisionImageVersion(t *testing.T) {
	var (
		ctx             = context.Background()
		logger          = telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)
		imageDefinition = &models.ImageDefinition{
			Id:        1,
			OwnerId:   "github",
			ImageType: models.ImageType_Curated,
			Name:      "test-image",
			OsType:    models.OsType_Linux,
		}
		imageVersion = &models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Provisioning,
			Enabled:           true,
		}
	)

	t.Run("failed to set resource id for image version", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(uint64(0), fmt.Errorf("test"))

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, "resource-id")
		assert.ErrorContains(t, err, "failed to set resource id for image version")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(imageVersion.Id, nil)

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, "")
		assert.Nil(t, err)
	})
}
