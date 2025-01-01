package deploy

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/github/go-kvp"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	errs "github.com/pkg/errors"
	"github.com/shurcooL/githubv4"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/processors/build"
	"github.com/github/launch/services/deploy/workflowinvoker"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	"github.com/github/launch/utils"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/workflowparser"
	"github.com/github/launch/workflowparser/executiongraph"
)

func (s *service) RunDynamicWorkflow(ctx context.Context, req *pb.RunDynamicWorkflowRequest) (*pb.RunDynamicWorkflowResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repoGID, err := s.GetGlobalIDFromIdentity(ctx, req.GetRepositoryId(), "RunDynamicWorkflow")
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}
	actorGID, err := s.GetGlobalIDFromIdentity(ctx, req.GetActorId(), "RunDynamicWorkflow")
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	ll := logger.AdaptToFieldLogger(ctx, s.cfg.Obs.Logger)
	ll.Info("RunDynamicWorkflow",
		kvp.String("gh.repo.global_id", repoGID.String()),
		kvp.String("gh.actor.global_id", actorGID.String()),
		kvp.String("gh.actor.login", req.GetActorLogin()),
		kvp.String("gh.launch.event.ref", req.GetRef()),
		kvp.String("gh.launch.event.commit_sha", req.GetSha()),
		kvp.String("gh.launch.workflow.content", req.GetWorkflow()),
		kvp.String("gh.launch.integration.name", req.GetIntegrationName()),
		kvp.String("gh.launch.workflow.name", req.GetWorkflowName()),
		kvp.String("gh.launch.slug", req.GetSlug()),
		kvp.Any("gh.check_suite.visibility", req.GetVisibility()),
		kvp.Int("gh.launch.workflow.inputs.count", len(req.GetInputs())),
	)

	executionID := types.NewRandomWorkflowExecutionID()
	ll.Debug("Received dynamic workflow", kvp.String("gh.launch.workflow.execution.id", executionID.String()))

	spammy, err := s.cfg.GithubTwirpClient.IsUserSpammy(ctx, actorGID)
	if err != nil {
		// Allow the run to continue if we failed to check spammy
		// Creating the check suite will fail if the user is spammy
		ll.Error("Failed to check if user is spammy, allowing dynamic run to continue",
			kvp.Err(err),
			kvp.String("gh.actor.global_id", actorGID.String()),
		)
	} else if spammy {
		ll.Info("Not running dynamic workflow for spammy user", kvp.String("gh.actor.global_id", actorGID.String()))
		return nil, tracing.RecordError(span, twirp.FailedPrecondition.Error("Not running dynamic workflow for spammy user"))
	}

	dynamicEvent := &flowevents.DynamicEvent{
		Ref:             req.GetRef(),
		Workflow:        req.GetWorkflow(),
		IntegrationName: req.GetIntegrationName(),
		Inputs:          req.GetInputs(),
		WorkflowName:    req.GetWorkflowName(),
		Slug:            req.GetSlug(),
		Visibility:      githubv4.CheckSuiteVisibility(req.GetVisibility().String()),
	}
	err = extendDynamicEventWithRepositoryDetails(ctx, dynamicEvent, repoGID, s.cfg.GithubTwirpClient)
	if err != nil {
		ll.Error("Failed to extend dynamic event with repository details", kvp.Err(err))
	}

	payloadJSON, err := json.Marshal(dynamicEvent)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	path := flowevents.BuildDynamicWorkflowFilePath(req.GetIntegrationName(), req.GetSlug())

	deliveryID := uuid.New().String()

	_, repoDatabaseID, err := repoGID.Decode()
	if err != nil {
		ll.Error("Failed to decode repository global ID", kvp.Err(err))
	}

	client, err := s.cfg.ClientFactory.NewClientForRepositoryOwnerDatabaseID(ctx, repoGID, req.GetOwnerId())
	if err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "failed to create github client for repository owner"))
	}

	ref := types.GitRef(req.GetRef())
	eventSHA, eventRef, err := client.ResolveRef(ctx, repoGID, ref)
	if err != nil {
		s.cfg.Obs.Logger.ErrorWithFields(
			ctx,
			"could not resolve ref for dynamic workflow",
			err,
			kvp.String("gh.repo.global_id", repoGID.String()),
			kvp.String("gh.launch.event.ref", req.GetRef()),
			kvp.String("gh.launch.integration.name", req.GetIntegrationName()))

		return nil, tracing.RecordError(span, errs.Wrap(err, "could not resolve ref for dynamic workflow"))
	}

	if ref.IsPullHeadRef() {
		if eventRef.IsZeroValue() {
			eventRef = ref
			ll.Info(
				"Dynamic workflow used pull head ref fallback",
				kvp.String("gh.launch.event.ref", eventRef.String()),
			)
		} else {
			ll.Info(
				"Dynamic workflow did not use pull head ref fallback",
				kvp.String("gh.launch.event.ref", eventRef.String()),
			)
		}
	}

	if req.GetSha() != "" {
		logFields := []kvp.Field{
			kvp.String("gh.launch.event.ref", eventRef.String()),
			kvp.String("gh.launch.event.commit_sha", req.GetSha()),
			kvp.String("gh.launch.resolved_commit.sha", eventSHA.String()),
		}

		if !types.IsCommitSha(req.GetSha()) {
			ll.Error("Invalid SHA requested for dynamic workflow", logFields...)
			return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("Invalid SHA"))
		}

		sha := types.CommitSha(req.GetSha())
		if sha.IsNullSha() {
			ll.Error("Null SHA requested for dynamic workflow", logFields...)
			return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("Null SHA"))
		}

		ll.Info("Dynamic workflow uses requested SHA over SHA resolved from ref", logFields...)
		eventSHA = sha
	}

	eventCommit := types.WorkflowInvocationReference{
		CommitSHA: eventSHA,
		GitRef:    eventRef,
	}

	githubTenant, err := ghtenant.GitHubTenantFromContext(ctx, s.IsMultiTenant)
	if err != nil {
		err = fmt.Errorf("error getting github tenant from context: %w", err)

		s.cfg.Obs.Logger.ErrorWithFields(
			ctx,
			"error getting github tenant from context",
			err,
			kvp.String("gh.repo.global_id", repoGID.String()),
			kvp.String("gh.launch.event.ref", req.GetRef()),
			kvp.String("gh.launch.integration.name", req.GetIntegrationName()))

		return nil, tracing.RecordError(span, err)
	}

	invocation := newInvocation(
		executionID,
		deliveryID,
		eventRef,
		eventSHA,
		payloadJSON,
		dynamicEvent,
		actorGID,
		req.GetActorLogin(),
		repoGID,
		repoDatabaseID,
		path,
		req.GetOwnerId(),
		githubTenant,
	)

	wfFtFlags := types.WorkflowFeatureFlags{}
	var wfSrc workflowparser.WorkflowSource
	ll.Debug("preparing resolver for callable workflows")
	metaResolve := workflowinvoker.NewRepositoryMetadataResolver(s.cfg.ClientFactory, s.cfg.AZPResources, actorGID, ll)

	// REVIEW:  Prefer twirp GetRepositoryOwners here?
	nwo, err := client.RepositoryNWO(ctx, repoGID)
	if err != nil {
		ll.Error("Failed to determine Repo Owner and Name (NWO)",
			kvp.Err(err),
			kvp.String("gh.repo.global_id", repoGID.String()))
	}

	callerRepo := &workflowinvoker.CallerRepo{
		NWO:        nwo,
		RepoID:     repoGID,
		DatabaseID: uint64(repoDatabaseID),
		Ref:        req.GetRef(),
		SHA:        eventSHA.String(),
	}
	wfSrc = s.cfg.WorkflowSourceFactory.Build(ctx, metaResolve, callerRepo, &invocation.Event, types.NilGlobalID, uuid.Nil)

	// Validate workflow
	runtimeHelper := utils.NewRuntimeHelper(s.IsEnterprise, s.EnterpriseVersion)
	_, actorID, err := actorGID.Decode()
	if err != nil {
		ll.Error("Failed to decode actor global ID", kvp.Err(err))
	}

	wf, err := verifyWorkflow(ctx, req.GetWorkflow(), wfFtFlags, wfSrc, runtimeHelper, actorID, s.cfg.Obs)
	if err != nil {
		ll.Debug("Invalid dynamic workflows received", kvp.Any("exception.message", err))
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("Invalid workflow: '%s'", err.Error()))
	}

	// Pre-Create check suite
	s.cfg.Log.Debug(ctx, "pre-creating check suite")

	graph, err := executiongraph.BuildExecutionGraph(wf)
	if err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "could not generate graph"))
	}

	referencedWorkflows, err := wf.BuildReferencedWorkflowsJSON()
	if err != nil {
		ll.Error("Failed to build referenced workflows JSON.", kvp.Err(err))
	}

	jsonGraph, err := json.Marshal(graph)
	if err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "could not serialize graph"))
	}

	// We don't actually need this for creating a check suite, so we pass an empty reference. This is only used
	// to create the check suite *state* returned by `CreateCheckSuite`, of which we only need the IDs
	checkoutCommit := types.WorkflowInvocationReference{}

	checkSuiteState, err := workflowinvoker.CreateCheckSuite(
		ctx,
		client,
		executionID,
		invocation,
		eventCommit,
		checkoutCommit,
		repoGID,
		wf.Name,
		path,
		types.NilGlobalID, // Do not pass a trigger ID for dynamic workflows
		true,              // Dynamic workflows are re-runnable
		string(jsonGraph),
		&[]github.CheckSuiteAnnotation{},
		github.NilCheckSuiteConclusion,
		referencedWorkflows,
		"",                       // This field is only needed for required workflows
		types.CommitShaZeroValue, // Dynamic workflow events not supported for reuse and to not need to save any tree_id information for the workflow run
		"",                       // This field is only needed for required workflows
	)
	if err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "could not pre-create check suite"))
	}

	ll.Debug(
		"pre-created check suite",
		kvp.Int64("gh.check_suite.id", checkSuiteState.CheckSuiteIDPair.DatabaseID),
		kvp.String("gh.check_suite.global_id", checkSuiteState.CheckSuiteIDPair.GlobalID.String()),
		kvp.Int64("gh.launch.workflow_run.id", checkSuiteState.WorkflowRunID),
	)

	// Add the ID of the pre-created check suite to the invocation in order to re-use it for error
	// scenarios
	invocation.PrecreatedCheckSuiteID = &checkSuiteState.CheckSuiteIDPair.GlobalID
	workflowRunID := checkSuiteState.WorkflowRunID

	job := build.Job{Invocation: invocation}
	payload, err := json.Marshal(job)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	aqJob := aqueduct.Job{App: s.cfg.AqueductApp, Queue: s.cfg.AqueductQueue, Payload: payload}

	installationValidAfter := req.GetInstallationValidAfter()
	if installationValidAfter != nil {
		now := time.Now().UTC()
		installationValid := installationValidAfter.AsTime()

		fields := []kvp.Field{
			kvp.String("gh.launch.workflow.execution.id", executionID.String()),
			kvp.Int64("gh.launch.workflow_run.id", checkSuiteState.WorkflowRunID),
			kvp.Time("gh.launch.installation_valid_after", installationValid),
			kvp.Time("gh.launch.event.time", now),
		}

		if now.Before(installationValid) {
			ll.Debug("Delaying dynamic workflow", fields...)
			aqJob.DeliverAt = installationValid
		} else {
			ll.Debug("Not delaying dynamic workflow, installation is already valid", fields...)
		}
	}

	_, err = s.cfg.AqueductClient.Send(ctx, aqJob)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	ll.Debug("Queued", kvp.String("gh.launch.workflow.execution.id", executionID.String()))
	s.cfg.Obs.Counter(ctx, "dynamic_workflow.queued", statter.Tags{
		"integration_name": req.GetIntegrationName(),
	}, 1)

	return &pb.RunDynamicWorkflowResponse{ExecutionId: executionID.String(), WorkflowRunId: workflowRunID}, nil
}

