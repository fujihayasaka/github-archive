package processor

import (
	"context"

	enterprisev0 "github.com/github/hydro-schemas-go/hydro/schemas/github/enterprise_account/v0"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("github.enterprise_account.v0.OrganizationAdd")

func (p *Processor) organizationAdd(ctx context.Context, organizationAdd *enterprisev0.OrganizationAdd) error {
	return errors.Wrap(p.syncOrganizationEntity(ctx, organizationAdd.Organization), "failed to process OrganizationAdd")
}
