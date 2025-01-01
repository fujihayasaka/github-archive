package workflowinvoker

import (
	"context"

	errs "github.com/pkg/errors"
	"github.com/shurcooL/githubv4"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	ghclient "github.com/github/launch/clients/github"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/types"
)

func CreateCheckSuite(ctx context.Context,
	client github.Client,
	workflowExecutionID types.WorkflowExecutionID,
	invocation Invocation,
	eventCommit types.WorkflowInvocationReference,
	checkoutCommit types.WorkflowInvocationReference,
	headRepositoryID types.GlobalID,
	workflowIdentifier,
	workflowFilePath string,
	triggerID types.GlobalID,
	rerequestable bool,
	workflowExecutionGraph string,
	annotations *[]github.CheckSuiteAnnotation,
	conclusion github.CheckSuiteConclusion,
	referencedWorkflows string,
	workflowFileCheckoutSHA types.CommitSha,
	workflowRunTreeID types.CommitSha,
	workflowFileRef types.GitRef,
) (*types.CheckSuiteState, error) {
	return createCheckSuite(
		ctx,
		client,
		workflowExecutionID,
		invocation,
		eventCommit,
		checkoutCommit,
		headRepositoryID,
		workflowIdentifier,
		workflowFilePath,
		triggerID,
		rerequestable,
		workflowExecutionGraph,
		annotations,
		conclusion,
		referencedWorkflows,
		workflowFileCheckoutSHA,
		workflowRunTreeID,
		workflowFileRef,
	)
}

func createCheckSuite(
	ctx context.Context,
	client github.Client,
	workflowExecutionID types.WorkflowExecutionID,
	invocation Invocation,
	eventCommit types.WorkflowInvocationReference,
	checkoutCommit types.WorkflowInvocationReference,
	headRepositoryID types.GlobalID,
	workflowIdentifier,
	workflowFilePath string,
	triggerID types.GlobalID,
	rerequestable bool,
	workflowExecutionGraph string,
	annotations *[]github.CheckSuiteAnnotation,
	conclusion github.CheckSuiteConclusion,
	referencedWorkflows string,
	workflowFileCheckoutSHA types.CommitSha,
	workflowRunTreeID types.CommitSha,
	workflowFileRef types.GitRef,
) (*types.CheckSuiteState, error) {
	if annotations == nil {
		annotations = &[]github.CheckSuiteAnnotation{}
	}
	// for display purpose, we differentiate between the actor who's
	// access level is used for execution, and the actor who's shown
	// as having requested the execution
	creatorActor := invocation.TriggeringActor
	req := github.CreateCheckSuiteRequest{
		WorkflowExecutionID:     workflowExecutionID,
		RepositoryID:            invocation.Target.RepositoryID,
		HeadSHA:                 eventCommit.CommitSHA,
		HeadRef:                 eventCommit.GitRef,
		HeadRepositoryID:        headRepositoryID,
		CreatorID:               creatorActor.ID,
		Rerequestable:           rerequestable,
		EventName:               invocation.Event.Name,
		EventAction:             invocation.Event.Action,
		Name:                    workflowIdentifier,
		ExplicitCompletion:      true,
		WorkflowName:            getWorkflowName(invocation),
		WorkflowFilePath:        workflowFilePath,
		Annotations:             *annotations,
		TriggerID:               triggerID,
		WorkflowExecutionGraph:  workflowExecutionGraph,
		Conclusion:              conclusion.String(),
		Visibility:              getVisibilityState(invocation),
		ReferencedWorkflows:     referencedWorkflows,
		WorkflowFileCheckoutSHA: workflowFileCheckoutSHA,
		WorkflowRunTreeID:       workflowRunTreeID,
		WorkflowFileRef:         workflowFileRef,
	}
	res, err := client.CreateCheckSuite(ctx, req)
	if err != nil {
		return nil, err
	}

	checkSuiteState, err := types.NewCheckSuiteState(
		invocation.Target.RepositoryID,
		eventCommit.CommitSHA,
		eventCommit.GitRef,
		checkoutCommit.CommitSHA,
		checkoutCommit.GitRef,
		headRepositoryID,
		workflowIdentifier,
		workflowFilePath,
		res.WorkflowRun.DatabaseID,
		res.WorkflowRun.RunNumber,
		triggerID,
		workflowFileRef,
	)
	if err != nil {
		return nil, err
	}

	checkSuiteState.CheckSuiteIDPair = res.CheckSuiteIDPair

	return checkSuiteState, nil
}

func updateCheckSuiteWithExecutionID(ctx context.Context, twirpClient ghtwirp.Client, checkSuiteState *types.CheckSuiteState, triggeringActorID types.GlobalID, executionID types.WorkflowExecutionID, attemptNum int64, executionGraph string, referencedWorkflows string) error {
	return twirpClient.CreateRerunExecution(ctx, &ghtwirp.RerunExecutionInput{
		RepositoryID:        checkSuiteState.RepositoryID,
		WorkflowRunID:       checkSuiteState.WorkflowRunID,
		ActorID:             triggeringActorID,
		PlanID:              executionID,
		Attempt:             attemptNum,
		ExecutionGraph:      executionGraph,
		ReferencedWorkflows: referencedWorkflows,
	})
}

func updateCheckSuiteWithAnnotations(ctx context.Context, client github.Client, checkSuiteState *types.CheckSuiteState, annotations []ghclient.CheckSuiteAnnotation) error {
	req := github.UpdateCheckSuiteRequest{
		RepositoryID: checkSuiteState.RepositoryID,
		CheckSuiteID: checkSuiteState.CheckSuiteIDPair.GlobalID,
		Annotations:  annotations,
	}
	res, err := client.UpdateCheckSuite(ctx, req)
	if err != nil {
		return errs.Wrap(err, "unable to update check suite with annotations")
	}
	if res == nil {
		return errs.New("ID pair not found in output, while updating check suite with annotations")
	}

	return nil
}

func getWorkflowName(invocation Invocation) string {
	if dynamicEvent, ok := invocation.Event.Ghe.(*flowevents.DynamicEvent); ok {
		return dynamicEvent.WorkflowName
	}

	return ""
}

func getVisibilityState(invocation Invocation) githubv4.CheckSuiteVisibility {
	if dynamicEvent, ok := invocation.Event.Ghe.(*flowevents.DynamicEvent); ok {
		return dynamicEvent.Visibility
	}

	return githubv4.CheckSuiteVisibilityDefault
}

func updateWorkflowRun(ctx context.Context, twirpClient ghtwirp.Client, checkSuiteState *types.CheckSuiteState, name string) error {
	return twirpClient.UpdateWorkflowRun(ctx, checkSuiteState.RepositoryID, checkSuiteState.WorkflowRunID, name)
}

func reusePreviousWorkflowRun(ctx context.Context,
	client github.Client,
	invocation Invocation,
	checkSuiteToClone types.GlobalID,
	triggerID types.GlobalID,
	eventCommit types.WorkflowInvocationReference,
	treeID types.CommitSha,
) (*github.ReusePreviousWorkflowRunResponse, error) {
	creatorActor := invocation.TriggeringActor

	req := github.ReusePreviousWorkflowRequest{
		RepositoryID:      invocation.Target.RepositoryID,
		CheckSuiteToClone: checkSuiteToClone,
		Event:             invocation.Event.Name,
		CreatorID:         creatorActor.ID,
		TriggerID:         triggerID,
		HeadSha:           eventCommit.CommitSHA,
		HeadBranch:        eventCommit.GitRef.TagOrHeadName(),
		TreeID:            treeID,
	}

	return client.ReusePreviousWorkflowRun(ctx, req)
}
