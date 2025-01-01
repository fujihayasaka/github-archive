package chatops

import (
	"context"
	"fmt"

	crpc "github.com/github/go-chatops/v2"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/services/pbtypes"
)

func (app *Application) chatopWorkflowCancel(ctx context.Context, r *crpc.CommandRequest) (*crpc.CommandResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	// The id is optional so the chatop matches and we can then
	// provide useful feedback rather than "command not found"
	checkSuiteID := r.Params["id"]
	if checkSuiteID == "" {
		return &crpc.CommandResponse{Result: "Check Suite Global Relay ID required"}, nil
	}

	_, err := app.DeployerClient.WorkflowCancel(ctx, &deploy.WorkflowCancelRequest{
		CheckSuiteId: &pbtypes.Identity{GlobalId: checkSuiteID},
	})
	if err != nil {
		return &crpc.CommandResponse{Result: fmt.Sprintf("Error: %s", err)}, nil
	}

	return &crpc.CommandResponse{Result: fmt.Sprintf("The Workflow for Check Suite ID %s has been cancelled", checkSuiteID)}, nil
}
