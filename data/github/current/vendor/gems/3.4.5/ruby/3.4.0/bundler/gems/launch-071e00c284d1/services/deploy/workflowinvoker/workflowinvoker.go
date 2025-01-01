package workflowinvoker

import (
	"context"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/github/go-kvp"
	githubgo "github.com/google/go-github/v25/github"
	"github.com/google/uuid"
	"github.com/pkg/errors"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/pkg/launchconfig"
	ghactions "github.com/github/launch/proto/monolith/core/v1"
	"github.com/github/launch/utils/requiredworkflowutils"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/results"
	"github.com/github/launch/clients/runservice"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/model"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/logkeys"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/deploy/workflowinvoker/ctxkeys"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils"
	"github.com/github/launch/workerpool"
	"github.com/github/launch/workflowbuild/azp"
	"github.com/github/launch/workflowbuild/build"
	"github.com/github/launch/workflowparser"
)

//revive:disable-next-line:exported
type WorkflowInvokerFactory interface {
	Build(obs *Observability, inv Invocation, ghClient github.Client, ghTwirpClient ghtwirp.Client, errorHandler WorkflowStartErrHandler, runServiceClient runservice.Client, resultsClient results.Client) WorkflowInvoker
}

type workflowInvokerFactory struct {
	buildInvokerFactory   BuildInvokerFactory
	workflowSourceFactory WorkflowSourceFactory
	ghClientFactory       github.Factory
	azpResourcesRepo      deployer.AzpResourcesRepository
	tenantHandler         azp.TenantHandler
	env                   launchconfig.AppEnv
	provider              azp.WorkflowProvider
	filterer              azp.WorkflowFilterer
	appMode               launchconfig.AppMode
	isEnterprise          bool
	enterpriseVersion     string
	workers               workerpool.Workers
	sloReporter           *slometrics.Reporter
}

func NewWorkflowInvokerFactory(buildInvokerFactory BuildInvokerFactory, workflowSourceFactory WorkflowSourceFactory, ghClientFactory github.Factory, tenantHandler azp.TenantHandler, azpResourcesRepo deployer.AzpResourcesRepository, isLabEnvironment bool, provider azp.WorkflowProvider, filterer azp.WorkflowFilterer, workers workerpool.Workers, appMode launchconfig.AppMode, isEnterprise bool, enterpriseVersion string, sloReporter *slometrics.Reporter) WorkflowInvokerFactory {
	env := launchconfig.ProductionAppEnv
	if isLabEnvironment {
		env = launchconfig.LabAppEnv
	}
	return &workflowInvokerFactory{
		buildInvokerFactory:   buildInvokerFactory,
		workflowSourceFactory: workflowSourceFactory,
		ghClientFactory:       ghClientFactory,
		azpResourcesRepo:      azpResourcesRepo,
		tenantHandler:         tenantHandler,
		env:                   env,
		provider:              provider,
		filterer:              filterer,
		appMode:               appMode,
		isEnterprise:          isEnterprise,
		enterpriseVersion:     enterpriseVersion,
		workers:               workers,
		sloReporter:           sloReporter,
	}
}

func (f *workflowInvokerFactory) Build(obs *Observability, inv Invocation, ghClient github.Client, ghTwirpClient ghtwirp.Client, errorHandler WorkflowStartErrHandler, runServiceClient runservice.Client, resultsClient results.Client) WorkflowInvoker {
	return &workflowInvoker{
		buildInvokerFactory:   f.buildInvokerFactory,
		workflowSourceFactory: f.workflowSourceFactory,
		ghClientFactory:       f.ghClientFactory,
		azpResourcesRepo:      f.azpResourcesRepo,
		tenantHandler:         f.tenantHandler,
		env:                   f.env,
		provider:              f.provider,
		filterer:              f.filterer,
		appMode:               f.appMode,
		isEnterprise:          f.isEnterprise,
		enterpriseVersion:     f.enterpriseVersion,

		obs:              obs,
		ghClient:         ghClient,
		ghTwirpClient:    ghTwirpClient,
		inv:              inv,
		errorHandler:     errorHandler,
		workers:          f.workers,
		sloReporter:      f.sloReporter,
		runServiceClient: runServiceClient,
		resultsClient:    resultsClient,
	}
}

