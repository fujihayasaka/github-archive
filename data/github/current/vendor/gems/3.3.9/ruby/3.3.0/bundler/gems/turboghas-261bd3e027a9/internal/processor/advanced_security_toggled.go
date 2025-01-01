package processor

import (
	"context"

	securitycenterv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("github.security_center.v0.AdvancedSecurityToggled")

func (p *Processor) advancedSecurityToggled(ctx context.Context, advancedSecurityToggled *securitycenterv0.AdvancedSecurityToggled) error {
	return errors.Wrap(p.syncRepository(ctx, uint64(advancedSecurityToggled.RepositoryId)), "failed to process AdvancedSecurityToggled")
}
