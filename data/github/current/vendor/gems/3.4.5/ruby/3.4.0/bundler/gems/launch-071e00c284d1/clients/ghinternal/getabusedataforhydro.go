package ghinternal

import (
	"context"
	"net/http"

	"github.com/pkg/errors"

	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils"
)

type AbuseDataForHydro struct {
	OwnersByEntityID map[types.GlobalID]*hydroV0.BillingPlanOwner
}

type abuseDataResponse struct {
	OwnerByEntityID map[types.GlobalID]abuseOwnerInfo `json:"owners_by_id"`
}

type abuseOwnerInfo struct {
	PlanName   string `json:"plan_name"`
	ID         string `json:"id"`
	DatabaseID int64  `json:"database_id"`
	Name       string `json:"name"`
	Type       string `json:"type"`
}

func (c *ghclient) GetAbuseDataForHydro(ctx context.Context, entityIDs []types.GlobalID) (*AbuseDataForHydro, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	payload := struct {
		Ids []types.GlobalID `json:"ids"`
	}{
		Ids: entityIDs,
	}

	var parsed abuseDataResponse
	err := c.do(ctx, "GetAbuseDataForHydro", "POST", "internal/actions/abuse-batch-info", payload, &parsed, func(r *http.Response) (bool, error) {
		retryable := r.StatusCode >= 500
		if r.StatusCode >= 400 {
			return retryable, NewAPIError(r.StatusCode, r.Status)
		}
		return retryable, nil
	})
	if err != nil {
		return nil, err
	}

	ownersByID, err := mapOwnersByEntityID(entityIDs, parsed)
	if err != nil {
		return nil, errors.Wrap(err, "failed to map owners by ID")
	}

	return &AbuseDataForHydro{
		OwnersByEntityID: ownersByID,
	}, nil
}

// The global IDs returned by the Abuse API may not be in the same format
// as the entities sent.
// This could happen if Launch starts using next global IDs for entities before their ready date
func mapOwnersByEntityID(inputEntities []types.GlobalID, resp abuseDataResponse) (map[types.GlobalID]*hydroV0.BillingPlanOwner, error) {
	originalIDMap := make(map[types.GitHubEntity]types.GlobalID)
	for _, gid := range inputEntities {
		entity, err := types.NewGitHubEntity(gid)
		if err != nil {
			return nil, err
		}

		originalIDMap[entity] = gid
	}

	entityMap := make(map[types.GlobalID]types.GitHubEntity)
	for gid := range resp.OwnerByEntityID {
		entity, err := types.NewGitHubEntity(gid)
		if err != nil {
			return nil, err
		}

		entityMap[gid] = entity
	}

	ownersByID := make(map[types.GlobalID]*hydroV0.BillingPlanOwner, len(inputEntities))
	for entityID, owner := range resp.OwnerByEntityID {
		originalID, ok := originalIDMap[entityMap[entityID]]
		if !ok {
			return nil, errors.Errorf("failed to find original ID for entity %s", entityID)
		}

		ownersByID[originalID] = &hydroV0.BillingPlanOwner{
			GlobalId:   owner.ID,
			DatabaseId: owner.DatabaseID,
			Name:       owner.Name,
			PlanSku:    utils.GetHydroBillingPlanOwnerSKU(owner.PlanName),
			Type:       utils.GetHydroBillingPlanOwnerType(owner.Type),
			// Not set here
			TenantName: "",
		}
	}

	return ownersByID, nil
}
