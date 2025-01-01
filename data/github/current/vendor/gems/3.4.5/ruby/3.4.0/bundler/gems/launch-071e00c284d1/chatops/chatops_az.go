package chatops

import (
	"context"
	"fmt"

	crpc "github.com/github/go-chatops/v2"
	errs "github.com/pkg/errors"

	terrors "github.com/github/launch/types/errors"

	"github.com/github/launch/utils/cliutils"

	"github.com/github/launch/services/pb/deploy"
)

func (app *Application) chatopsAz(ctx context.Context, r *crpc.CommandRequest) (*crpc.CommandResponse, error) {
	app.Logger.Log(ctx, "received chatop: az")

	repo := r.Params["repo"]
	globalID := r.Params["global_id"]
	if repo == "" && globalID == "" {
		return nil, errs.New("repo or global ID required")
	}

	if repo != "" && globalID != "" {
		return nil, errs.New("pass only repo or global ID not both")
	}

	env, err := cliutils.ParseEnv(r.Params["env"])
	if err != nil {
		return nil, err
	}

	var output string

	if repo != "" {
		nwo, err := parseRepo(repo)

		if err != nil {
			return nil, err
		}

		nwoString := nwo.String()
		output = fmt.Sprintf("Sorry, use `.actions kusto nwo %s` instead", nwoString)
	}

	if globalID != "" {
		resp, err := app.DeployerClient.GetAZForGlobalIDChatops(ctx, &deploy.GetAZForGlobalIDChatopsRequest{
			GlobalRelayId: globalID,
			Env:           env,
		})

		if err == nil {
			output = getGlobalIDOutput(env, resp)
		} else if terrors.IsNotFoundError(err) {
			output = "The entity either doesn't exist or has no Actions usage."
		} else {
			return nil, err
		}
	}

	return &crpc.CommandResponse{Result: output}, nil
}

const azGlobalIDResult = `:actions-service: Actions Service details for %s in %s:
*GlobalID* %s
*Tenant Name* %s
*Tenant Id* %s
`

func getGlobalIDOutput(env string, resp *deploy.GetAZForGlobalIDChatopsResponse) string {
	return fmt.Sprintf(azGlobalIDResult,
		resp.GlobalID,
		env,
		resp.GlobalID,
		resp.AzTenantName,
		resp.AzTenantID,
	)
}
