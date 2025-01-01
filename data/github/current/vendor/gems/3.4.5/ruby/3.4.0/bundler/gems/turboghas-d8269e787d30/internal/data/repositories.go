package data

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/pkg/errors"
	"github.com/simon-engledew/sqlh"
)

func (d *Data) HasRepositoryContributions(ctx context.Context, repoID RepositoryID) (bool, error) {
	return pluckBool(d.db.Replica.QueryRowContext(ctx, `SELECT 1
 FROM tg_contributions
WHERE repository_id = ?`, repoID))
}

func (d *Data) HasRepositoryCache(ctx context.Context, repoID RepositoryID) (bool, error) {
	return pluckBool(d.db.Replica.QueryRowContext(ctx, `SELECT 1
 FROM tg_repositories
WHERE repository_id = ?`, repoID))
}

type UpsertRepositoryArgs struct {
	RepositoryID RepositoryID
	OwnerID      UserID
	Name         string
	Enabled      Feature
}

func (d *Data) UpsertRepository(ctx context.Context, args UpsertRepositoryArgs) error {
	err := Upserter(ctx, d.db, stats.Tags{"table": "tg_repositories"}).
		Select(`SELECT 1
 FROM tg_repositories
WHERE owner_id = ?
  AND BINARY name = ?
  AND enabled = ?
  AND repository_id = ?`,
			args.OwnerID,
			args.Name,
			args.Enabled,
			args.RepositoryID,
		).
		Update(`UPDATE tg_repositories
SET updated_at = NOW(), owner_id = ?, name = ?, enabled = ?
WHERE repository_id = ?`,
			args.OwnerID,
			args.Name,
			args.Enabled,
			args.RepositoryID,
		).
		Insert(`INSERT INTO tg_repositories (created_at, updated_at, owner_id, name, enabled, repository_id)
VALUES (NOW(), NOW(), ?, ?, ?, ?)
ON DUPLICATE KEY
UPDATE
	updated_at = VALUES(updated_at),
	owner_id = VALUES(owner_id),
	name = VALUES(name),
	enabled = VALUES(enabled)`,
			args.OwnerID,
			args.Name,
			args.Enabled,
			args.RepositoryID,
		)

	return errors.Wrap(err, "upsert repository failed")
}

func (d *Data) DeleteRepository(ctx context.Context, repositoryID RepositoryID) error {
	res, err := d.db.Primary.ExecContext(ctx, "DELETE FROM tg_repositories WHERE repository_id = ? LIMIT 1", repositoryID)

	if err == nil && rowsAffected(res) > 0 {
		fromctx.Statter.Value(ctx).Counter("data.delete", stats.Tags{"table": "tg_repositories"}, rowsAffected(res))
		fromctx.Logger.Value(ctx).Info("deleted repository", kvp.Uint64("gh.repo.id", uint64(repositoryID)))
	}

	return errors.Wrap(err, "failed to delete repository")
}

func (d *Data) GetEntityRepositories(ctx context.Context, entityID uint64, entityType v1.EntityType) ([]uint64, error) {
	var repo_ids []uint64

	repo_ids, err := sqlh.Pluck[uint64](d.db.Replica.QueryContext(ctx, `SELECT repository_id
FROM tg_entities
INNER JOIN tg_purchasers ON tg_entities.entity_type = tg_purchasers.entity_type AND tg_entities.entity_id = tg_purchasers.entity_id
INNER JOIN tg_repositories ON tg_repositories.owner_id = tg_purchasers.owner_id
WHERE tg_entities.entity_id = ? AND tg_entities.entity_type = ?`, entityID, entityType))

	return repo_ids, errors.Wrap(err, "failed to query repositories for entity")
}
