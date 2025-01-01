package workflowinvoker

import (
	"context"
	"fmt"
	"regexp"
	"sort"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/launch/model"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/workflowparser"
)

// Prevent all CodeQL actions from being in required workflows
var nonAllowedActionsRegexes = []*regexp.Regexp{
	regexp.MustCompile(`^github\/codeql-action\/.*`),
}

// _except_ upload-sarif
var allowListedActions = []string{
	"github/codeql-action/upload-sarif@",
}

// ActionsAllowedByPolicy hits a twirp endpoint with the list of Actions and validates
// they are allowed to be used by this Repo.
//
// If not, an error is returned and shown to the user.
func (i *buildInvoker) ActionsAllowedByPolicy(ctx context.Context, errCtx *WorkflowStartErrorContext, repoID types.GlobalID, parsedWorkflow *workflowparser.Workflow) *WorkflowStartErr {
	if i.data.AllowsAllActions {
		return nil
	}

	actionsList := actionsToStrings(parsedWorkflow.GetActions())
	actionsPolicyInfo, err := i.ghTwirpClient.CheckActionsAllowedByPolicy(ctx, repoID, actionsList, false, parsedWorkflow.IsRequiredWorkflow())

	if err != nil {
		i.obs.Report(ctx, errors.Wrap(err, "error validating Action policy via twirp"))
		return NewWorkflowStartError(errCtx, err, validateActionAllowedErrType)
	}

	if actionsPolicyInfo.IsExecutionAllowed {
		return nil
	}

	userError := NewPermanentWorkflowStartError(errCtx, terrors.NewUserError(actionsPolicyInfo.PolicyErrorMessage), validateActionAllowedErrType)

	return userError
}

// CheckIfActionsAllowedByLaunch uses a predefined list of actions regexes to determine
// if those actions are allowed to be executed inside a workflow. This is currently
// needed for preventing CodeQL actions from getting executed inside required workflows
// ref: github/code-scanning#7196
// ref: codeql-core/issues#4323
//
// The list can also be extended for other cases when we want to block a particular
// action.
//
// If not allowed, an error is returned and shown to the user.
func (i *buildInvoker) CheckIfActionsAllowedByLaunch(_ context.Context, errCtx *WorkflowStartErrorContext, parsedWorkflow *workflowparser.Workflow) *WorkflowStartErr {
	if !parsedWorkflow.IsRequiredWorkflow() {
		return nil
	}

	nonAllowedActions := make([]string, 0)
	actionsList := actionsToStrings(parsedWorkflow.GetActions())
	for _, action := range actionsList {
		if !isAllowedAction(action) {
			nonAllowedActions = append(nonAllowedActions, action)
		}
	}

	// Ensure the list is sorted for consistent error messages
	sort.Strings(nonAllowedActions)

	if len(nonAllowedActions) == 0 {
		return nil
	}

	userErr := terrors.NewUserError(
		fmt.Sprintf(
			"The following actions are not allowed to be used inside a required workflow: %s",
			strings.Join(nonAllowedActions, ", "),
		),
	)
	return NewPermanentWorkflowStartError(errCtx, userErr, validateActionAllowedErrType)
}

func isAllowedAction(action string) bool {
	for _, allowListedAction := range allowListedActions {
		if strings.HasPrefix(action, allowListedAction) {
			return true
		}
	}

	for _, nonAllowedActionRegex := range nonAllowedActionsRegexes {
		if nonAllowedActionRegex.MatchString(action) {
			return false
		}
	}
	return true
}

func actionsToStrings(actions []*model.Action) []string {
	var actionUses []string

	for _, a := range actions {
		actionUses = append(actionUses, a.Uses.String())
	}

	return actionUses
}