// WorkflowInvoker takes WorkflowInvocationData, runs various checks and then processes each build with a BuildInvoker
type WorkflowInvoker interface {
	Start(ctx context.Context, data *types.WorkflowInvocationData, isFinalAttempt bool) MultiWorkflowStartErr
}

type workflowInvoker struct {
	buildInvokerFactory   BuildInvokerFactory
	workflowSourceFactory WorkflowSourceFactory
	ghClientFactory       github.Factory
	azpResourcesRepo      deployer.AzpResourcesRepository
	tenantHandler         azp.TenantHandler
	env                   launchconfig.AppEnv
	provider              azp.WorkflowProvider
	filterer              azp.WorkflowFilterer
	appMode               launchconfig.AppMode
	isEnterprise          bool
	enterpriseVersion     string
	obs                   *Observability
	inv                   Invocation
	ghClient              github.Client
	ghTwirpClient         ghtwirp.Client
	errorHandler          WorkflowStartErrHandler
	workers               workerpool.Workers
	sloReporter           *slometrics.Reporter
	runServiceClient      runservice.Client
	resultsClient         results.Client
}

func (i *workflowInvoker) isEnterpriseAppMode() bool {
	return i.appMode == launchconfig.EnterpriseAppMode
}

//gocyclo:ignore
func (i *workflowInvoker) Start(ctx context.Context, data *types.WorkflowInvocationData, isFinalAttempt bool) MultiWorkflowStartErr {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	// Set Owner Values here.
	ctx = context.WithValue(ctx, ctxkeys.OwnerIDContextKey, data.Owner.GlobalID)

	// Ensure that panics are reported to the user as soon as we have enough info to create a check suite.
	// Note: panics from here on will result in this function returning (nil, nil), i.e no error
	defer i.errorHandler.handlePanic(ctx, data)

	ctx = withGitHubDataLogFields(ctx, data)
	addGitHubDataStatsTags(ctx, data)

	observability.LogStage(ctx, i.obs.Logger, logkeys.InvocationResolvedStage)

	// Holds information, so we can construct WorkflowStartErr and create failed check suites from them
	errCtx := NewWorkflowStartErrorContext(i.inv, data)

	workflows := i.provider.GetWorkflows(ctx, i.inv.Event.Name, i.inv.Event.Ghe, data)

	if i.shouldSkip(ctx, i.obs, workflows, data) {
		// i.shouldSkip tags status
		return nil
	}

	if data.IsActionsDisabledAtAnyLevel {
		tags := reqmeta.Tags{"status": "skipped", "skip_reason": "actions_allowed_none"}

		// We need to process required workflows even if actions has been disabled. Required workflows are filtered out in get_additional_workflows in dotcom if actions is disabled at the same level as the ruleset was created.
		requiredWorkflows := make([]types.ResolvedFile, 0)
		for _, wf := range workflows {
			if requiredworkflowutils.IsRequiredWorkflow(wf.Path) {
				requiredWorkflows = append(requiredWorkflows, types.ResolvedFile{
					Path:          wf.Path,
					Ref:           wf.Ref,
					SHA:           wf.SHA,
					Text:          wf.Text,
					IsTruncated:   wf.IsTruncated,
					RepositoryNwo: wf.RepositoryNwo,
					RepositoryID:  wf.RepositoryID,
				})
			}
		}

		if len(requiredWorkflows) == 0 {
			mw.TagStatsWith(ctx, tags)
			i.obs.Log(ctx, "Ignoring this event, because Actions has been disabled in the repo, org, or enterprise settings and no required workflows are present", kvp.String("gh.repo.name_with_owner", data.NWO.String()))
			return nil
		}

		i.obs.Log(ctx, "Filtering only required workflows if actions is disabled, but not at the level that the ruleset was created", kvp.String("gh.repo.name_with_owner", data.NWO.String()))
		workflows = requiredWorkflows
	}

	// As per a request from security, we are not currently running workflows for
	// events that run code from forks for private repositories.
	// See: https://github.com/github/dreamlifter/issues/542#issuecomment-504435785
	runForkCodeInBaseRepoContext := flowevents.IsRestrictedForkPREvent(i.inv.Event.Name, i.inv.Event.Ghe)
	if runForkCodeInBaseRepoContext {
		// Log that this is PR event coming from a fork and its fork policy settings
		ctx = ctxstash.WithFields(ctx,
			kvp.Bool("gh.launch.is_pr_from_fork", true),
			kvp.Bool("gh.launch.fork_should_run", data.ForkPRWorkflowsPolicy.ShouldRun()),
			kvp.Bool("gh.launch.fork_send_secrets", data.ForkPRWorkflowsPolicy.ShouldSendSecrets()),
			kvp.Bool("gh.launch.fork_send_write_token", data.ForkPRWorkflowsPolicy.ShouldSendWriteToken()),
			kvp.Bool("gh.launch.public_fork_send_variables", data.PublicForkPRWorkflowsPolicy.ShouldSendVariables()),
		)

		prEvent := i.inv.Event.Ghe.(flowevents.HasPullRequest)

		// User-defined policy may allow running fork PR workflows on private repos.
		if prEvent.GetRepo().GetPrivate() && !data.ForkPRWorkflowsPolicy.ShouldRun() {
			i.obs.Log(ctx, "skipping pull_request workflow from fork of private repo")
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "skipped", "skip_reason": "private_repo_fork"})
			return nil
		}
	}

	repoIDRes := NewRepositoryMetadataResolver(i.ghClientFactory, i.azpResourcesRepo, data.PlanOwner.GlobalID, logger.AdaptToFieldLogger(ctx, i.obs.Logger))
	callerRepo := &CallerRepo{
		NWO:        data.NWO,
		RepoID:     data.RepoGlobalID,
		DatabaseID: uint64(data.RepoDatabaseID),
		Ref:        data.References.CheckoutCommit.GitRef.String(),
		SHA:        data.References.CheckoutCommit.CommitSHA.String(),
	}
	wsExistingCheckSuiteID := types.NilGlobalID
	wsPreviousPlanID := uuid.Nil
	if i.inv.RerunInfo != nil && i.inv.ExistingCheckSuite.Backend == types.WorkflowBackendRunService {
		// Use the previous run attempt to resolve workflow refs to commit SHAs (4-9s partial re-runs only)
		wsExistingCheckSuiteID = i.inv.ExistingCheckSuite.CheckSuiteIDPair.GlobalID
		wsPreviousPlanID = uuid.UUID(i.inv.ExistingCheckSuite.ExecutionID)
	}
	var wfSrc = i.workflowSourceFactory.Build(ctx, repoIDRes, callerRepo, &i.inv.Event, wsExistingCheckSuiteID, wsPreviousPlanID)

	runtimeHelper := utils.NewRuntimeHelper(i.isEnterpriseAppMode(), i.enterpriseVersion)
	_, actorID, err := i.inv.ExecutingActor.ID.Decode()
	if err != nil {
		i.obs.Error(ctx, "Failed to decode actor global ID", kvp.Err(err))
	}

	parsedWorkflows, err := workflowparser.ParseWorkflows(ctx, workflows, data.WorkflowFeatureFlags, wfSrc, runtimeHelper, actorID, &i.obs.Observability)
	if err != nil {
		span.RecordError(err)
		return NewPermanentWorkflowStartError(errCtx, err, parserErrorErrType)
	}

	pathToCheckoutSHAMap := make(map[string]types.CommitSha)
	if len(parsedWorkflows.InvalidWorkflows) > 0 {
		for _, wf := range workflows {
			pathToCheckoutSHAMap[wf.Path] = types.CommitSha(wf.SHA)
		}
	}

	// Invalid workflows that were just pushed should publish a CheckSuite to notify the author of the problem.
	// For forked PRs also publish a CheckSuite for pull_request:synchronize events since there's no push event for the target repo.
	// Parse errors on other events are user_errors, but don't need reporting. This prevents invalid workflows from spamming CheckSuites for every event.
	//
	// If all workflows are invalid, we will exit after no workflows are found during planning.
	for fileReference, err := range parsedWorkflows.InvalidWorkflows {
		i.obs.Debug(ctx, "invalid workflow file", kvp.String("gh.launch.workflow.file_path", fileReference.Path), kvp.Err(err))
		if i.shouldNotifyInvalidWorkflow(fileReference.Path, runForkCodeInBaseRepoContext) {
			var workflowFileCheckoutSHA types.CommitSha
			if requiredworkflowutils.IsRequiredWorkflow(fileReference.Path) {
				workflowFileCheckoutSHA = pathToCheckoutSHAMap[fileReference.Path]
			}
			i.errorHandler.notifyInvalidWorkflow(ctx, fileReference.Path, err, data, &i.inv.Event, workflowFileCheckoutSHA)
		}
	}

	filter, err := i.filterer.GetWorkflowFilter(ctx, parsedWorkflows, i.inv.Event.Name, i.inv.Event.Ghe, i.ghClient)
	if err != nil {
		if terrors.IsNotFoundError(err) {
			i.obs.Error(ctx, "error generating workflow filter", kvp.Err(err))
			// Graphql errors for forked pull requests may be due to commit replication lag.
			// Return a retryable error, and rely on the aqueduct job being re-attempted.
			return NewWorkflowStartError(errCtx, err, filterFlowsErrType)
		}
		i.obs.Report(ctx, errors.Wrap(err, "could not generate workflow filter"))
		return NewPermanentWorkflowStartError(errCtx, err, filterFlowsErrType)
	}

	flow := parsedWorkflows.Flow()
	i.obs.Debug(ctx, "parsed flow", kvp.Int("gh.launch.parsed_workflows.count", len(flow.Workflows)))

	selectedWorkflows, err := i.inv.Target.WorkflowSelector.Select(flow)
	if err != nil {
		i.obs.Log(ctx, "could not plan given flow")
		return NewPermanentWorkflowStartError(errCtx, err, planningErrType)
	}

	i.obs.Debug(ctx, "workflows selected", kvp.Int("gh.launch.selected_workflows.count", len(selectedWorkflows)))

	if len(selectedWorkflows) == 0 {
		i.obs.Log(ctx, "no matching workflows found", kvp.String("gh.repo.name_with_owner", data.NWO.String()))
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "noop", "skip_reason": "noop"})
		return nil
	}

	i.obs.WorkflowMatchCompleted()

	if !data.FeatureFlags.IsActionsEligible {
		i.obs.Log(
			ctx,
			"workflow execution stopped due to being ineligible to run actions",
			kvp.String("gh.repo.name_with_owner", data.NWO.String()),
			kvp.String("gh.launch.executing_actor.id", string(i.inv.ExecutingActor.ID)),
		)

		ineligibleError := errors.New("The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings.")
		// If we receive an ineligible error in Proxima, it should not be considered a user error given they are all enterprise accounts and less likely to be mistake caused by a user.
		// Otherwise in production we should consider it a user error.
		// https://github.com/github/actions-relaunch/issues/841
		if !launchconfig.IsMultiTenant() {
			ineligibleError = terrors.NewUserError(ineligibleError.Error())
		}

		return NewPermanentWorkflowStartError(errCtx, ineligibleError, "isActionsEligible")
	}

	reportingMD, err := i.ghClient.GetReportingMetadata(ctx, i.inv.Target.RepositoryID, i.inv.ExecutingActor.ID)
	if err != nil {
		span.RecordError(err)
		return NewWorkflowStartError(errCtx, err, reportingMetadataErrType)
	}

	if shouldCheckReachability(&i.inv.Event) {
		commitOID := data.References.CheckoutCommit.CommitSHA
		reachable, err := assertReachability(ctx, i.obs, i.ghClient, i.inv.Target.RepositoryID, commitOID)
		if err != nil {
			err := errors.Wrap(err, "error checking commit reachability")
			span.RecordError(err)
			return NewWorkflowStartError(errCtx, err, reachabilityCheckErrType)
		}
		if !reachable {
			i.obs.Log(ctx, "commit not reachable")
			return NewPermanentWorkflowStartError(errCtx, terrors.NewUnreachableCommitError(commitOID), unreachableErrType)
		}
	}

	if err := i.checkIfValidActors(ctx, data, errCtx); err != nil {
		return err
	}

	vulnerable, err := i.isDependabotAssociatedRef(ctx, i.inv.Event.Name, i.inv.Event.Ghe)
	if err != nil {
		i.obs.Report(ctx, err)
		span.RecordError(err)
		return NewPermanentWorkflowStartError(errCtx, err, dependabotRefCheckErrType)
	}

	// Avoid supply chain attack. See https://github.com/github/c2c-actions/issues/3481.
	if vulnerable {
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "skipped", "skip_reason": "forked_dependabot_ref"})
		return nil
	}

	getOrCreateStart := time.Now().UTC()
	azpClient, repositoryTenants, outcome, err := i.tenantHandler.GetOrCreateTenants(ctx, i.inv.Target.RepositoryID, data.Owner.GlobalID, data.PlanOwner.GlobalID, data.NWO)
	mw.TagStatsWith(ctx, reqmeta.Tags{"outcome": string(outcome)})
	_, _ = i.obs.LogDurationWithoutCheckpoint(ctx, "org_acquisition_time", getOrCreateStart, thresholds.ResourceAcquisition, statter.Tags{
		"outcome": string(outcome),
		"context": "invoker",
	})

	if err != nil {
		span.RecordError(err)
		return NewWorkflowStartError(errCtx, err, getBackendErrType)
	}

	partialAbuseContext, err := i.buildPartialAbuseContext(
		ctx,
		i.inv.Event,
		data.Actor.GlobalID,
		data.Owner.GlobalID,
		data.PlanOwner.GlobalID,
		data.RepoGlobalID,
	)

	if err != nil {
		span.RecordError(err)
		return NewWorkflowStartError(errCtx, err, abuseContextErrType)
	}

	bi := i.buildInvokerFactory.Build(
		i.obs,
		azpClient,
		&reportingMD,
		i.ghClient,
		i.ghTwirpClient,
		data,
		i.inv,
		outcome,
		filter,
		repositoryTenants,
		i.errorHandler,
		wfSrc,
		partialAbuseContext,
		i.runServiceClient,
		i.resultsClient,
	)

	runFunc := func(fnCtx context.Context, workflow *model.Workflow) *WorkflowStartErr {
		fnCtx, span := tracing.StartWithOpFuncName(fnCtx, "FlowRun")
		defer span.End()
		parsedWorkflow, pathErr := parsedWorkflows.Find(workflow.FileReference)
		if pathErr != nil {
			err := errors.Wrap(err, "error getting parsed workflow from workflows")
			span.RecordError(err)
			return NewPermanentWorkflowStartError(errCtx, pathErr, "parsed_workflow_find_error")
		}

		return bi.Run(fnCtx, workflow, parsedWorkflow, isFinalAttempt)
	}

	var wg sync.WaitGroup
	errCh := make(chan *WorkflowStartErr, len(selectedWorkflows))

	for _, workflow := range selectedWorkflows {
		workflow := workflow

		wg.Add(1)
		go func() {
			defer wg.Done()

			if err := runFunc(ctx, workflow); err != nil {
				errCh <- err
			}
		}()
	}

	wg.Wait()
	close(errCh)

	i.obs.Debug(ctx, "workflow invocations complete",
		kvp.Int("gh.launch.selected_workflows", len(selectedWorkflows)),
		kvp.Int("gh.launch.error.count", len(errCh)))

	if len(errCh) > 0 {
		startErrs := make([]*WorkflowStartErr, 0, len(errCh))
		for startErr := range errCh {
			startErrs = append(startErrs, startErr)
		}

		return NewMultiWorkflowStartError(startErrs)
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{"status": "success"})
	return nil
}

