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

type AuthenticationTokensStore interface {
	FindAuthenticationTokenByHash(ctx context.Context, hash string) (*models.AuthenticationToken, error)
}

func (s *store) FindAuthenticationTokenByHash(ctx context.Context, hash string) (*models.AuthenticationToken, error) {
	ctx = mysql.WithQueryTableName(ctx, "authentication_tokens")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindAuthenticationTokenByHash")
	defer span.End()

	var token models.AuthenticationToken
	ex := s.resolver.ReadOnlyExecutorForTable("authentication_tokens")
	err := ex.GetContext(ctx, &token, `
		SELECT id, authenticatable_id, authenticatable_type, created_at, updated_at, expires_at_timestamp
		FROM authentication_tokens
		WHERE hashed_value = ?
	`, hash)

	s.trackFindResult(ctx, ex.ConnectionName(), "authentication_token_by_hash", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	return &token, nil
}

func (s *enterpriseStore) FindAuthenticationTokenByHash(ctx context.Context, hash string) (*models.AuthenticationToken, error) {
	return s.store.FindAuthenticationTokenByHash(ctx, hash)
}
