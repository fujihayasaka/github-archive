// Package devicetokens implements a storage for mobile device tokens.
package devicetokens

import (
	"context"
	sqltypes "database/sql"
	"time"

	"github.com/Masterminds/squirrel"
	clockpkg "github.com/benbjohnson/clock"
	"github.com/jmoiron/sqlx"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
)

const maxTokensPerUser = 50

// Storage represents a storage for mobile device tokens.
type Storage interface {
	Get(ctx context.Context, userID int64) (Tokens, error)
	Set(ctx context.Context, userID int64, oauthAccessID int64, token string) (bool, error)
	Delete(ctx context.Context, userID int64, tokens ...string) error
	DeleteAll(ctx context.Context, userID int64) error
}

type storage struct {
	clock   clockpkg.Clock
	telem   *telemetry.Provider
	statter stats.Client
	dbWrite *sqlx.DB
	dbRead  *sqlx.DB
}

// NewStorage implements Storage to deal with device tokens
func NewStorage(clock clockpkg.Clock, telem *telemetry.Provider, statter stats.Client, db mysql.DB) Storage {
	return storage{
		clock:   clock,
		telem:   telem,
		statter: statter,
		dbWrite: db.Write,
		dbRead:  db.Read,
	}
}

func (s storage) Get(ctx context.Context, userID int64) (Tokens, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	return mysql.WithRetries(ctx, s.clock, s.telem, func(c context.Context) (Tokens, error) {
		sql, args, err := squirrel.Select("*").From("mobile_device_tokens").Where(squirrel.Eq{"user_id": userID}).ToSql()
		if err != nil {
			return nil, errors.Wrap(err, "failed to build select SQL query")
		}

		rows, err := s.dbRead.QueryContext(ctx, sql, args...)
		if err != nil {
			return nil, errors.Wrap(err, "failed to select device token from DB")
		}
		defer rows.Close()
		var tokens []Token
		for rows.Next() {
			var token sqlToken
			if err := rows.Scan(
				&token.ID,
				&token.UserID,
				&token.Service,
				&token.DeviceToken,
				&token.CreatedAt,
				&token.UpdatedAt,
				&token.DeviceName,
				&token.OauthAccessID,
			); err != nil {
				return nil, err
			}
			tokens = append(tokens, token.ToToken())
		}
		if err := rows.Close(); err != nil {
			return nil, err
		}
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return tokens, nil
	})
}

func (s storage) Set(ctx context.Context, userID, oauthAccessID int64, token string) (bool, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	return mysql.WithRetries(ctx, s.clock, s.telem, func(c context.Context) (bool, error) {
		t0 := time.Now()
		success := "true"
		set := "false"
		res, err := s.set(ctx, userID, oauthAccessID, token)
		if err != nil {
			success = "false"
		} else if res {
			set = "true"
		}
		s.statter.DistributionMs("device_tokens.set.time", stats.Tags{"success": success, "set": set}, time.Since(t0))
		return res, err
	})
}

func (s storage) set(ctx context.Context, userID, oauthAccessID int64, token string) (bool, error) {
	// Check whether the limit has been reached.
	// This validation is not transactional to avoid contention, but this means
	// that race conditions are possible and a user may be able to surpass the
	// limit as a result. This should be fine.
	var count int
	err := squirrel.Select("COUNT(*)").
		From("mobile_device_tokens").
		Where(squirrel.Eq{"user_id": userID}).
		RunWith(s.dbRead).
		ScanContext(ctx, &count)
	if err != nil {
		return false, errors.Wrap(err, "failed to count device tokens in DB")
	}

	ts := mysql.NewTimestamps(s.clock)
	var sqlOauthAccessID sqltypes.NullInt64
	if oauthAccessID != 0 {
		sqlOauthAccessID = sqltypes.NullInt64{Valid: true, Int64: oauthAccessID}
	}

	if count < maxTokensPerUser {
		// Both insert and update are OK.
		_, err = squirrel.Insert("mobile_device_tokens").
			Columns("user_id", "device_token", "oauth_access_id", "created_at", "updated_at").
			Values(userID, token, sqlOauthAccessID, ts.CreatedAt, ts.UpdatedAt).
			Suffix("ON DUPLICATE KEY UPDATE oauth_access_id = ?, updated_at = ?", sqlOauthAccessID, ts.UpdatedAt).
			RunWith(s.dbWrite).
			ExecContext(ctx)
		if err != nil {
			return false, errors.Wrap(err, "failed to insert the device token")
		}
	} else {
		// Only update is allowed.
		r, err := squirrel.Update("mobile_device_tokens").
			SetMap(map[string]interface{}{"oauth_access_id": sqlOauthAccessID, "updated_at": ts.UpdatedAt}).
			// NOTE(abeaumont): service is required by the index
			Where(squirrel.Eq{"user_id": userID, "device_token": token, "service": 0}).
			RunWith(s.dbWrite).
			ExecContext(ctx)
		if err != nil {
			return false, errors.Wrap(err, "failed to update the device token")
		}
		affected, err := r.RowsAffected()
		if err != nil {
			return false, errors.Wrap(err, "failed to validate the device token was updated")
		}
		switch affected {
		case 0:
			return false, nil
		case 1:
			return true, nil
		default:
			return false, errors.Newf("failed to update the device token: unexpected number of affected rows: %d", affected)
		}
	}

	return true, nil
}

func (s storage) Delete(ctx context.Context, userID int64, tokens ...string) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	_, err := mysql.WithRetries(ctx, s.clock, s.telem, mysql.ToCallback(func(c context.Context) error {
		t0 := time.Now()
		success := "true"
		err := s.delete(ctx, userID, tokens)
		if err != nil {
			success = "false"
		}
		s.statter.DistributionMs("device_tokens.delete.time", stats.Tags{"success": success}, time.Since(t0))
		return err
	}))
	return err
}

func (s storage) delete(ctx context.Context, userID int64, tokens []string) error {
	_, err := squirrel.Delete("mobile_device_tokens").
		// NOTE(abeaumont): service is required by the index
		Where(squirrel.Eq{"user_id": userID, "device_token": tokens, "service": 0}).
		RunWith(s.dbWrite).
		ExecContext(ctx)
	return err
}

func (s storage) DeleteAll(ctx context.Context, userID int64) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	_, err := mysql.WithRetries(ctx, s.clock, s.telem, mysql.ToCallback(func(c context.Context) error {
		t0 := time.Now()
		success := "true"
		err := s.deleteAll(ctx, userID)
		if err != nil {
			success = "false"
		}
		s.statter.DistributionMs("device_tokens.delete_all.time", stats.Tags{"success": success}, time.Since(t0))
		return err
	}))
	return err
}

func (s storage) deleteAll(ctx context.Context, userID int64) error {
	_, err := squirrel.Delete("mobile_device_tokens").Where(squirrel.Eq{"user_id": userID}).RunWith(s.dbWrite).ExecContext(ctx)
	return err
}
