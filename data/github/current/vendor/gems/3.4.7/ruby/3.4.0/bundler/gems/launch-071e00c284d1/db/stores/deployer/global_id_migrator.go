package deployer

import (
	"context"

	"github.com/pkg/errors"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/types"
	errutil "github.com/github/launch/types/errors"
)

type GlobalIDMigrator interface {
	GetNextGlobalID(ctx context.Context, legacyOrNextGID string) (types.GlobalID, error)
	GetNextGlobalIDAndColumnForQuery(ctx context.Context, legacyOrNextGID string, column string) (types.GlobalID, string, error)
	GetNextGlobalIDsAndColumnForQuery(ctx context.Context, legacyOrNextGIDs []string, column string) ([]types.GlobalID, string, error)
	IsFeatureEnabledForActor(ctx context.Context, flag string, featureFlagActorID types.GlobalID) bool
}

func NewGlobalIDMigrator(ghTwirpClient ghtwirp.Client) GlobalIDMigrator {
	return &globalIDMigrator{
		ghTwirpClient: ghTwirpClient,
	}
}

type globalIDMigrator struct {
	ghTwirpClient ghtwirp.Client
}

func (c *globalIDMigrator) GetNextGlobalID(ctx context.Context, legacyOrNextGID string) (types.GlobalID, error) {
	nextGlobalID, err := c.ghTwirpClient.GetNextGlobalID(ctx, legacyOrNextGID)
	if err != nil {
		if errutil.IsNotFoundError(err) {
			return types.NilGlobalID, errors.Wrap(err, "globalID not found")
		}
		return types.NilGlobalID, errors.Wrap(err, "could not get next global id")
	}
	return nextGlobalID, err
}

func (c *globalIDMigrator) GetNextGlobalIDAndColumnForQuery(ctx context.Context, legacyOrNextGID string, column string) (types.GlobalID, string, error) {
	nextColumn, ok := columnToNextColumn[column]
	if !ok {
		return types.NilGlobalID, "", errors.New("Invalid column name")
	}

	nextGlobalID, err := c.GetNextGlobalID(ctx, legacyOrNextGID)
	if err != nil {
		return types.NilGlobalID, "", err
	}
	return nextGlobalID, nextColumn, nil
}

// Get list of global IDs and column (used for excluding repos in GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs)
func (c *globalIDMigrator) GetNextGlobalIDsAndColumnForQuery(ctx context.Context, legacyOrNextGIDs []string, column string) ([]types.GlobalID, string, error) {
	nextColumn, ok := columnToNextColumn[column]
	if !ok {
		return nil, "", errors.New("Invalid column name")
	}

	nextGlobalIDsMap, allFound, err := c.ghTwirpClient.GetNextGlobalIDs(ctx, legacyOrNextGIDs)
	if err != nil {
		return nil, "", err
	}
	if !allFound {
		return nil, "", errors.New("Could not get all next global ids")
	}

	var nextGlobalIDs []types.GlobalID
	for _, nextID := range nextGlobalIDsMap {
		nextGlobalIDs = append(nextGlobalIDs, nextID)
	}

	return nextGlobalIDs, nextColumn, nil
}

func (c *globalIDMigrator) IsFeatureEnabledForActor(ctx context.Context, flag string, featureFlagActorID types.GlobalID) bool {
	if featureFlagActorID != types.NilGlobalID {
		return c.ghTwirpClient.IsFeatureEnabledForActor(ctx, flag, featureFlagActorID)
	}
	if c.ghTwirpClient.IsFeatureEnabledGlobally(ctx, flag) {
		return true
	}
	return false
}

var columnToNextColumn = map[string]string{
	// workflow_builds
	"check_suite_id":     "check_suite_next_id",
	"executing_actor_id": "executing_actor_next_id",
	"repository_id":      "repository_next_id",
	// workflow_build_executions
	"triggering_actor_id": "triggering_actor_next_id",
	// workflow_jobs
	"check_run_id": "check_run_next_id",
	// azp_resources
	"entity_id": "entity_next_id",
	// workflow_schedules
	"schedule_hash":      "schedule_next_hash",
	"repository_node_id": "repository_next_id",
	"actor_node_id":      "actor_next_id",
}