func verifyWorkflow(ctx context.Context, workflow string, wfFtFlags types.WorkflowFeatureFlags, wfSrc workflowparser.WorkflowSource, runtimeHelper *utils.RuntimeHelper, actorID int64, obs *observability.Observability) (*workflowparser.Workflow, error) {
	return workflowparser.ParseWithCalledWorkflows(ctx, types.ResolvedFile{
		Path:        flowevents.DynamicWorkflowFilePath,
		Text:        workflow,
		SHA:         "",
		IsTruncated: false,
	}, wfFtFlags, wfSrc, runtimeHelper, actorID, obs)
}

func newInvocation(
	executionID types.WorkflowExecutionID,
	deliveryID string,
	eventRef types.GitRef,
	eventSHA types.CommitSha,
	payloadJSON []byte,
	event flowevents.GitHubEvent,
	actorGlobalID types.GlobalID,
	actorLogin string,
	repoGlobalID types.GlobalID,
	repoID int64,
	workflowPath string,
	ownerDatabaseID int64,
	githubTenant ghtenant.GitHubTenant,
) workflowinvoker.Invocation {
	executingActor := workflowinvoker.NewActor(
		actorGlobalID,
		actorLogin,
	)
	triggeringActor := executingActor
	return workflowinvoker.NewInvocation(
		workflowinvoker.NewEvent(
			&deliveryID,
			eventRef,
			eventSHA,
			// We don't need the commit message for a dynamic workflow
			types.CommitMessageZeroValue,
			flowevents.Dynamic,
			"", // No action for dynamic run
			payloadJSON,
			time.Now().UTC(),
			time.Now().UTC(),
			event,
		),
		executingActor,
		triggeringActor,
		workflowinvoker.NewTarget(
			repoGlobalID,
			repoID,
			workflowinvoker.WorkflowSelector{
				Path:      &workflowPath,
				EventName: flowevents.Dynamic,
			},
			types.NilGlobalID,
			ownerDatabaseID,
			githubTenant,
		),
		workflowinvoker.WithExecutionID(executionID),
	)
}

func extendDynamicEventWithRepositoryDetails(ctx context.Context, event *flowevents.DynamicEvent, repoGID types.GlobalID, ghTwirpClient ghtwirp.Client) error {
	_, repoDatabaseID, err := repoGID.Decode()
	if err != nil {
		return errors.Wrap(err, "failed to decode repository global ID")
	}

	eventDetails, err := ghTwirpClient.GetRepositoryEventDetails(ctx, repoDatabaseID)
	if err != nil {
		return errors.Wrap(err, "failed to get repository event details")
	}

	var payload map[string]map[string]any
	if err := json.Unmarshal([]byte(eventDetails), &payload); err != nil {
		return errors.Wrap(err, "error unmarshalling event details")
	}

	if repo, ok := payload["repository"]; ok {
		event.Repository = repo
	}

	if org, ok := payload["organization"]; ok {
		event.Organization = org
	}

	if enterprise, ok := payload["enterprise"]; ok {
		event.Enterprise = enterprise
	}

	return nil
}