func logInvocationLatency(ctx context.Context, obs *Observability, outcome deployer.OrgCreationOutcome) {
	var threshold time.Duration
	if outcome == deployer.OrgCreationSuccess {
		threshold = thresholds.WorkflowQueuedOrgSuccess
	} else {
		threshold = thresholds.WorkflowQueuedOrgUnnecessary
	}

	if _, err := obs.LogDuration(ctx, observability.AqJobRecvAtCheckpoint, "workflow.queued", threshold, statter.Tags{}); err != nil {
		obs.Report(ctx, errors.Wrap(err, "failed to log invocation latency"))
	}
}

func (i *workflowInvoker) shouldSkip(ctx context.Context, obs *Observability, workflows []types.ResolvedFile, data *types.WorkflowInvocationData) bool {
	if len(workflows) == 0 {
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "skipped", "skip_reason": "missing_empty_workflow_file"})
		obs.Log(ctx, "ignoring this event, because there are no active workflow files",
			kvp.String("gh.repo.name_with_owner", data.NWO.String()),
			kvp.String("gh.launch.workflow_files.commit_sha", data.References.CheckoutCommit.CommitSHA.String()))
		return true
	}

	// Action invocation blocked for orgs or users
	if data.Actor.ActionInvocationBlocked {
		obs.Counter(ctx, "workflow.invoker.actor_blocked", statter.Tags{"skipped": strconv.FormatBool(false)}, 1)
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "skipped", "skip_reason": "invocation_blocked"})
		obs.Log(ctx, "Ignoring this event, because action invocation has been blocked for the actor", kvp.String("gh.repo.name_with_owner", data.NWO.String()))
		return true
	}

	// Action invocation blocked for repositories
	if data.ActionInvocationBlocked {
		obs.Counter(ctx, "workflow.invoker.repo_blocked", statter.Tags{"skipped": strconv.FormatBool(false)}, 1)
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "skipped", "skip_reason": "repo_invocation_blocked"})
		obs.Log(ctx, "Ignoring this event, because action invocation has been blocked for the repository", kvp.String("gh.repo.name_with_owner", data.NWO.String()))
		return true
	}

	if i.env == launchconfig.LabAppEnv {
		if !data.FeatureFlags.LaunchLabEnabled {
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "skipped", "skip_reason": "launch_lab_disabled"})
			obs.Log(ctx, "ignoring this event, because launch_lab feature flag is not set for the repo", kvp.String("gh.repo.name_with_owner", data.NWO.String()))
			return true
		}
	}

	return false
}

