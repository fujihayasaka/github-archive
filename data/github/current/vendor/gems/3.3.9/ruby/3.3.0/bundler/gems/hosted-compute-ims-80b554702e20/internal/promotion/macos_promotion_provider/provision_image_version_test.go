package macos_promotion_provider

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
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

	t.Run("success", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		err := p.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, "")
		assert.Nil(t, err)
	})
}
