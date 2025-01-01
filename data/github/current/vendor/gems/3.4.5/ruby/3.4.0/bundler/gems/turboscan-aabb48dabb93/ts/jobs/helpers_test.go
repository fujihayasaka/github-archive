package jobs_test

import (
	"context"

	oldtshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
	"github.com/github/turboscan/ts"
)

const (
	repoID        = ts.RepositoryEID(1)
	workflowRunID = ts.WorkflowRunEID(123)
)

type hydroPublisherStub struct{}

func (h hydroPublisherStub) CodeqlRunEvent(ctx context.Context, run *oldtshydro.CodeqlRun) error {
	return nil
}
