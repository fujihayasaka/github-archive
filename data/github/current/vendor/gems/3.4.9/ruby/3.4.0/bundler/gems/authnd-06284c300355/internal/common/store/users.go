package store

import (
	"context"
	"fmt"

	"github.com/github/authnd/internal/api/tenancy"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

type UsersStore interface {
	FindUserByLogin(ctx context.Context, login string) (*models.User, error)
	FindUserByID(ctx context.Context, userID int64) (*models.User, error)
}

// FindUserByLogin finds user by login from authnd database.
func (s *store) FindUserByLogin(ctx context.Context, login string) (*models.User, error) {
	ctx = mysql.WithQueryTableName(ctx, "users")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindUserByLogin")
	defer span.End()

	var user models.User
	ex := s.resolver.ReadOnlyExecutorForTable("users")
	query := s.findUserByQuery(ctx, "login")
	err := ex.GetContext(ctx, &user, query, login)
	s.trackFindResult(ctx, ex.ConnectionName(), "users_by_login", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return &user, nil
}

// FindUserByID finds user by ID from authnd database.
func (s *store) FindUserByID(ctx context.Context, userID int64) (*models.User, error) {
	ctx = mysql.WithQueryTableName(ctx, "users")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindUserByID")
	defer span.End()

	var user models.User
	ex := s.resolver.ReadOnlyExecutorForTable("users")
	query := s.findUserByQuery(ctx, "id")
	err := ex.GetContext(ctx, &user, query, userID)
	s.trackFindResult(ctx, ex.ConnectionName(), "users_by_id", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return &user, nil
}

func (s *store) findUserByQuery(ctx context.Context, filterField string) string {
	selectFields := "id,login,bcrypt_auth_token,token_secret,suspended_at,disabled"

	if s.isProxima {
		return fmt.Sprintf("SELECT %s FROM users WHERE %s=? AND business_id = %d LIMIT 1", selectFields, filterField, tenancy.GetTenantContext(ctx).ID)
	}
	return fmt.Sprintf("SELECT %s FROM users WHERE %s=? LIMIT 1", selectFields, filterField)
}

// do support these methods for enterprise store
func (s *enterpriseStore) FindUserByLogin(ctx context.Context, login string) (*models.User, error) {
	return s.store.FindUserByLogin(ctx, login)
}

func (s *enterpriseStore) FindUserByID(ctx context.Context, userID int64) (*models.User, error) {
	return s.store.FindUserByID(ctx, userID)
}