func extractPRData(ctx context.Context, env build.RunEnvironment, event *InvokingEvent, target *invocationTarget) (build.RunEnvironment, types.GlobalID) {
	headRepositoryID := target.RepositoryID

	if prEvent, ok := event.Ghe.(*githubgo.PullRequestEvent); ok {
		env.BaseRef = types.GitRef(prEvent.GetPullRequest().GetBase().GetRef())
		env.HeadRef = types.GitRef(prEvent.GetPullRequest().GetHead().GetRef())

		headRepository := prEvent.GetPullRequest().GetHead().GetRepo()
		headRepositoryID = types.NewGlobalID(ctx, headRepository.GetNodeID())

		env.ForkedPullRequest = !target.RepositoryID.IsEquivalent(headRepositoryID)
		env.HeadRepositoryID = headRepositoryID
		env.HeadRepository = types.RepositoryFullName{
			Owner: headRepository.GetOwner().GetLogin(),
			Name:  headRepository.GetName(),
		}
		env.HeadRepositoryOwnerID = types.NewGlobalID(ctx, headRepository.GetOwner().GetNodeID())
	}

	return env, headRepositoryID
}

// DO NOT alter reachability checks without explicit review from @github/appsec
//
// See https://github.com/github/c2c-actions/issues/255 for context.
func shouldCheckReachability(event *InvokingEvent) bool {
	// We check reachability of deployment and registry package events, whose
	// commit SHAs are untrusted (they could be from a fork).
	if _, ok := event.Ghe.(flowevents.HasDeployment); ok {
		return true
	}

	if _, ok := event.Ghe.(*githubgo.RegistryPackageEvent); ok {
		return true
	}

	return false
}

