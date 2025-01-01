package store

import (
	"context"
	"database/sql"
	"time"

	apimodels "github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/go-stats"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

// ProgrammaticAccessTokensStore store for looking up and acting on credentials issued by Authnd
type ProgrammaticAccessTokensStore interface {
	FindProgrammaticAccessTokenByHash(ctx context.Context, hashedToken string) (*models.ProgrammaticAccessToken, error)
	FindProgrammaticAccessTokenByID(ctx context.Context, id uint64) (*models.ProgrammaticAccessToken, error)
	FindProgrammaticAccessTokens(ctx context.Context, actorId int64, actorType string, accessId int64) ([]*models.ProgrammaticAccessToken, error)

	FindProgrammaticAccessTokensForRevokedNotification(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error)
	FindProgrammaticAccessTokensForIssuedNotification(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error)
	FindProgrammaticAccessTokensForExpiredNotification(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error)
	FindProgrammaticAccessTokensForExpirationWarningNotification(ctx context.Context, expiresInDays int64, lastID uint64, batch int64) ([]*models.ProgrammaticAccessToken, error)
	MarkEventForProgrammaticAccessTokens(ctx context.Context, ids []uint64) error
	BusinessIdForProgrammaticAccessToken(ctx context.Context, id uint64) (uint64, error)

	// InsertProgrammaticAccessToken inserts the provided token into the database.
	// The current value of token.ID is ignored.
	// If no error is returned, token.ID will be populated with the new token's ID.
	InsertProgrammaticAccessToken(ctx context.Context, token *models.ProgrammaticAccessToken) error
	RevokeProgrammaticAccessTokenByHash(ctx context.Context, hashedToken string) (apimodels.RevokeResult, error)
	RevokeProgrammaticAccessTokenByID(ctx context.Context, id uint64) (apimodels.RevokeResult, error)
}

// FindProgrammaticAccessTokenByHash finds programmatic_access_token by hashed token from authnd database.
func (s *store) FindProgrammaticAccessTokenByHash(ctx context.Context, hashedToken string) (*models.ProgrammaticAccessToken, error) {
	ctx = mysql.WithQueryTableName(ctx, "programmatic_access_tokens")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindProgrammaticAccessTokenByHash")
	defer span.End()

	var result models.ProgrammaticAccessToken
	ex := s.resolver.ReadOnlyExecutorForTable("programmatic_access_tokens")
	err := ex.GetContext(ctx, &result, `
	SELECT id, actor_id, actor_type, issued_at_utc, expires_at_utc, revoked_at_utc, last_event_at_utc, attributes, hashed_token, token_suffix, access_id FROM programmatic_access_tokens
	WHERE hashed_token=?
	LIMIT 1`, hashedToken)
	s.trackFindResult(ctx, ex.ConnectionName(), "programmatic_access_token_by_hash", timer, err)

	if err != nil {
		return nil, errors.WithStack(err)
	}

	return &result, nil
}

func (s *store) FindProgrammaticAccessTokenByID(ctx context.Context, id uint64) (*models.ProgrammaticAccessToken, error) {
	ctx = mysql.WithQueryTableName(ctx, "programmatic_access_tokens")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindProgrammaticAccessTokenByID")
	defer span.End()

	var result models.ProgrammaticAccessToken
	ex := s.resolver.ReadOnlyExecutorForTable("programmatic_access_tokens")
	err := ex.GetContext(ctx, &result, `
	SELECT id, actor_id, actor_type, issued_at_utc, expires_at_utc, revoked_at_utc, last_event_at_utc, attributes, hashed_token, token_suffix, access_id FROM programmatic_access_tokens
	WHERE id=?
	LIMIT 1`, id)
	s.trackFindResult(ctx, ex.ConnectionName(), "programmatic_access_token_by_id", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return &result, nil
}

// FindProgrammaticAccessTokens finds PrATs by the given attributes.
func (s *store) FindProgrammaticAccessTokens(ctx context.Context, actorId int64, actorType string, accessId int64) ([]*models.ProgrammaticAccessToken, error) {
	ctx = mysql.WithQueryTableName(ctx, "programmatic_access_tokens")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindProgrammaticAccessTokens")
	defer span.End()

	now := models.NullMysqlDateTimeFromTime(time.Now().UTC())
	query := `SELECT id, actor_id, actor_type, issued_at_utc, expires_at_utc, revoked_at_utc, last_event_at_utc, attributes, hashed_token, token_suffix, access_id FROM programmatic_access_tokens WHERE actor_id=? AND actor_type=? AND revoked_at_utc IS NULL AND (expires_at_utc IS NULL OR expires_at_utc > ?)`
	args := []interface{}{actorId, actorType, now}

	if accessId != 0 {
		query = `SELECT id, actor_id, actor_type, issued_at_utc, expires_at_utc, revoked_at_utc, last_event_at_utc, attributes, hashed_token, token_suffix, access_id FROM programmatic_access_tokens WHERE actor_id=? AND actor_type=? AND access_id=? AND revoked_at_utc IS NULL AND (expires_at_utc IS NULL OR expires_at_utc > ?)`
		args = []interface{}{actorId, actorType, accessId, now}
	}

	var tokens []*models.ProgrammaticAccessToken
	ex := s.resolver.ReadOnlyExecutorForTable("programmatic_access_tokens")
	err := ex.SelectContext(ctx, &tokens, query, args...)
	s.trackFindResult(ctx, ex.ConnectionName(), "find_programmatic_access_tokens", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return tokens, nil
}

// FindProgrammaticAccessTokenForRevokeNotification find PrATs for which a revoked notification hasn't been sent
func (s *store) FindProgrammaticAccessTokensForRevokedNotification(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
	ctx = mysql.WithQueryTableName(ctx, "programmatic_access_tokens")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindProgrammaticAccessTokensForRevokedNotification")
	defer span.End()

	now := time.Now()
	oneMinuteAgo := now.Add(-1 * time.Minute).UTC()
	revokedBeforeTime := models.NullMysqlDateTimeFromTime(oneMinuteAgo)

	var tokens []*models.ProgrammaticAccessToken
	ex := s.resolver.ReadOnlyExecutorForTable("programmatic_access_tokens")
	err := ex.SelectContext(ctx, &tokens, `
		SELECT id, actor_id, issued_at_utc, expires_at_utc, revoked_at_utc, last_event_at_utc, token_suffix, access_id FROM programmatic_access_tokens
		WHERE revoked_at_utc is NOT NULL AND
		revoked_at_utc < ? AND
		last_event_at_utc < revoked_at_utc AND
		id > ?
		LIMIT ?
		`, revokedBeforeTime, lastID, batchSize)
	s.trackFindResult(ctx, ex.ConnectionName(), "find_programmatic_access_tokens_for_revoked_notification", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return tokens, nil
}

// FindProgrammaticAccessTokenForIssuedNotification find PrATs for which a issued notification hasn't been sent
func (s *store) FindProgrammaticAccessTokensForIssuedNotification(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
	ctx = mysql.WithQueryTableName(ctx, "programmatic_access_tokens")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindProgrammaticAccessTokensForIssuedNotification")
	defer span.End()

	now := time.Now()
	oneMinuteAgo := now.Add(-1 * time.Minute).UTC()
	issuedBeforeTime := models.NullMysqlDateTimeFromTime(oneMinuteAgo)

	var tokens []*models.ProgrammaticAccessToken
	ex := s.resolver.ReadOnlyExecutorForTable("programmatic_access_tokens")
	err := ex.SelectContext(ctx, &tokens, `
		SELECT id, actor_id, issued_at_utc, expires_at_utc, revoked_at_utc, last_event_at_utc, token_suffix, access_id FROM programmatic_access_tokens
		WHERE last_event_at_utc IS NULL AND
		revoked_at_utc is NULL AND
		(
			expires_at_utc is NULL OR
			expires_at_utc > ?
		) AND
		issued_at_utc < ? AND
		id > ?
		LIMIT ?
		`, now, issuedBeforeTime, lastID, batchSize)
	s.trackFindResult(ctx, ex.ConnectionName(), "find_programmatic_access_tokens_for_issued_notification", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return tokens, nil
}

// FindProgrammaticAccessTokenForExpiredNotification find PrATs for which a expired notification hasn't been sent
func (s *store) FindProgrammaticAccessTokensForExpiredNotification(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
	ctx = mysql.WithQueryTableName(ctx, "programmatic_access_tokens")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindProgrammaticAccessTokensForExpiredNotification")
	defer span.End()

	now := models.NullMysqlDateTimeFromTime(time.Now().UTC())

	var tokens []*models.ProgrammaticAccessToken
	ex := s.resolver.ReadOnlyExecutorForTable("programmatic_access_tokens")
	err := ex.SelectContext(ctx, &tokens, `
		SELECT id, actor_id, issued_at_utc, expires_at_utc, revoked_at_utc, last_event_at_utc, token_suffix, access_id FROM programmatic_access_tokens
		WHERE
		revoked_at_utc is NULL AND
		expires_at_utc IS NOT NULL AND
		expires_at_utc < ? AND
		last_event_at_utc < expires_at_utc AND
		id > ?
		LIMIT ?
		`, now, lastID, batchSize)
	s.trackFindResult(ctx, ex.ConnectionName(), "find_programmatic_access_tokens_for_expired_notification", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return tokens, nil
}

// FindProgrammaticAccessTokenForExpirationWarningNotification find PrATs which will expire in the provided number of days
func (s *store) FindProgrammaticAccessTokensForExpirationWarningNotification(ctx context.Context, expiresInDays int64, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
	ctx = mysql.WithQueryTableName(ctx, "programmatic_access_tokens")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindProgrammaticAccessTokensForExpirationWarningNotification")
	defer span.End()

	day := 24 * time.Hour
	expiresBefore := time.Now().Add(time.Duration(expiresInDays) * day)

	var tokens []*models.ProgrammaticAccessToken
	ex := s.resolver.ReadOnlyExecutorForTable("programmatic_access_tokens")
	err := ex.SelectContext(ctx, &tokens, `
		SELECT id, actor_id, issued_at_utc, expires_at_utc, revoked_at_utc, last_event_at_utc, token_suffix, access_id FROM programmatic_access_tokens
		WHERE
		revoked_at_utc is NULL AND
		expires_at_utc IS NOT NULL AND
		expires_at_utc < ? AND
		last_event_at_utc < DATE_SUB(expires_at_utc, INTERVAL ? DAY) AND
		id > ?
		LIMIT ?
		`, expiresBefore, expiresInDays, lastID, batchSize)
	s.trackFindResult(ctx, ex.ConnectionName(), "find_programmatic_access_tokens_for_expiration_warning_notification", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return tokens, nil
}

// MarkEventForProgrammaticAccessTokens updates the last_event_at_utc column for PrATs with the provided IDs
func (s *store) MarkEventForProgrammaticAccessTokens(ctx context.Context, ids []uint64) error {
	ctx = mysql.WithQueryTableName(ctx, "programmatic_access_tokens")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.MarkEventForProgrammaticAccessTokens")
	defer span.End()

	// sqlx.In expands '(?)' clauses based on the number of elements in the matching slice
	query, args, err := sqlx.In(`
		UPDATE programmatic_access_tokens SET last_event_at_utc = ?
		WHERE id IN (?)`,
		models.NullMysqlDateTimeFromTime(time.Now().UTC()),
		ids,
	)
	if err != nil {
		return errors.WithStack(err)
	}

	ex := s.resolver.WriteExecutorForTable("programmatic_access_tokens")
	_, err = ex.ExecContext(ctx, query, args...)

	s.trackWriteResult(ctx, ex.ConnectionName(), "mark_event_for_programmatic_access_tokens", timer, err)
	if err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func (s *store) InsertProgrammaticAccessToken(ctx context.Context, token *models.ProgrammaticAccessToken) error {
	ctx = mysql.WithQueryTableName(ctx, "programmatic_access_tokens")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.InsertProgrammaticAccessToken")
	defer span.End()

	ex := s.resolver.WriteExecutorForTable("programmatic_access_tokens")
	result, err := ex.ExecContext(ctx, `
		INSERT INTO programmatic_access_tokens (hashed_token, token_suffix, actor_id, actor_type, access_id, issued_at_utc, expires_at_utc, revoked_at_utc, attributes)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		token.HashedToken,
		token.TokenSuffix,
		token.ActorID,
		token.ActorType,
		token.AccessID,
		token.IssuedAt,
		token.ExpiresAt,
		token.RevokedAt,
		token.Attributes,
	)

	s.trackWriteResult(ctx, ex.ConnectionName(), "insert_token", timer, err)
	if err != nil {
		return errors.WithStack(err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return errors.WithStack(err)
	}

	token.ID = uint64(id)

	return nil
}

func (s *store) RevokeProgrammaticAccessTokenByHash(ctx context.Context, hashedToken string) (apimodels.RevokeResult, error) {
	ctx = mysql.WithQueryTableName(ctx, "programmatic_access_tokens")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.RevokeProgrammaticAccessTokenByHash")
	defer span.End()

	ex := s.resolver.WriteExecutorForTable("programmatic_access_tokens")
	result, err := ex.ExecContext(ctx, `UPDATE programmatic_access_tokens SET revoked_at_utc = ? WHERE hashed_token = ? AND revoked_at_utc IS NULL`,
		models.NullMysqlDateTimeFromTime(time.Now().UTC()),
		hashedToken,
	)

	s.trackWriteResult(ctx, ex.ConnectionName(), "revoke_token_by_hash", timer, err)
	if err != nil {
		return apimodels.RevokeResult_Error, errors.WithStack(err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return apimodels.RevokeResult_Error, errors.WithStack(err)
	}

	// if no rows were affected, determine if the token was not found or if the token was already revoked
	if rowsAffected == 0 {
		var result int64
		ex := s.resolver.WriteExecutorForTable("programmatic_access_tokens")
		err := ex.GetContext(ctx, &result, `SELECT 1 FROM programmatic_access_tokens WHERE hashed_token = ? LIMIT 1`, hashedToken)
		if err != nil {
			if !errors.Is(err, sql.ErrNoRows) {
				return apimodels.RevokeResult_Error, errors.WithStack(err)
			}
			return apimodels.RevokeResult_NotFound, nil
		} else {
			return apimodels.RevokeResult_AlreadyRevoked, nil
		}
	}

	return apimodels.RevokeResult_Success, nil
}

func (s *store) RevokeProgrammaticAccessTokenByID(ctx context.Context, id uint64) (apimodels.RevokeResult, error) {
	ctx = mysql.WithQueryTableName(ctx, "programmatic_access_tokens")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.RevokeProgrammaticAccessTokenByID")
	defer span.End()

	ex := s.resolver.WriteExecutorForTable("programmatic_access_tokens")
	result, err := ex.ExecContext(ctx, `UPDATE programmatic_access_tokens SET revoked_at_utc = ? WHERE id = ? AND revoked_at_utc IS NULL`,
		models.NullMysqlDateTimeFromTime(time.Now().UTC()),
		id,
	)

	s.trackWriteResult(ctx, ex.ConnectionName(), "revoke_token_by_id", timer, err)
	if err != nil {
		return apimodels.RevokeResult_Error, errors.WithStack(err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return apimodels.RevokeResult_Error, errors.WithStack(err)
	}

	// if no rows were affected, determine if the token was not found or if the token was already revoked
	if rowsAffected == 0 {
		var result int64
		ex := s.resolver.WriteExecutorForTable("programmatic_access_tokens")
		err := ex.GetContext(ctx, &result, `SELECT 1 FROM programmatic_access_tokens WHERE id = ? LIMIT 1`, id)
		if err != nil {
			if !errors.Is(err, sql.ErrNoRows) {
				return apimodels.RevokeResult_Error, errors.WithStack(err)
			}
			return apimodels.RevokeResult_NotFound, nil
		} else {
			return apimodels.RevokeResult_AlreadyRevoked, nil
		}
	}

	return apimodels.RevokeResult_Success, nil
}

// do support these methods for enterprise store
func (s *enterpriseStore) FindProgrammaticAccessTokenByHash(ctx context.Context, hashedToken string) (*models.ProgrammaticAccessToken, error) {
	return s.store.FindProgrammaticAccessTokenByHash(ctx, hashedToken)
}

func (s *enterpriseStore) FindProgrammaticAccessTokenByID(ctx context.Context, id uint64) (*models.ProgrammaticAccessToken, error) {
	return s.store.FindProgrammaticAccessTokenByID(ctx, id)
}

func (s *enterpriseStore) FindProgrammaticAccessTokens(ctx context.Context, actorId int64, actorType string, accessId int64) ([]*models.ProgrammaticAccessToken, error) {
	return s.store.FindProgrammaticAccessTokens(ctx, actorId, actorType, accessId)
}

func (s *enterpriseStore) FindProgrammaticAccessTokensForRevokedNotification(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
	return s.store.FindProgrammaticAccessTokensForRevokedNotification(ctx, lastID, batchSize)
}

func (s *enterpriseStore) FindProgrammaticAccessTokensForIssuedNotification(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
	return s.store.FindProgrammaticAccessTokensForIssuedNotification(ctx, lastID, batchSize)
}

func (s *enterpriseStore) FindProgrammaticAccessTokensForExpiredNotification(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
	return s.store.FindProgrammaticAccessTokensForExpiredNotification(ctx, lastID, batchSize)
}

func (s *enterpriseStore) FindProgrammaticAccessTokensForExpirationWarningNotification(ctx context.Context, expiresInDays int64, lastID uint64, batch int64) ([]*models.ProgrammaticAccessToken, error) {
	return s.store.FindProgrammaticAccessTokensForExpirationWarningNotification(ctx, expiresInDays, lastID, batch)
}

func (s *enterpriseStore) MarkEventForProgrammaticAccessTokens(ctx context.Context, ids []uint64) error {
	return s.store.MarkEventForProgrammaticAccessTokens(ctx, ids)
}

func (s *enterpriseStore) InsertProgrammaticAccessToken(ctx context.Context, token *models.ProgrammaticAccessToken) error {
	return s.store.InsertProgrammaticAccessToken(ctx, token)
}

func (s *enterpriseStore) RevokeProgrammaticAccessTokenByHash(ctx context.Context, hashedToken string) (apimodels.RevokeResult, error) {
	return s.store.RevokeProgrammaticAccessTokenByHash(ctx, hashedToken)
}

func (s *enterpriseStore) RevokeProgrammaticAccessTokenByID(ctx context.Context, id uint64) (apimodels.RevokeResult, error) {
	return s.store.RevokeProgrammaticAccessTokenByID(ctx, id)
}
