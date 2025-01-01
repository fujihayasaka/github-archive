package chatops

import (
	"context"
	"fmt"
	"strings"

	crpc "github.com/github/go-chatops/v2"
	"github.com/pkg/errors"

	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/cliutils"
)

func (app *Application) chatopsSchedules(ctx context.Context, r *crpc.CommandRequest) (*crpc.CommandResponse, error) {
	app.Logger.Log(ctx, "received chatop: schedules")

	switch cmd := r.Params["cmd"]; cmd {
	case "delete":
		return app.schedulesDelete(ctx, r)
	default:
		return nil, errors.Errorf("%q is not a known sub-command for schedules", cmd)
	}
}

func (app *Application) schedulesDelete(ctx context.Context, r *crpc.CommandRequest) (*crpc.CommandResponse, error) {
	env, err := cliutils.ParseEnv(r.Params["env"])
	if err != nil {
		return nil, err
	}

	nodeID := strings.TrimSpace(r.Params["target"])
	if nodeID == "" {
		return nil, errors.New("Repository node ID required")
	}

	// convert to a NextGlobalID if necessary
	globalID, err := app.GlobalIDMigrator.GetNextGlobalID(ctx, nodeID)
	if err != nil {
		return nil, err
	}

	req := launchtypes.DeleteSchedulesRequest{
		Environment:      env,
		RepositoryNodeId: types.IdentityFromGlobalID(globalID),
	}

	resp, err := app.DeployerClient.DeleteSchedules(ctx, &req)
	if err != nil {
		return nil, err
	}
	return &crpc.CommandResponse{Result: fmt.Sprintf("Success: Deleted %d scheduled workflows", resp.GetCount())}, nil
}
