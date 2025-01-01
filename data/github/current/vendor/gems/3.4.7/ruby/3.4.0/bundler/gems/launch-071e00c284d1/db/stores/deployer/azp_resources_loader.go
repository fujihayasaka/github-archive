package deployer

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/pkg/errors"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
)

type AzpResourcesLoader interface {
	GetByTenantID(ctx context.Context, tenantID string) (*AzpResource, bool, error)
	GetByGlobalID(ctx context.Context, id types.GlobalID, env string) (*TenantInfo, bool, error)
	GetByTenantName(ctx context.Context, tenantName string) (*AzpResourceByName, bool, error)
}

func NewAZPResourcesLoader(obs *observability.Observability, db *asql.SQL, gidMigrator GlobalIDMigrator) AzpResourcesLoader {
	return &azpResourcesLoader{
		obs:         obs,
		db:          db,
		gidMigrator: gidMigrator,
	}
}

type azpResourcesLoader struct {
	obs         *observability.Observability
	db          *asql.SQL
	gidMigrator GlobalIDMigrator
}

type AzpResource struct {
	EntityID    types.GlobalID
	TenantID    string
	Environment string
}

type AzpResourceByName struct {
	EntityID    types.GlobalID
	TenantID    string
	Environment string
}

type TenantInfo struct {
	TenantName           string
	TenantID             string
	PipelinesScaleUnitID types.ScaleUnitID
}
type RepoTenantInfo struct {
	LatestBuilds   []*WorkflowWithBuild
	RepoTenantName string
	RepoTenantID   string
}

type WorkflowWithBuild struct {
	BuildURL         string
	WorkflowFilePath string
	QueuedAt         *timestamp.Timestamp
	WorkflowBuildID  string
}

// GetByTenantID loads an azp resource by tenant_id if one is found. If no rows are found it returns false and no error.
func (r *azpResourcesLoader) GetByTenantID(ctx context.Context, tenantID string) (*AzpResource, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `
		SELECT 
			entity_id, 
			tenant_id, 
			environment
		FROM azp_resources
		WHERE tenant_id = ?
		LIMIT 1`

	out := AzpResource{}
	err := r.db.QueryScanWith(ctx, query,
		asql.WithName("GetByTenantID"),
		asql.Params(tenantID),
		&out.EntityID,
		&out.TenantID,
		&out.Environment,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, false, nil
		}

		return nil, false, tracing.RecordError(span, err)
	}
	return &out, true, nil
}

// GetByGlobalID loads an azp resource by global_id if one is found. If no rows are found it returns false and no error.
func (r *azpResourcesLoader) GetByGlobalID(ctx context.Context, id types.GlobalID, env string) (*TenantInfo, bool, error) {
	ti := &TenantInfo{}
	entityNextID, entityNextIDColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, id.String(), entityIDColumnName)
	if err != nil {
		return nil, false, errors.Wrap(err, "Failed to get next entity id and column for azpResourcesLoader")
	}
	err = r.db.QueryScanWith(ctx, fmt.Sprintf(`
		SELECT
			tenant_name,
			tenant_id,
			pipelines_scale_unit_id
		FROM azp_resources az
		WHERE az.%s = ?
			AND az.environment = ?
		LIMIT 1`, entityNextIDColumn),
		asql.WithName("GetAzTenantInfo"),
		asql.Params(entityNextID, env),
		&ti.TenantName,
		&ti.TenantID,
		&ti.PipelinesScaleUnitID,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, false, nil
		}
		return nil, false, err
	}
	return ti, true, nil
}

// GetByTenantName loads an azp resource by tenant_name if one is found. If no rows are found it returns false and no error.
func (r *azpResourcesLoader) GetByTenantName(ctx context.Context, tenantName string) (*AzpResourceByName, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const query = `SELECT entity_id, tenant_id, environment
		FROM azp_resources
		WHERE tenant_name = ?
		LIMIT 1`

	out := AzpResourceByName{}
	err := r.db.QueryScanWith(ctx, query,
		asql.WithName("GetByTenantName"),
		asql.Params(tenantName),
		&out.EntityID,
		&out.TenantID,
		&out.Environment,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, false, nil
		}

		return nil, false, tracing.RecordError(span, err)
	}
	return &out, true, nil
}
