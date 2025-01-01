package data

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/pkg/errors"
)

type UpsertUserArgs struct {
	UserID UserID
	Login  string
	Type   v1.UserType
}

func (d *Data) HasUserContributions(ctx context.Context, userID UserID) (bool, error) {
	return pluckBool(d.db.Replica.QueryRowContext(ctx, `SELECT 1
 FROM tg_contributions
WHERE user_id = ?`, userID))
}

func (d *Data) HasUserCache(ctx context.Context, userID UserID) (bool, error) {
	return pluckBool(d.db.Replica.QueryRowContext(ctx, `SELECT 1
 FROM tg_users
WHERE user_id = ?`, userID))
}

func (d *Data) UpsertUser(ctx context.Context, args UpsertUserArgs) error {
	err := Upserter(ctx, d.db, stats.Tags{"table": "tg_users"}).
		Select(`SELECT 1
 FROM tg_users
WHERE BINARY login = ?
  AND type = ?
  AND user_id = ?`,
			args.Login,
			args.Type,
			args.UserID,
		).
		Update(`UPDATE tg_users
SET updated_at = NOW(), login = ?, type = ?
WHERE user_id = ?`,
			args.Login,
			args.Type,
			args.UserID,
		).
		Insert(`INSERT INTO tg_users (created_at, updated_at, login, type, user_id)
VALUES (NOW(), NOW(), ?, ?, ?)
ON DUPLICATE KEY
UPDATE
	updated_at = VALUES(updated_at),
	login = VALUES(login),
	type = VALUES(type)`,
			args.Login,
			args.Type,
			args.UserID,
		)

	return errors.Wrap(err, "upsert user failed")
}

func (d *Data) DeleteUser(ctx context.Context, userID UserID) error {
	res, err := d.db.Primary.ExecContext(ctx, "DELETE FROM tg_users WHERE user_id = ? LIMIT 1", userID)
	if err == nil && rowsAffected(res) > 0 {
		fromctx.Statter.Value(ctx).Counter("data.delete", stats.Tags{"table": "tg_users"}, rowsAffected(res))
		fromctx.Logger.Value(ctx).Info("deleted user", kvp.Uint64("gh.user.id", uint64(userID)))
	}
	return errors.Wrap(err, "failed to update user")
}
