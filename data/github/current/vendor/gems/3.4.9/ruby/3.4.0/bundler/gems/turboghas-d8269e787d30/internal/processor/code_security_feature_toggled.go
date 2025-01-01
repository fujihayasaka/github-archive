package processor

import (
	"context"

	codesecurityv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/code_security/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("github.code_security.v1.CodeSecurityFeatureToggled")

func (p *Processor) codeSecurityFeatureToggled(ctx context.Context, codeSecurityFeatureToggled *codesecurityv1.CodeSecurityFeatureToggled) error {
	return errors.Wrap(p.syncRepository(ctx, uint64(codeSecurityFeatureToggled.RepositoryId)), "failed to process CodeSecurityFeatureToggled")
}
