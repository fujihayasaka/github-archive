package workflowbuild

import (
	"context"

	"github.com/github/launch/model"
)

type WorkflowFilter interface {
	ShouldRun(ctx context.Context, wf model.Workflow) bool
}
