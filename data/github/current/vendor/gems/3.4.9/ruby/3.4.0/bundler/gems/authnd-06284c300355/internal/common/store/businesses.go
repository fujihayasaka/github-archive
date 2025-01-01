package store

import (
	"context"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

type BusinessesStore interface {
	FindBusinessBySlug(ctx context.Context, slug string) (*models.Business, error)
	BusinessIdForProgrammaticAccessToken(ctx context.Context, id uint64) (uint64, error)
}

// FindBusinessBySlug finds the business (i.e. proxima Tenant) from the slug.
func (s *store) FindBusinessBySlug(ctx context.Context, slug string) (*models.Business, error) {
	ctx = mysql.WithQueryTableName(ctx, "businesses")

	if !s.isProxima {
		return nil, errors.New("not available in non-proxima environment")
	}

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindBusinessBySlug")
	defer span.End()

	var business models.Business
	ex := s.resolver.ReadOnlyExecutorForTable("businesses")
	err := ex.GetContext(ctx, &business, "SELECT id,shortcode FROM businesses WHERE slug = ?", slug)

	s.trackFindResult(ctx, ex.ConnectionName(), "business_by_slug", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	return &business, nil
}

// BusinessIdForProgrammaticAccessToken returns the id of the business to which the token with the provided tokenId is scoped
func (s *store) BusinessIdForProgrammaticAccessToken(ctx context.Context, tokenId uint64) (uint64, error) {
	if !s.isProxima {
		return 0, errors.New("not available in non-proxima environment")
	}

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.BusinessIdForProgrammaticAccessToken")
	defer span.End()

	ex := s.resolver.ReadOnlyExecutorForTable("programmatic_access_tokens")
	var actorId uint64
	err := ex.GetContext(mysql.WithQueryTableName(ctx, "programmatic_access_tokens"), &actorId, `
		SELECT actor_id FROM programmatic_access_tokens WHERE id = ?`, tokenId)
	if err != nil {
		return 0, errors.WithStack(err)
	}
	s.trackFindResult(ctx, ex.ConnectionName(), "business_id_for_programmatic_access_token", timer, err)

	ex = s.resolver.ReadOnlyExecutorForTable("users")
	var businessId uint64
	err = ex.GetContext(mysql.WithQueryTableName(ctx, "users"), &businessId, `
		SELECT business_id FROM users WHERE id = ?`, actorId)
	if err != nil {
		return 0, errors.WithStack(err)
	}
	s.trackFindResult(ctx, ex.ConnectionName(), "business_id_for_programmatic_access_token", timer, err)

	return businessId, nil
}

func (s *enterpriseStore) FindBusinessBySlug(ctx context.Context, slug string) (*models.Business, error) {
	return nil, errors.New("not implemented")
}

func (s *enterpriseStore) BusinessIdForProgrammaticAccessToken(ctx context.Context, tokenId uint64) (uint64, error) {
	return 0, errors.New("not implemented")
}
