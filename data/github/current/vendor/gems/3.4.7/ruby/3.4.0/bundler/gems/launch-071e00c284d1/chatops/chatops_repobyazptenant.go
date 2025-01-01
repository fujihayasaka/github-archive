package chatops

import (
	"context"
	"fmt"

	crpc "github.com/github/go-chatops/v2"
	errs "github.com/pkg/errors"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/pb/deploy"
)

func (app *Application) chatopRepoByAZPTenant(ctx context.Context, r *crpc.CommandRequest) (*crpc.CommandResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	name := r.Params["name"]
	if name == "" {
		return nil, tracing.RecordError(span, errs.New("<name> cannot be empty"))
	}

	res, err := app.DeployerClient.RepoByAZPTenant(ctx, &deploy.RepoByAZPTenantRequest{
		Name: name,
	})
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return &crpc.CommandResponse{
		Result: getTemplatedRepoByAZPTenant(res),
	}, nil
}

func getTemplatedRepoByAZPTenant(res *deploy.RepoByAZPTenantResponse) string {
	return fmt.Sprintf(`
		RepositoryID: %s
		NWO: %s
		Environment: %s
	`, res.GetRepositoryId(), res.GetNwo(), res.GetEnv())
}
