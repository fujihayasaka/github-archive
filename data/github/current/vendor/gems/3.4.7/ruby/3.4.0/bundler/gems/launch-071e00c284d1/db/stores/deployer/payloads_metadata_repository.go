package deployer

import (
	"context"
	"database/sql"

	"github.com/facebookgo/clock"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/utils/asql"
)

// PayloadMetadataRepository defines the interface for interactions with payloads metadata table
type PayloadMetadataRepository interface {
	Persist(ctx context.Context, workflowBuildID int64, storageAccountID int, version uint8) error
	Get(ctx context.Context, workflowBuildID int64) (*PayloadMetadata, bool, error)
}

type PayloadMetadata struct {
	StorageAccountID uint8
	Version          uint8
}

type PayloadMetadataStoreSQL struct {
	db     *asql.SQL
	clock  clock.Clock
	logger logger.Logger
	stats  statter.Statter
}

func NewPayloadMetadataStoreSQL(db *asql.SQL, log logger.Logger, stats statter.Statter, clock clock.Clock) PayloadMetadataRepository {
	return &PayloadMetadataStoreSQL{
		db:     db,
		clock:  clock,
		logger: log,
		stats:  stats,
	}
}

func (p *PayloadMetadataStoreSQL) Persist(ctx context.Context, workflowBuildID int64, storageAccountID int, version uint8) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `INSERT INTO workflow_payloads_metadata (workflow_build_id, created_at, storage_account_id, version) VALUES (?, ?, ?, ?)`

	now := p.clock.Now().UTC()

	_, err := p.db.ExecContextWith(
		ctx,
		query,
		asql.WithName("PersistPayloadMetadata"),
		workflowBuildID,
		now,
		storageAccountID,
		version,
	)
	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

func (p *PayloadMetadataStoreSQL) Get(ctx context.Context, workflowBuildID int64) (*PayloadMetadata, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	query := `SELECT storage_account_id, version FROM workflow_payloads_metadata WHERE workflow_build_id = ?`

	out := PayloadMetadata{}

	err := p.db.QueryScanWith(
		ctx,
		query,
		asql.WithName("GetPayloadMetadata"),
		asql.Params(workflowBuildID),
		&out.StorageAccountID,
		&out.Version,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, false, nil
		}

		return nil, false, tracing.RecordError(span, err)
	}

	return &out, true, nil
}