func assertReachability(ctx context.Context, obs *Observability, client github.Client, repoGID types.GlobalID, commitSHA types.CommitSha) (bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	reachable, err := client.CheckCommitReachability(ctx, repoGID, commitSHA)
	if err != nil {
		return false, tracing.RecordError(span, errors.Wrap(err, "error determining commit reachability"))
	}

	logCommitReachability(ctx, obs, reachable)

	if reachable == nil {
		return false, tracing.RecordError(span, errors.New("unable to determine commit reachability"))
	}

	return *reachable, nil
}

func (i *workflowInvoker) checkIfValidActors(ctx context.Context, data *types.WorkflowInvocationData, errCtx *WorkflowStartErrorContext) MultiWorkflowStartErr {
	// Let's see if the Actor has been marked as spammy
	if data.Actor.IsSpammy {
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "skipped", "skip_reason": "spammy"})
		i.obs.Log(
			ctx,
			"workflow skipped as Actor is marked as spammy",
			kvp.String("gh.repo.name_with_owner", data.NWO.String()),
			kvp.String("gh.actor.global_id", string(data.Actor.GlobalID)),
		)
		userErr := terrors.NewUserError("Actions are disabled for this account. Please contact GitHub Support. https://github.com/contact")
		return NewPermanentWorkflowStartError(errCtx, userErr, "workflow_actor_spammy_error")
	}

	// Check if the Actor does not have a verified email address
	if !i.isEnterpriseAppMode() && data.Actor.NoVerifiedEmail {
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "skipped", "skip_reason": "noverifiedemail"})
		i.obs.Log(
			ctx,
			"workflow skipped as Actor does not have a verified email address",
			kvp.String("gh.repo.name_with_owner", data.NWO.String()),
			kvp.String("gh.actor.global_id", string(data.Actor.GlobalID)),
		)
		userErr := terrors.NewUserError("Please verify your email address to run GitHub Actions workflows. https://github.com/settings/emails")
		return NewPermanentWorkflowStartError(errCtx, userErr, "workflow_actor_noverifiedemail_error")
	}

	return nil
}

