package processor

import (
	"context"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/pkg/errors"
)

func (p *Processor) syncAccountEntity(ctx context.Context, account *entities.User) error {
	if account == nil {
		return backoff.Permanent(errors.New("no account inside the message"))
	}

	// skip if we are not interested in this account
	if ok, err := p.db.HasUserContributions(ctx, data.UserID(account.Id)); err != nil || !ok {
		return errors.Wrap(err, "failed to check cache")
	}

	_, err := p.sync.User(ctx, uint64(account.Id))
	return err
}

func (p *Processor) syncRepositoryEntity(ctx context.Context, repository *entities.Repository) error {
	if repository == nil {
		return backoff.Permanent(errors.New("no repository inside the message"))
	}

	return p.syncRepository(ctx, uint64(repository.Id))
}

func (p *Processor) syncRepository(ctx context.Context, repositoryID uint64) error {
	// skip if we are not interested in this repository
	if ok, err := p.db.HasRepositoryContributions(ctx, data.RepositoryID(repositoryID)); err != nil || !ok {
		return errors.Wrap(err, "failed to check cache")
	}

	ctx = fromctx.Logger.With(ctx, fromctx.Logger.Value(ctx).WithFields(
		kvp.Uint64("gh.turboghas.owner_id", repositoryID),
	))

	_, err := p.sync.Repository(ctx, repositoryID)
	return err
}

func (p *Processor) syncOrganizationEntity(ctx context.Context, organization *entities.Organization) error {
	if organization == nil {
		return backoff.Permanent(errors.New("no organization inside the message"))
	}

	return p.syncOrganization(ctx, organization.Id)
}

func (p *Processor) syncOrganization(ctx context.Context, ownerID uint64) error {
	// skip if we are not interested in this entity
	if ok, err := p.db.HasContributorsCache(ctx, data.UserID(ownerID), nil); err != nil || !ok {
		return errors.Wrap(err, "failed to check cache")
	}

	_, err := p.sync.Entity(ctx, ownerID)
	return err
}
