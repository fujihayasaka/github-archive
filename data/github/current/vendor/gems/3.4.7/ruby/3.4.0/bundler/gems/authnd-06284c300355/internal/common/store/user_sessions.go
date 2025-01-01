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

type UserSessionsStore interface {
	FindUserSessionByID(ctx context.Context, SessionID int64) (*models.UserSession, error)
}

// FindSessionByID finds user session by ID from authnd database.
func (s *store) FindUserSessionByID(ctx context.Context, sessionID int64) (*models.UserSession, error) {
	ctx = mysql.WithQueryTableName(ctx, "user_sessions")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindUserSessionByID")
	defer span.End()

	var session models.UserSession
	ex := s.resolver.ReadOnlyExecutorForTable("user_sessions")
	err := ex.GetContext(ctx, &session, "SELECT id,user_id,accessed_at,revoked_at,expires_at,impersonator_session_id FROM user_sessions WHERE id=? LIMIT 1", sessionID)
	s.trackFindResult(ctx, ex.ConnectionName(), "session_by_id", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return &session, nil
}

// Not implemented in enterprise store
func (s *enterpriseStore) FindUserSessionByID(ctx context.Context, SessionID int64) (*models.UserSession, error) {
	return nil, errors.New("not implemented")
}