func logCommitReachability(ctx context.Context, obs *Observability, reachable *bool) {
	key := "commit_reachability"
	var gotResult bool
	var wasReachable bool

	if reachable != nil {
		gotResult = true
		wasReachable = *reachable
	}

	obs.Debug(ctx, key, kvp.Bool("gh.launch.commit_reachability.result", gotResult), kvp.Bool("gh.launch.commit_reachability.reachable", wasReachable))
	obs.Counter(ctx, key, statter.Tags{"got_result": strconv.FormatBool(gotResult), "was_reachable": strconv.FormatBool(wasReachable)}, 1)
}

// buildPartialAbuseContext queries dotcom for information about actors and starts to assemble the AbuseInfoForMMS
//
// Since this is being built at workflow invocation time to save twirp calls, some information won't be
// known until later, such as WorkflowExecutionID, and WorkflowFilePath.
func (i *workflowInvoker) buildPartialAbuseContext(
	ctx context.Context,
	event InvokingEvent,
	actorGID types.GlobalID,
	targetRepoOwnerGID types.GlobalID,
	billingPlanOwnerGID types.GlobalID,
	targetRepoGID types.GlobalID,
) (*types.PartialAbuseTriggerInfo, error) {

	if i.appMode == launchconfig.EnterpriseAppMode {
		return nil, nil
	}

	actors := []types.GlobalID{
		actorGID,
		targetRepoOwnerGID,
		billingPlanOwnerGID,
		targetRepoGID,
	}

	prEvent, isPullRequestBasedEvent := event.Ghe.(flowevents.HasPullRequest)

	var haveValidHeadPullRequest = false
	if isPullRequestBasedEvent {
		headRepo := prEvent.GetPullRequest().GetHead().GetRepo()
		headRepoOwnerGID := types.NewGlobalID(ctx, headRepo.GetOwner().GetNodeID())
		headRepoGID := types.NewGlobalID(ctx, headRepo.GetNodeID())
		if headRepo != nil {
			actors = append(actors, headRepoOwnerGID, headRepoGID)
			haveValidHeadPullRequest = true
		}
	}

	actorsInfo, err := i.ghTwirpClient.GetActorsInfo(ctx, actors)
	if err != nil {
		return nil, err
	}

	ai := actorsInfo.Actors

	for idx, a := range ai {
		if a.GetType() == ghactions.Actor_TYPE_INVALID {
			i.obs.Error(ctx, "incomplete abuse info because actor was unresolvable", kvp.String("gh.launch.unresolvable_global_id", actors[idx].String()))
		}
	}

	var headRepoAbuseUser *types.ActionsAbuseUser
	var headRepoAbuseRepo *types.ActionsAbuseRepository
	if isPullRequestBasedEvent && haveValidHeadPullRequest {
		headRepoAbuseUser = buildAbuseUser(ai[4])
		headRepoAbuseRepo = buildAbuseRepository(ai[5])
	}

	return &types.PartialAbuseTriggerInfo{
		TriggerEvent:       event.Name,
		TriggerEventAction: event.Action,
		Actor:              buildAbuseUser(ai[0]),
		TargetRepoOwner:    buildAbuseUser(ai[1]),
		BillingPlanOwner:   buildAbuseUser(ai[2]),
		TargetRepository:   buildAbuseRepository(ai[3]),
		HeadRepoOwner:      headRepoAbuseUser,
		HeadRepository:     headRepoAbuseRepo,
	}, nil
}

