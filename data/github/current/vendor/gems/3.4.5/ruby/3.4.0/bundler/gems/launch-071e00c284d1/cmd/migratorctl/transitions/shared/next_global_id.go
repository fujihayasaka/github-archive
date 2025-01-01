package shared

import (
	"context"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/types"
)

func GetNextGlobalID(ctx context.Context, legacyOrNextGID string, entityNextID *types.GlobalID, twirpClient ghtwirp.Client) (types.GlobalID, error) {
	if entityNextID != nil {
		return *entityNextID, nil
	}

	return twirpClient.GetNextGlobalID(ctx, legacyOrNextGID)
}
