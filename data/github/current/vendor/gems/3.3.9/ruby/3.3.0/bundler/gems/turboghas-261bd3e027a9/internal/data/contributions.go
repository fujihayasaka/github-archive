package data

import (
	"context"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

type UpsertContributionArgs struct {
	RepositoryID RepositoryID
	UserID       uint64
	PushedAt     sqltime.Time
	Email        []byte
}

func (d *Data) UpsertContribution(ctx context.Context, args UpsertContributionArgs) error {
	err := Upserter(ctx, d.db, stats.Tags{"table": "tg_contributions"}).
		Select(`SELECT 1
 FROM tg_contributions
WHERE pushed_at >= ?
  AND email = ?
  AND repository_id = ?
  AND user_id = ?`,
			args.PushedAt,
			args.Email,
			args.RepositoryID,
			args.UserID).
		Update(`UPDATE tg_contributions
SET pushed_at = GREATEST(pushed_at, ?), email = ?
WHERE repository_id = ? AND user_id = ?`,
			args.PushedAt,
			args.Email,
			args.RepositoryID,
			args.UserID).
		Insert(`INSERT INTO tg_contributions (created_at, pushed_at, email, repository_id, user_id)
VALUES (NOW(), ?, ?, ?, ?)
ON DUPLICATE KEY
UPDATE
	pushed_at = GREATEST(pushed_at, VALUES(pushed_at)),
	email = VALUES(email)`,
			args.PushedAt,
			args.Email,
			args.RepositoryID,
			args.UserID,
		)

	return errors.Wrap(err, "upsert contribution failed")
}