// Given an Actor assembles an ActionsAbuseUser
func buildAbuseUser(a *ghactions.Actor) *types.ActionsAbuseUser {
	if a.GetType() == ghactions.Actor_TYPE_INVALID {
		return nil
	}
	return &types.ActionsAbuseUser{
		ID:        a.GetGlobalId().GetGlobalId(),
		Name:      a.GetIdString(),
		Type:      mapAbuseActorType(a.GetType()),
		Plan:      a.GetPlanName(),
		CreatedAt: a.GetCreatedAt().AsTime(),
		IsHammy:   a.GetIsHammy().GetValue(),
	}
}

// Given an Actor assembles an ActionsAbuseRepository
func buildAbuseRepository(a *ghactions.Actor) *types.ActionsAbuseRepository {
	if a.GetType() == ghactions.Actor_TYPE_INVALID {
		return nil
	}
	return &types.ActionsAbuseRepository{
		ID:         a.GetGlobalId().GetGlobalId(),
		DatabaseID: a.GetId(),
		Private:    a.GetIsPrivate().GetValue(),
		NWO:        a.GetIdString(),
		CreatedAt:  a.GetCreatedAt().AsTime(),
	}
}

// Maps a raw Actor_TYPE to a usable value for Actions Service
func mapAbuseActorType(t ghactions.Actor_Type) string {
	// Should handle any actor type that could be returned from https://github.com/github/github/blob/master/app/api/internal/twirp/actions/core/v1/actors_dependency.rb
	switch t {
	case ghactions.Actor_TYPE_USER:
		return "User"
	case ghactions.Actor_TYPE_BUSINESS:
		return "Enterprise"
	case ghactions.Actor_TYPE_ORGANIZATION:
		return "Organization"
	case ghactions.Actor_TYPE_REPOSITORY:
		return "Repository"
	default:
		return ""
	}
}

