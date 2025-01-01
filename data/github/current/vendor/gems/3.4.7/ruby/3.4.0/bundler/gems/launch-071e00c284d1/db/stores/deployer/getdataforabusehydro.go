package deployer

import (
	"context"
	"fmt"

	errs "github.com/pkg/errors"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
)

type AbuseHydroDBData struct {
	EntityIDsToTenantIDs map[types.GlobalID]string
}

func (a *azpResourcesRepository) GetDataForAbuseHydro(ctx context.Context, tenantIDs []string) (*AbuseHydroDBData, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if len(tenantIDs) == 0 {
		return nil, errs.New("the list of tenants cannot be empty")
	}

	params := make([]any, 0, len(tenantIDs))
	for _, id := range tenantIDs {
		params = append(params, id)
	}
	query := fmt.Sprintf(`
		SELECT entity_id, tenant_name
		FROM azp_resources
		WHERE tenant_name IN (%s)
	`, mysqldb.Placeholders(len(tenantIDs)))
	rows, err := a.db.QueryContextWith(ctx, query, asql.WithName("GetDataForAbuseHydro"), params...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	res := &AbuseHydroDBData{
		EntityIDsToTenantIDs: make(map[types.GlobalID]string),
	}
	for rows.Next() {
		var entityID types.GlobalID
		var tenantName string
		err := rows.Scan(&entityID, &tenantName)
		if err != nil {
			return nil, err
		}
		res.EntityIDsToTenantIDs[entityID] = tenantName
	}

	if rows.Err() != nil {
		return nil, rows.Err()
	}

	return res, nil
}
