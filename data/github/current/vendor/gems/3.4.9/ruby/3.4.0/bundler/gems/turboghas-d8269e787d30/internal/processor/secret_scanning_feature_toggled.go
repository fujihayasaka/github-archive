package processor

import (
	"context"

	secretscanningv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/secret_scanning/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("github.secret_scanning.v1.SecretScanningFeatureToggled")

func (p *Processor) secretScanningFeatureToggled(ctx context.Context, secretScanningFeatureToggled *secretscanningv1.SecretScanningFeatureToggled) error {
	return errors.Wrap(p.syncRepository(ctx, uint64(secretScanningFeatureToggled.RepositoryId)), "failed to process SecretScanningFeatureToggled")
}
