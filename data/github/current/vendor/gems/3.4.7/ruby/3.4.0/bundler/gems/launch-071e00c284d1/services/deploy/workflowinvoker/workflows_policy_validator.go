package workflowinvoker

import (
	"context"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/launch/model"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/workflowparser"
)

// WorkflowsAllowedByPolicy hits a twirp endpoint with the list of workflows and validates
// they are allowed to be used by this repo.
//
// If not, an error is returned and shown to the user.
func (i *buildInvoker) WorkflowsAllowedByPolicy(ctx context.Context, errCtx *WorkflowStartErrorContext, repoID types.GlobalID, parsedWorkflow *workflowparser.Workflow, wfs map[string]workflowparser.CalledWorkflow) *WorkflowStartErr {
	if i.data.AllowsAllActions {
		// actions and workflows use the same policy
		return nil
	}

	workflowList, err := workflowsToString(wfs, 0)
	if err != nil {
		err = errors.Wrap(err, "generating resolved paths for reusable workflows")
		i.obs.Report(ctx, err)
		return NewPermanentWorkflowStartError(errCtx, err, validateWorkflowsAllowedErrType)
	}

	workflowsPolicyInfo, err := i.ghTwirpClient.CheckWorkflowsAllowedByPolicy(ctx, repoID, workflowList, parsedWorkflow.IsRequiredWorkflow())
	if err != nil {
		i.obs.Report(ctx, errors.Wrap(err, "error validating workflow policy via twirp"))
		return NewWorkflowStartError(errCtx, err, validateWorkflowsAllowedErrType)
	}

	if workflowsPolicyInfo.IsExecutionAllowed {
		return nil
	}

	return NewPermanentWorkflowStartError(errCtx, terrors.NewUserError(workflowsPolicyInfo.PolicyErrorMessage), validateWorkflowsAllowedErrType)
}

func workflowsToString(wfs map[string]workflowparser.CalledWorkflow, depth int32) ([]string, error) {
	if depth > workflowparser.MaxWorkflowCallDepth {
		return nil, errors.New("max workflow call depth reached")
	}

	resolvedPaths := []string{}
	keys := make(map[string]bool)

	for _, wf := range wfs {
		if strings.HasPrefix(wf.Workflow.Path, model.LocalWorkflowPathPrefix) {
			// we should not allow omitted nwo to handle nested calling of workflows
			return nil, errors.New("workflow path is not resolved")
		}
		if _, ok := keys[wf.Workflow.Path]; !ok {
			keys[wf.Workflow.Path] = true
			resolvedPaths = append(resolvedPaths, wf.Workflow.Path)

			// call recursively
			if wf.Workflow.CalledWorkflows != nil {
				subResolvedPaths, err := workflowsToString(wf.Workflow.CalledWorkflows, depth+1)
				if err != nil {
					return nil, err
				}
				for _, path := range subResolvedPaths {
					if _, ok = keys[path]; !ok {
						resolvedPaths = append(resolvedPaths, path)
					}
				}
			}
		}
	}

	return resolvedPaths, nil
}
