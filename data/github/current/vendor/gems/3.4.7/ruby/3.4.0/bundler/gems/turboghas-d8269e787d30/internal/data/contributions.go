package data

import (
	"context"
	"encoding/hex"

	"github.com/simon-engledew/sqlh"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

type Commit string

func (s Commit) MarshalBinary() (data []byte, err error) {
	v, err := hex.DecodeString(string(s))
	if len(v) > 20 {
		return v, errors.New("commit too long")
	}
	return v, err
}

func (s *Commit) UnmarshalBinary(data []byte) error {
	*s = Commit(hex.EncodeToString(data))
	return nil
}

type UpsertContributionArgs struct {
	RepositoryID RepositoryID
	UserID       uint64
	PushedAt     sqltime.Time
	Email        []byte
	Commit       Commit
}

func (d *Data) UpsertContribution(ctx context.Context, args UpsertContributionArgs) error {
	// Select will check for any qualifying row so that we do not do more writes than are necessary
	// if Select returns a row we will not continue to update the data.
	// LEAST(1, DATEDIFF(pushed_at, ?))
	//   treat all rows in the future (> 1) the same by returning 1
	//   a row may be in the future because we are replaying old Hydro topics - in which case do not want to overwrite
	//    any new value we have had since
	//   if the row is in the past (< 0) then we do not want to select it, we want to update it instead
	// IF(email = ? AND commit = ?, 0, 1)
	//   if the email and commit match we are willing to accept a row from today (0) or the future (1)
	//   if they do not match, we are only willing to accept a row from the future (1)
	err := Upserter(ctx, d.db, stats.Tags{"table": "tg_contributions"}).
		Select(`SELECT 1
 FROM tg_contributions
WHERE LEAST(1, DATEDIFF(pushed_at, ?)) >= IF(email = ? AND commit = ?, 0, 1)
  AND repository_id = ?
  AND user_id = ?`,
			args.PushedAt,
			args.Email,
			sqlh.Binary(&args.Commit),
			args.RepositoryID,
			args.UserID).
		Update(`UPDATE tg_contributions
SET pushed_at = ?, email = ?, commit = ?
WHERE repository_id = ? AND user_id = ? AND DATEDIFF(pushed_at, ?) <= 0`,
			args.PushedAt,
			args.Email,
			sqlh.Binary(&args.Commit),
			args.RepositoryID,
			args.UserID,
			args.PushedAt).
		Insert(`INSERT INTO tg_contributions (created_at, pushed_at, email, commit, repository_id, user_id)
VALUES (NOW(), ?, ?, ?, ?, ?)
ON DUPLICATE KEY
UPDATE
	pushed_at = VALUES(pushed_at),
	email = VALUES(email),
	commit = VALUES(commit)`,
			args.PushedAt,
			args.Email,
			sqlh.Binary(&args.Commit),
			args.RepositoryID,
			args.UserID,
		)

	return errors.Wrap(err, "upsert contribution failed")
}