// dependabotRefSubstr is used to avoid executing the Twirp call to dotcom in (*workflowInvoker).isDependabotAssociatedRef when the ref is not applicable.
// See https://github.com/github/c2c-actions/issues/3481#issuecomment-999073243 for more information. (Includes SQL query demonstrating that we can expect
// the substring dependabot to be present in all Dependabot-created branches.)
const dependabotRefSubstr = "dependabot"

// isDependabotAssociatedRef checks to make sure that Dependabot created branches are not executed in a
// trusted context by creating malicious forks.
func (i *workflowInvoker) isDependabotAssociatedRef(ctx context.Context, eventName string, ghe flowevents.GitHubEvent) (bool, error) {
	if eventName != flowevents.PullRequestTarget {
		return false, nil
	}

	prEvent := ghe.(flowevents.HasPullRequest)
	if !flowevents.IsForkPR(prEvent) {
		return false, nil
	}

	baseRef := types.GitRef(prEvent.GetPullRequest().GetBase().GetRef())
	if !strings.Contains(baseRef.String(), dependabotRefSubstr) {
		return false, nil
	}

	vulnerable, err := i.ghTwirpClient.IsDependabotAssociatedRef(ctx, i.inv.Target.RepositoryDatabaseID, baseRef.String())
	if err != nil {
		return false, err
	}

	if vulnerable {
		prNum := prEvent.GetPullRequest().GetNumber()
		i.obs.Error(ctx, "skipping pull_request_target workflow from fork because it is associated with dependabot indicating a potential supply-chain attack", kvp.Int("gh.pull_request.number", prNum))
	}

	return vulnerable, nil
}

func (i *workflowInvoker) shouldNotifyInvalidWorkflow(path string, runForkCodeInBaseRepoContext bool) bool {
	if i.inv.Event.Name == "push" {
		return true
	}

	if runForkCodeInBaseRepoContext && i.inv.Event.Action == "synchronize" {
		return true
	}

	// For non required workflows, we don't want to spam the repository by
	// creating a lot of check suites
	if !requiredworkflowutils.IsRequiredWorkflow(path) {
		return false
	}

	// To start with, for required workflows, we
	// report back the invalid workflow only for PR events.
	return i.inv.Event.Name == flowevents.PullRequest
}
