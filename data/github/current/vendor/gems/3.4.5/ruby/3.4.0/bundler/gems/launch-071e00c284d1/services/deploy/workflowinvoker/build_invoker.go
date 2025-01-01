package workflowinvoker

import (
	"context"
	"fmt"
	"runtime/debug"
	"strconv"
	"strings"
	"time"

	twirpv1 "github.com/github/actions-proto/gen/go/run-service/api/twirp/v1"
	parser "github.com/github/actions-workflow-parser/go"
	"github.com/github/actions-workflow-parser/go/template"
	"github.com/github/go-kvp"
	githubgo "github.com/google/go-github/v25/github"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"
	"github.com/github/launch/pkg/rate"

	"github.com/github/launch/clients/earthsmoke"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	ghclient "github.com/github/launch/clients/github"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/clients/results"
	"github.com/github/launch/clients/runservice"
	cu "github.com/github/launch/clients/utils"
	"github.com/github/launch/clients/varz"
	customerlabels "github.com/github/launch/config/customerlabels"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/model"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	azpclient "github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/expressions"
	"github.com/github/launch/pkg/globalidmigration"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/tiers"
	"github.com/github/launch/pkg/wfparser"
	"github.com/github/launch/services/auth/hkdf"

	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/requiredworkflowutils"
	"github.com/github/launch/workflowbuild"
	"github.com/github/launch/workflowbuild/azp/azperrors"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowbuild/build"
	"github.com/github/launch/workflowparser"
	"github.com/github/launch/workflowparser/executiongraph"
)

const (
	triggerDeleted        = "deleted"
	triggerTransferred    = "transferred"
	planTypeBusiness      = "Business"
	ownerTypeOrganisation = "Organization"
	planTypeFreeOrg       = "free_organization"
)

type BuildInvokerFactory interface {
	Build(
		obs *Observability,
		azpClient azpclient.RepositoryClient,
		workflowMetadata *metadata.WorkflowMetadata,
		ghClient ghclient.Client,
		ghTwirpClient ghtwirp.Client,
		data *types.WorkflowInvocationData,
		invocation Invocation,
		outcome deployer.OrgCreationOutcome,
		filter workflowbuild.WorkflowFilter,
		repositoryTenants *types.RepositoryTenants,
		errorHandler WorkflowStartErrHandler,
		workflowSource workflowparser.WorkflowSource,
		partialAbuseContext *types.PartialAbuseTriggerInfo,
		runServiceClient runservice.Client,
		resultsClient results.Client,
	) BuildInvoker
}

type buildInvokerFactory struct {
	appEnv                launchconfig.AppEnv
	tokenFactory          workflowbuild.TokenFactory
	repo                  deployer.WorkflowBuildsRepository
	actionsAppGlobalID    string
	dependabotAppGlobalID string
	kredzClient           kredz.Client
	varzClient            varz.Client
	secretDecryptor       earthsmoke.Decryptor
	keyGenerator          hkdf.KeyGenerator
	receiverURL           string
	receiverInternalURL   string
	receiverPublicURL     string
	resultsReceiverURL    string
	urlProviderFactory    cu.URLProviderFactory
	sloReporter           *slometrics.Reporter
	labeler               customerlabels.CustomerLabeler
	isEnterprise          bool
	enterpriseVersion     string
	queueBuildRateLimiter rate.RateLimiter
}

func NewBuildInvokerFactory(
	appEnv launchconfig.AppEnv,
	tokenFactory workflowbuild.TokenFactory,
	repo deployer.WorkflowBuildsRepository,
	actionsAppGlobalID string,
	dependabotAppGlobalID string,
	kredzClient kredz.Client,
	varzClient varz.Client,
	secretDecryptor earthsmoke.Decryptor,
	keyGenerator hkdf.KeyGenerator,
	receiverURL string,
	receiverInternalURL string,
	receiverPublicURL string,
	resultsReceiverURL string,
	urlProviderFactory cu.URLProviderFactory,
	sloReporter *slometrics.Reporter,
	labeler customerlabels.CustomerLabeler,
	isEnterprise bool,
	enterpriseVersion string,
	queueBuildRateLimiter rate.RateLimiter,
) BuildInvokerFactory {
	return &buildInvokerFactory{
		appEnv:                appEnv,
		tokenFactory:          tokenFactory,
		repo:                  repo,
		actionsAppGlobalID:    actionsAppGlobalID,
		dependabotAppGlobalID: dependabotAppGlobalID,
		kredzClient:           kredzClient,
		varzClient:            varzClient,
		secretDecryptor:       secretDecryptor,
		keyGenerator:          keyGenerator,
		receiverURL:           receiverURL,
		receiverInternalURL:   receiverInternalURL,
		receiverPublicURL:     receiverPublicURL,
		resultsReceiverURL:    resultsReceiverURL,
		urlProviderFactory:    urlProviderFactory,
		sloReporter:           sloReporter,
		labeler:               labeler,
		isEnterprise:          isEnterprise,
		enterpriseVersion:     enterpriseVersion,
		queueBuildRateLimiter: queueBuildRateLimiter,
	}
}

func (b *buildInvokerFactory) Build(
	obs *Observability,
	azpClient azpclient.RepositoryClient,
	workflowMetadata *metadata.WorkflowMetadata,
	ghClient ghclient.Client,
	ghTwirpClient ghtwirp.Client,
	data *types.WorkflowInvocationData,
	invocation Invocation,
	outcome deployer.OrgCreationOutcome,
	filter workflowbuild.WorkflowFilter,
	repositoryTenants *types.RepositoryTenants,
	errorHandler WorkflowStartErrHandler,
	workflowSource workflowparser.WorkflowSource,
	partialAbuseContext *types.PartialAbuseTriggerInfo,
	runServiceClient runservice.Client,
	resultsClient results.Client,
) BuildInvoker {
	return &buildInvoker{
		obs:               obs,
		azpClient:         azpClient,
		workflowMetadata:  workflowMetadata,
		ghClient:          ghClient,
		ghTwirpClient:     ghTwirpClient,
		data:              data,
		invocation:        invocation,
		outcome:           outcome,
		filter:            filter,
		repositoryTenants: repositoryTenants,
		errorHandler:      errorHandler,
		workflowSource:    workflowSource,
		runServiceClient:  runServiceClient,
		resultsClient:     resultsClient,

		appEnv:                b.appEnv,
		tokenFactory:          b.tokenFactory,
		repo:                  b.repo,
		actionsAppGlobalID:    b.actionsAppGlobalID,
		dependabotAppGlobalID: b.dependabotAppGlobalID,
		kredzClient:           b.kredzClient,
		varzClient:            b.varzClient,
		secretDecryptor:       b.secretDecryptor,
		keyGenerator:          b.keyGenerator,
		receiverURL:           b.receiverURL,
		receiverInternalURL:   b.receiverInternalURL,
		receiverPublicURL:     b.receiverPublicURL,
		resultsReceiverURL:    b.resultsReceiverURL,
		urlProviderFactory:    b.urlProviderFactory,
		reporter:              b.sloReporter,
		labeler:               b.labeler,
		isEnterprise:          b.isEnterprise,
		enterpriseVersion:     b.enterpriseVersion,
		partialAbuseContext:   partialAbuseContext,
		queueBuildRateLimiter: b.queueBuildRateLimiter,
	}
}

// BuildInvoker takes a single build (defined by one workflow file) and queues it with Action Service
type BuildInvoker interface {
	Run(ctx context.Context, workflow *model.Workflow, parsedWorkflow *workflowparser.Workflow, isFinalAttempt bool) *WorkflowStartErr
}

type buildInvoker struct {
	obs               *Observability
	azpClient         azpclient.RepositoryClient
	workflowMetadata  *metadata.WorkflowMetadata
	ghClient          ghclient.Client
	ghTwirpClient     ghtwirp.Client
	data              *types.WorkflowInvocationData
	invocation        Invocation
	outcome           deployer.OrgCreationOutcome
	filter            workflowbuild.WorkflowFilter
	repositoryTenants *types.RepositoryTenants
	errorHandler      WorkflowStartErrHandler
	workflowSource    workflowparser.WorkflowSource

	appEnv                launchconfig.AppEnv
	tokenFactory          workflowbuild.TokenFactory
	repo                  deployer.WorkflowBuildsRepository
	actionsAppGlobalID    string
	dependabotAppGlobalID string
	kredzClient           kredz.Client
	varzClient            varz.Client
	secretDecryptor       earthsmoke.Decryptor
	keyGenerator          hkdf.KeyGenerator
	receiverURL           string
	receiverInternalURL   string
	receiverPublicURL     string
	resultsReceiverURL    string
	urlProviderFactory    cu.URLProviderFactory
	reporter              *slometrics.Reporter
	labeler               customerlabels.CustomerLabeler
	isEnterprise          bool
	enterpriseVersion     string
	partialAbuseContext   *types.PartialAbuseTriggerInfo
	queueBuildRateLimiter rate.RateLimiter
	webhookRateLimiter    rate.RateLimiter
	runServiceClient      runservice.Client
	resultsClient         results.Client
}

//gocyclo:ignore
func (i *buildInvoker) Run(ctx context.Context, workflow *model.Workflow, parsedWorkflow *workflowparser.Workflow, isFinalAttempt bool) *WorkflowStartErr {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx = appcontext.Fork(ctx)

	repoID := i.invocation.Target.RepositoryID
	executingActor := i.invocation.ExecutingActor
	triggeringActor := i.invocation.TriggeringActor
	event := i.invocation.Event
	target := i.invocation.Target
	var calledWorkflowParsingError error

	defer i.errorHandler.handlePanic(ctx, i.data)

	// Check if this build is:
	// - not a re-run, and
	// - originates from a webhook
	// and if it has been queued already
	if i.invocation.ExistingCheckSuite == nil &&
		event.WebhookDeliveryID != nil {
		if state, ok, err := i.repo.GetWorkflowState(ctx, *event.WebhookDeliveryID, event.Name, workflow.FileReference); err != nil {
			// Report the error but continue
			i.obs.Report(ctx, errors.Wrap(err, "Could not get workflow state"))
		} else if ok && *state >= build.WorkflowStateQueued {
			i.obs.Log(ctx, "Workflow not run, it's already in a state >= queued", kvp.Any("gh.launch.workflow_build.state", *state))
			return nil
		}
	}

	// Check if this build is:
	// - a rerun, and
	// - originates from a webhook
	// - and if it has been queued already
	if i.invocation.ExistingCheckSuite != nil && event.WebhookDeliveryID != nil {
		if state, ok, err := i.repo.GetWorkflowRerunState(ctx, *event.WebhookDeliveryID, event.Name, i.invocation.RerunWebhookDeliveryID, parsedWorkflow.FileReference); err != nil {
			i.obs.Report(ctx, errors.Wrap(err, "Could not get workflow state"))
		} else if ok && *state >= build.WorkflowStateQueued {
			i.obs.Log(ctx, "Workflow not rerun, it's already in a state >= queued", kvp.Any("gh.launch.workflow_build.state", *state))
			return nil
		}
	}

	// Populate the checkout SHA of the workflow only incase of
	// required workflows because we need this information when we
	// fetch the workflow file for a particular execution.
	var workflowFileCheckoutSHA types.CommitSha
	if parsedWorkflow.IsRequiredWorkflow() {
		workflowFileCheckoutSHA = types.CommitSha(parsedWorkflow.File.SHA)
	}

	errCtx := NewBuildStartErrContext(workflow.Path, workflow.Identifier, i.invocation, i.data, workflowFileCheckoutSHA, parsedWorkflow.File.Ref)
	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.workflow.identifier", workflow.Identifier))

	run := i.filter.ShouldRun(ctx, *workflow)

	if !run {
		i.obs.Log(ctx, "workflow not running due to filter")
		return nil
	}

	if event.Name == flowevents.WorkflowRun || event.Name == flowevents.Deployment || event.Name == flowevents.DeploymentStatus {
		hasCycle, err := i.HasWorkflowCycle(ctx, workflow.Identifier, workflow.Path, event.Ghe)
		if err != nil {
			// Report error but let the execution continue
			i.obs.Report(ctx, errors.Wrap(err, "Could not check for workflow cycle"))
		}

		if hasCycle {
			i.obs.Log(ctx, "workflow not running due to recursive cycle detected")
			return nil
		}
	}

	if parsedWorkflow.CalledWorkflows == nil {
		i.obs.Debug(ctx, "Parse if there are any callable workflows")
		runtimeHelper := utils.NewRuntimeHelper(i.isEnterprise, i.enterpriseVersion)
		_, actorID, err := triggeringActor.ID.Decode()
		if err != nil {
			i.obs.Error(ctx, "Failed to decode actor global ID", kvp.Err(err))
		}

		calledWorkflows, _, callDepth, err := workflowparser.PopulateJobsUsingWorkflows(ctx, parsedWorkflow.Parsed().Jobs, i.data.WorkflowFeatureFlags, i.workflowSource, 1, runtimeHelper, actorID, &i.obs.Observability)
		if err != nil {
			i.obs.Debug(ctx, "invalid workflow file", kvp.String("gh.launch.workflow.file_path", workflow.Path), kvp.Err(err))
			calledWorkflowParsingError = err
			if err, ok := err.(workflowparser.CalledWorkflowParseError); ok {
				calledWorkflowParsingError = err.ToParseError(workflow.Path)
			}
			if i.invocation.ExistingCheckSuite == nil {
				// in case of new run fail early and report error
				i.errorHandler.notifyInvalidWorkflow(ctx, workflow.Path, calledWorkflowParsingError, i.data, &event, workflowFileCheckoutSHA)
				return nil
			}
		}
		nestedCallTags := statter.Tags{
			"call_depth": strconv.Itoa(callDepth),
		}
		i.obs.Observability.Counter(ctx, metrickeys.NestedWorkflowsCallDepth, nestedCallTags, 1)

		// isEnterprise is true for GHES
		if (!i.isEnterprise) && len(calledWorkflows) > 0 {
			// check workflow policy with resolved path in case of nested calling
			wfPolicyErr := i.WorkflowsAllowedByPolicy(ctx, errCtx, i.data.RepoGlobalID, parsedWorkflow, calledWorkflows)
			if wfPolicyErr != nil {
				i.obs.Log(
					ctx,
					"workflow execution stopped due to workflow execution capability settings",
					kvp.String("gh.repo.name_with_owner", i.data.NWO.String()),
					kvp.String("gh.actor.global_id", string(executingActor.ID)),
				)
				return wfPolicyErr
			}
		}

		parsedWorkflow.CalledWorkflows = calledWorkflows
	}

	// Validate that all actions in the plan are allowed to be run by the user.
	policyErr := i.ActionsAllowedByPolicy(ctx, errCtx, i.data.RepoGlobalID, parsedWorkflow)
	if policyErr != nil {
		i.obs.Log(
			ctx,
			"workflow execution stopped due to action execution capability settings",
			kvp.String("gh.repo.name_with_owner", i.data.NWO.String()),
			kvp.String("gh.actor.global_id", string(executingActor.ID)),
		)
		return policyErr
	}

	allowedActionsErr := i.CheckIfActionsAllowedByLaunch(ctx, errCtx, parsedWorkflow)
	if allowedActionsErr != nil {
		i.obs.Log(
			ctx,
			"found some disallowed actions",
			kvp.String("gh.repo.name_with_owner", i.data.NWO.String()),
			kvp.String("gh.actor.global_id", string(executingActor.ID)),
		)
		return allowedActionsErr
	}

	// Fail workflows that contain a snapshot step if custom image generation is disabled
	customImageErr := i.IsCustomImageGenerationAllowedByPolicy(ctx, errCtx, parsedWorkflow)
	if customImageErr != nil {
		i.obs.Log(
			ctx,
			"workflow execution stopped due to custom image generation policy",
			kvp.String("gh.repo.name_with_owner", i.data.NWO.String()),
			kvp.String("gh.actor.global_id", string(executingActor.ID)),
		)
		return customImageErr
	}

	// Get the repository tier
	repoTier, err := i.GetRepositoryTier(ctx, repoID)
	if err != nil {
		i.obs.Report(ctx, errors.Wrap(err, "Could not get repository tier"))
	}

	// In multi-tenant environments, the tenant slug should be used as a subdomin
	// In non-multi-tenant environments, this value will be empty and a no-op will be performed
	// See: https://github.com/github/actions-core-enterprise/issues/695
	urlProvider, err := i.urlProviderFactory.NewProvider(i.invocation.Target.GitHubTenant.Slug)
	if err != nil {
		err = fmt.Errorf("error creating URLProvider: %w", err)
		i.obs.Report(ctx, err)
		return NewPermanentWorkflowStartError(errCtx, err, newWorkflowBuildErrType)
	}

	workflowRef := i.data.NWO.Owner + "/" + i.data.NWO.Name + "/" + workflow.Path
	if i.data.References.CheckoutCommit.GitRef != "" {
		workflowRef = workflowRef + "@" + i.data.References.CheckoutCommit.GitRef.String()
	} else {
		workflowRef = workflowRef + "@" + i.data.References.CheckoutCommit.CommitSHA.String()
	}

	env := build.RunEnvironment{
		Event:                             event.Name,
		Repository:                        i.data.NWO,
		RepositoryID:                      i.data.RepoGlobalID,
		RepositoryDatabaseID:              i.data.RepoDatabaseID,
		RepositoryVisibility:              i.data.Visibility,
		ParentRepository:                  i.data.ParentRepositoryNWO,
		PrivateRepository:                 i.data.RepoIsPrivate,
		ForkedRepository:                  i.data.RepoIsFork,
		OwnerID:                           i.data.Owner.GlobalID,
		OwnerDatabaseID:                   i.data.Owner.DatabaseID,
		OwnerCreatedAt:                    i.data.Owner.CreatedAt,
		EnterpriseManagedBusinessID:       i.data.Owner.EnterpriseManagedBusinessID,
		GitURL:                            i.data.RepoGitURL,
		ServerURL:                         urlProvider.GitHubServerURL(),
		APIURL:                            urlProvider.V3ApiURL(),
		GraphQLURL:                        urlProvider.GraphQLApiURL(),
		ExecutingActor:                    executingActor.Login,
		ExecutingActorID:                  executingActor.ID,
		TriggeringActor:                   triggeringActor.Login,
		TriggeringActorID:                 triggeringActor.ID,
		Workflow:                          workflow.Identifier,
		BaseRef:                           types.GitRefZeroValue,
		HeadRef:                           types.GitRefZeroValue,
		RetentionDays:                     i.data.ActionsRetentionLimit,
		ActionsCacheSizeLimit:             i.data.ActionsCacheSizeLimit,
		OidcSubClaimCustomizationTemplate: i.data.OidcSubClaimCustomizationTemplate,
		CustomizeEnterpriseOidcIssuer:     i.data.CustomizeEnterpriseOidcIssuer,
		RepositoryTier:                    repoTier,
		SelfHostedRunnersDisabled:         i.data.RepoSelfHostedRunnersDisabled,
		WorkflowRef:                       workflowRef,
		WorkflowSha:                       i.data.References.EventCommit.CommitSHA,
	}

	_, executingActorDatabaseID, err := executingActor.ID.Decode()
	if err == nil {
		env.ExecutingActorDatabaseID = executingActorDatabaseID
	} else {
		env.ExecutingActorDatabaseID = -1
		// Report an error, but don't fail the workflow
		i.obs.Report(ctx, errors.Wrap(err, "Could not decode executing actor ID"))
	}

	env, headRepositoryID := extractPRData(ctx, env, &event, &target)

	triggerID := extractTrigger(ctx, i.ghTwirpClient, &event)
	i.obs.Debug(ctx, "extracted trigger", kvp.String("gh.launch.trigger.id", triggerID.String()))

	customerLabel := i.labeler.LabelFor(env.Repository.Owner, i.data.PlanOwner.Name)

	b, err := build.NewWorkflowBuild(
		i.invocation.ExecutionID(),
		parsedWorkflow,
		env,
		i.invocation.LatestWebhookDeliveryID(),
		event.Name,
		event.Payload,
		event.Time,
		event.OriginTime,
		i.data,
		i.repositoryTenants,
		event.Ghe,
		i.partialAbuseContext,
		customerLabel,
		i.invocation.Target.GitHubTenant,
	)
	if err != nil {
		span.RecordError(err)
		return NewPermanentWorkflowStartError(errCtx, err, newWorkflowBuildErrType)
	}

	b.FileReference = workflow.FileReference

	ctx = ctxstash.WithFields(ctx,
		kvp.Any("gh.launch.workflow_run.id", b.ExecutionID),
	)

	ctx = ctxstash.WithVSSOrchestrationID(ctx, b.ExecutionID.String())

	errCtx.workflowExecutionID = &b.ExecutionID

	// Create a copy and customize WorkflowMetadata for this workflow.
	workflowReportingMD := *i.workflowMetadata
	workflowReportingMD.RepositoryTier = repoTier
	workflowReportingMD.CustomerLabel = customerLabel
	workflowReportingMD.CustomerID = i.data.PlanOwner.CustomerID

	if !b.EventTime.IsZero() {
		defer func() {
			i.obs.LegacyTiming(ctx, "workflow.invoker.delay", nil, time.Since(b.EventTime))
		}()
	}

	var actorFromMetadata *metadata.WorkflowMetadataActor
	if i.workflowMetadata != nil {
		actorFromMetadata = i.workflowMetadata.Actor
	}

	// Determine permissions for workflow job tokens that'll be created later
	tokenPermissions, err := i.tokenFactory.CalculateRunPermissions(ctx, &i.obs.Observability, event.Name, event.Ghe, i.data.DefaultWorkflowPermissions, i.data.ForkPRWorkflowsPolicy, actorFromMetadata)
	if err != nil {
		return NewPermanentWorkflowStartError(errCtx, err, calculatePermissionsErrType)
	}

	b.RunEnvironment.DefaultWorkflowPermissions = i.data.DefaultWorkflowPermissions

	i.obs.Debug(ctx, "Determined permissions for creating a repository token",
		kvp.String("gh.launch.safe_access_level", string(tokenPermissions.InstallationPermissions.Contents)),
		kvp.Bool("gh.launch.has_extended_permissions", tokenPermissions.ExtendedPermissions != nil),
		kvp.String("gh.launch.default_permissions", string(tokenPermissions.DefaultPermissions)))

	referencedWorkflows, err := parsedWorkflow.BuildReferencedWorkflowsJSON()
	if err != nil {
		i.obs.Report(ctx, errors.Wrap(err, "could not build referenced workflows JSON"))
	}

	b.Backend = types.WorkflowBackendActionsService
	if useRunService(ctx, parsedWorkflow, i.data.PlanOwner.PlanName, i.data.NWO, i.data.RepoGlobalID, b.GetRootWorkflow(), i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners) {
		b.Backend = types.WorkflowBackendRunService
	}
	mw.TagStatsWith(ctx, reqmeta.Tags{"backend": b.Backend.String()})

	var workflowBuildID int64
	var checkSuiteState *types.CheckSuiteState
	var executionGraph string
	var eventCreatedTime time.Time
	if i.invocation.ExistingCheckSuite != nil {
		checkSuiteState = i.invocation.ExistingCheckSuite
		// Since we are re-running this build it has been persisted before and we already have an id. Update
		// startErr with the id, otherwise in case of an error we would try to persist the build again with the
		// same check suite id leading to a duplicate key SQL error.
		workflowBuildID = checkSuiteState.WorkflowBuildDatabaseID
		errCtx.workflowBuildID = &workflowBuildID

		// Generate execution graph for reusable workflows, skip for partial reruns
		isPartialRerun := i.invocation.RerunInfo != nil
		if len(parsedWorkflow.CalledWorkflows) > 0 && !isPartialRerun {
			executionGraph = i.buildExecutionGraphJSON(ctx, parsedWorkflow)
		}

		allowFourNinesRerun := false
		if checkSuiteState.Backend == types.WorkflowBackendRunService {
			// Ask Results if the run is complete
			rerunState, err := i.resultsClient.GetWorkflowRunState(ctx, checkSuiteState.ExecutionID)
			if err != nil {
				return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, "GetWorkflowRunStateError")
			}
			allowFourNinesRerun = rerunState.GetStatus() > 0 && rerunState.GetCompletedAt() != nil
		}

		// make sure we use the same backend as the previous run for partial rerun.
		if b.Backend != checkSuiteState.Backend && isPartialRerun {
			i.obs.Debug(ctx, "using previous backend", kvp.String("gh.launch.backend", checkSuiteState.Backend.String()))
			b.Backend = checkSuiteState.Backend
		}

		// If we are rerunning the build, we should reset its workflow build state, and update the installation since
		// it might have changed since the workflow was last run. Also update the permissions since repo settings might
		// have led to a different outcome for this run.
		workflowBuildResetContext, resetErr := i.repo.ResetWorkflowBuildState(
			ctx, checkSuiteState.CheckSuiteIDPair.GlobalID, b,
			tokenPermissions, &workflowReportingMD, executingActor.ID, allowFourNinesRerun,
		)
		if resetErr != nil {
			i.obs.Error(ctx, "error resetting build state", kvp.Err(resetErr))
			resetErr = tracing.RecordError(span, resetErr)
			return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, resetErr, resetWorkflowBuildErrType)
		}

		if workflowBuildResetContext.WorkflowExecutionID != nil {
			b.ExecutionID = *workflowBuildResetContext.WorkflowExecutionID
			errCtx.workflowExecutionID = workflowBuildResetContext.WorkflowExecutionID

			err := updateCheckSuiteWithExecutionID(ctx, i.ghTwirpClient, checkSuiteState, triggeringActor.ID, b.ExecutionID, workflowBuildResetContext.Attempt, executionGraph, referencedWorkflows)
			if err != nil {
				err = tracing.RecordError(span, err)
				i.obs.Error(ctx, "error updating the checksuite with ExecutionID", kvp.Err(err))
				return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, updateCheckSuiteStateErrType)
			}
		}
		b.RunEnvironment.WorkflowRunAttempt = workflowBuildResetContext.Attempt

		b.RerunInfo = i.invocation.RerunInfo

		if b.Backend == types.WorkflowBackendRunService && isPartialRerun {
			// we need to fetch the previous orchestration contexts from Results service for partial reruns in Run Service
			rerunWorkflowID, err := types.ParseWorkflowExecutionID(b.RerunInfo.PlanID)
			if err != nil {
				err = tracing.RecordError(span, err)
				i.obs.Error(ctx, "error parsing rerun workflow id", kvp.Err(err))
				return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, parseWorkflowPlanIDErrType)
			}

			b.PreviousOrchContexts, err = i.resultsClient.GetWorkflowOrchestrationContexts(ctx, rerunWorkflowID)
			if err != nil {
				err = tracing.RecordError(span, err)
				i.obs.Error(ctx, "error getting workflow orchestration contexts", kvp.Err(err))
				return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, getOrchestrationContextsErrType)
			}
		}

		// On re-run new attempt if there were parsing errors for reusable workflows throw the error now after preparing
		// run and checksuite state
		if calledWorkflowParsingError != nil {
			return NewPermanentWorkflowStartErrorWithBackend(errCtx, b.Backend, calledWorkflowParsingError, parserErrorErrType)
		}

	} else {
		var persistedPayload bool

		// Generate execution graph and keep around for CreateErrorCheckSuite
		executionGraph = i.buildExecutionGraphJSON(ctx, parsedWorkflow)

		// Persist build to get a build id
		eventSHA := i.data.References.EventCommit.CommitSHA
		eventRef := i.data.References.EventCommit.GitRef

		var workflowExecutionID types.WorkflowExecutionID
		workflowBuildID, workflowExecutionID, eventCreatedTime, persistedPayload, err = i.repo.Persist(
			ctx, b, target.RepositoryID,
			eventSHA, eventRef, workflow.Identifier, &workflowReportingMD, tokenPermissions, event.Payload,
			executingActor.ID, triggeringActor.ID, i.invocation.Target.GitHubTenant,
		)
		if err != nil {
			span.RecordError(err)
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error"})
			return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, buildPersistError)
		}

		i.obs.Debug(ctx, "persisted workflow build", kvp.Int64("gh.launch.workflow_build.id", workflowBuildID))

		b.ExecutionID = workflowExecutionID
		errCtx.workflowBuildID = &workflowBuildID
		errCtx.workflowExecutionID = &workflowExecutionID
		errCtx.rerunnable = persistedPayload

		isActionRequired, err := i.isActionRequired(ctx, target.RepositoryID, event, i.invocation.ExistingCheckSuite, i.data.WorkflowFeatureFlags.WorkflowApprovalsUsePRAuthorEnabled)
		if err != nil {
			span.RecordError(err)
			return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, isActionRequiredErrType)
		}

		var conclusion ghclient.CheckSuiteConclusion
		if isActionRequired {
			i.obs.Debug(ctx, "Creating action required check suite")
			conclusion = ghclient.CheckSuiteActionRequiredConclusion
		}

		var treeID types.CommitSha
		var reusableCheckSuite types.GlobalID
		if i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, ghclient.GreenTreesFeatureFlag, repoID) && parsedWorkflow.ReusePreviousOutcomeForEvent(i.invocation.Event.Name) {
			treeID, reusableCheckSuite = i.reusePreviousOutcomeCheck(ctx, target.RepositoryID, i.invocation.Event.Name, workflow.Path, eventSHA)

			if reusableCheckSuite != types.NilGlobalID {
				reuseOutcome, err := reusePreviousWorkflowRun(ctx, i.ghClient, i.invocation, reusableCheckSuite, triggerID, i.data.References.EventCommit, treeID)

				if reuseOutcome == nil {
					if err != nil {
						i.obs.Debug(ctx, "Unable to reuse a previous outcome by cloning an existing check suite. Will proceed to normally queue a run in actions-dotnet.", kvp.String("exception.message", err.Error()))
					} else {
						i.obs.Debug(ctx, "No outcome returned during reuse operation so a run will be normally queued in actions-dotnet.")
					}
				} else {
					i.obs.Debug(ctx, "Existing workflow run successfully cloned! Not queuing a new run in actions-dotnet",
						kvp.Int64("gh.check_suite.id", reuseOutcome.CheckSuiteDatabaseID),
						kvp.Int64("gh.launch.workflow_run.id", reuseOutcome.WorkflowRunDatabaseID))
					return nil
				}
			}
		}

		// Call this even if we already have a pre-created check suite, for instance in the case of a `dynamic` workflow run.
		// Re-using the same `ExecutionID` guarantees that we will receive the same result from the creation API.
		checkSuiteState, err = createCheckSuite(
			ctx,
			i.ghClient,
			b.ExecutionID,
			i.invocation,
			i.data.References.EventCommit,
			i.data.References.CheckoutCommit,
			headRepositoryID,
			workflow.Identifier,
			workflow.Path,
			triggerID,
			true,
			executionGraph,
			&[]ghclient.CheckSuiteAnnotation{},
			conclusion,
			referencedWorkflows,
			workflowFileCheckoutSHA,
			treeID,
			types.GitRef(parsedWorkflow.File.Ref),
		)

		if err != nil {
			span.RecordError(err)
			if terrors.IsNotFoundError(err) {
				// The repo/sha were not found when creating a check suite (probably because the SHA was deleted)
				// This is not recoverable, and attempts to notify via i.createErrorCheckSuite() will fail
				i.obs.Log(ctx, "Unable to create check suite as SHA cannot be found or has deleted")
				mw.TagStatsWith(ctx, reqmeta.Tags{"status": "unhandled_error", "error_type": "internal", "error_reason": "commit_not_found"})
				return nil
			}
			return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, newCheckSuiteStateErrType)
		}

		// set the workflow_builds database id in the check suite state for later use
		checkSuiteState.WorkflowBuildDatabaseID = workflowBuildID

		i.obs.Log(ctx, "created check suite", kvp.String("gh.check_suite.global_id", checkSuiteState.CheckSuiteIDPair.GlobalID.String()))

		// Update build with check suite state
		err = i.repo.SetCheckSuiteInformation(ctx, workflowBuildID, checkSuiteState.CheckSuiteIDPair.GlobalID, checkSuiteState.WorkflowRunID, checkSuiteState.WorkflowRunNumber)
		if err != nil {
			span.RecordError(err)
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error"})
			return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, buildPersistError)
		}

		if isActionRequired {
			sloMetadata := i.buildSloMetadata(ctx, b, &workflowReportingMD, &eventCreatedTime)
			workflowStartErr := i.createResultsWorkflowRun(ctx, b, sloMetadata, checkSuiteState, errCtx)
			if workflowStartErr != nil {
				return workflowStartErr
			}
			err = i.repo.Complete(ctx, time.Now().UTC(), time.Now().UTC(), workflowBuildID, build.WorkflowStateSkipped)
			if err != nil {
				span.RecordError(err)
				mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error"})
				return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, publicForkPRErrType)
			}

			return nil
		}
		b.RunEnvironment.WorkflowRunAttempt = 1
	}

	if launchconfig.UsingResultsService() {
		sloMetadata := i.buildSloMetadata(ctx, b, &workflowReportingMD, &eventCreatedTime)
		err := i.createResultsWorkflowRun(ctx, b, sloMetadata, checkSuiteState, errCtx)
		if err != nil {
			return err
		}
	}

	b.RunEnvironment.WorkflowRunID = checkSuiteState.WorkflowRunID
	b.RunEnvironment.WorkflowRunNumber = checkSuiteState.WorkflowRunNumber

	// Populate workflow run id in abuse context since it wasn't available when the abuse context was created
	if b.AbuseContext != nil {
		b.AbuseContext.WorkflowRunID = checkSuiteState.WorkflowRunID
	}

	// Ensure to save the instantiated check suite id for potential
	// createErrorCheckSuite calls below: this ensures the created CheckSuite
	// is reused for potential error messages.
	errCtx.checkSuiteID = checkSuiteState.CheckSuiteIDPair.GlobalID

	ctx = ctxstash.WithFields(ctx,
		kvp.Any("gh.check_suite.global_id", checkSuiteState.CheckSuiteIDPair.GlobalID),
		kvp.Int("gh.check_suite.id", int(checkSuiteState.CheckSuiteIDPair.DatabaseID)),
		kvp.Int64("gh.launch.workflow_run.id", checkSuiteState.WorkflowRunID),
	)

	// Determine what secret source to use and construct a secret store for it
	secretStore, err := i.getSecretStore(ctx, repoID, b)
	if err != nil {
		i.obs.Error(ctx, "unable to retrieve secrets", kvp.Err(err))
		span.RecordError(err)
		return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, "getSecretStore")
	}

	var variablesMap map[string]string

	publicForkPolicy := types.PublicForkPRWorkflowsInvalidPolicy
	if i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, github.PublicForkPrWorkflowsPolicyFlag, i.data.RepoGlobalID) {
		publicForkPolicy = i.data.PublicForkPRWorkflowsPolicy
	}

	// If the feature flag is enabled, fetch variables
	if ShouldSendVariables(b.Event, b.GitHubEvent, i.data.ForkPRWorkflowsPolicy, publicForkPolicy) && (i.isEnterprise || i.data.WorkflowFeatureFlags.ConfigurationVariablesEnabled) {
		if i.data.WorkflowFeatureFlags.SizeRestrictedVarCountEnabled {
			var err error
			variablesMap, err = i.getVariablesIncreasedCount(ctx, i.varzClient, i.ghTwirpClient, i.data, i.data.RepoGlobalID)

			if err != nil && err != ErrVariableSizeExceeded {
				i.obs.Error(ctx, "unable to retrieve variables", kvp.Err(err))
				span.RecordError(err)
				return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, "getVariablesIncreasedCount")
			}

			if err == ErrVariableSizeExceeded {
				i.annotateWithSizeExceededWarning(ctx, err, checkSuiteState)
			}

		} else {
			var err error
			variablesMap, err = i.getVariables(ctx, i.varzClient, i.ghTwirpClient, i.data, i.data.RepoGlobalID)
			if err != nil {
				i.obs.Error(ctx, "unable to retrieve variables", kvp.Err(err))
				span.RecordError(err)
				return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, "getVariables")
			}
		}
	}

	if workflow.RunNameExpression != "" {
		startErr := i.updateWorkflowRunName(ctx, parsedWorkflow, b, checkSuiteState, secretStore.GetSecretSource().String(), workflow.RunNameExpression, errCtx, variablesMap)
		if startErr != nil {
			return startErr
		}
	}

	return i.generateKeyAndQueueBuild(ctx, b, secretStore, variablesMap, workflowBuildID, isFinalAttempt, errCtx, parsedWorkflow, &workflowReportingMD, checkSuiteState)
}

func (i *buildInvoker) createResultsWorkflowRun(ctx context.Context, b *build.WorkflowBuild, sloMetadata *results.RunStartDelaySLOMetadata, checkSuiteState *types.CheckSuiteState, errCtx *WorkflowStartErrorContext) *WorkflowStartErr {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	previousAttemptWorkflowRunBackendID := ""
	if b.RerunInfo != nil {
		previousAttemptWorkflowRunBackendID = b.RerunInfo.PlanID
	}

	if err := i.resultsClient.CreateWorkflowRun(ctx, b.ExecutionID, checkSuiteState, i.data.ActionsRetentionLimit, sloMetadata, previousAttemptWorkflowRunBackendID); err != nil {
		span.RecordError(err)
		i.obs.Error(ctx, "error calling workflow run create to results", kvp.Err(err))
		return NewWorkflowStartErrorWithBackend(errCtx, b.Backend, err, createWorkflowRunResultsErrType)
	}
	return nil
}

func (i *buildInvoker) buildSloMetadata(ctx context.Context, b *build.WorkflowBuild, workflowReportingMD *metadata.WorkflowMetadata, eventCreatedTime *time.Time) *results.RunStartDelaySLOMetadata {
	sloMetadata := &results.RunStartDelaySLOMetadata{
		CustomerLabel: customerlabels.NoneLabel,
		IsRunFromLab:  launchconfig.IsLab(),
	}
	// ignore runs to Actions service since launch is still going track SLO for those runs.
	// ignore rerun and ignore schedule workflow runs.
	if b.Backend != types.WorkflowBackendRunService || i.invocation.ExistingCheckSuite != nil || b.Event == flowevents.Schedule {
		sloMetadata.IgnoreFromRunStartDelay = true
	}
	// for dynamic workflow we need to provide the integrator name based on the workflow path
	if b.Event == flowevents.Dynamic {
		integrator, _, ok := flowevents.ExtractDynamicWorkflowFilePath(b.WorkflowFilePath)
		if !ok {
			if b.WorkflowFilePath != "BuildFailed" {
				i.obs.Error(ctx, "could not extract workflow file path for dynamic workflow", kvp.String("gh.launch.workflow.file_path", b.WorkflowFilePath))
			}
			integrator = "buildfailed"
		}

		sloMetadata.DynamicWorkflowIntegrator = integrator
	}
	if workflowReportingMD.CustomerLabel != "" {
		sloMetadata.CustomerLabel = workflowReportingMD.CustomerLabel
	}

	if b.Event != "" {
		sloMetadata.EventName = b.Event
	}

	sloMetadata.EventCreatedAt = *eventCreatedTime
	return sloMetadata
}

func (i *buildInvoker) generateKeyAndQueueBuild(ctx context.Context, b *build.WorkflowBuild, secretStore build.SecretStore, variablesMap map[string]string, workflowBuildID int64, isFinalAttempt bool, errCtx *WorkflowStartErrorContext, parsedWorkflow *workflowparser.Workflow, md *metadata.WorkflowMetadata, css *types.CheckSuiteState) *WorkflowStartErr {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	defer i.errorHandler.handlePanic(ctx, i.data)

	defer logInvocationLatency(ctx, i.obs, i.outcome)

	timestamp := hkdf.Now()
	key, err := i.keyGenerator.Generate(b.ExecutionID.String(), timestamp)
	if err != nil {
		span.RecordError(err)
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error"})
		return NewPermanentWorkflowStartErrorWithBackend(errCtx, b.Backend, err, certGeneratorErrType)
	}
	b.SigningKey = key

	compareErrors := i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, ghclient.CompareParserErrorsFlag, i.data.RepoGlobalID)
	comparePlans := i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, ghclient.CompareParserPlansFlag, i.data.RepoGlobalID)

	var qbErr error

	if shouldRunParserComparison(compareErrors, comparePlans, b) {
		fileProvider := wfparser.NewFileProvider(ctx, &i.obs.Observability, b.WorkflowReferencedFiles(false))

		workflowFilePath := requiredworkflowutils.RemoveMetadataFromRequiredWorkflowPath(b.WorkflowFilePath)

		snapshotKeywordEnabled := i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, ghclient.SnapshotKeywordEnabledFlag, i.data.RepoGlobalID)
		parseOptions := []func(*template.ParseOptions){
			func(options *template.ParseOptions) {
				options.AllowSnapshotKeyword = snapshotKeywordEnabled
			},
		}

		wf, err := wfparser.LoadWorkflow(ctx, &i.obs.Observability, workflowFilePath, fileProvider, b.RunEnvironment.DefaultWorkflowPermissions, parseOptions...)
		if err != nil {
			i.obs.Error(ctx, "unable to parse workflow for comparison", kvp.Err(err))
			// queue the build as normal
			i.obs.Statter.Counter(ctx, "parser.queue_build", statter.Tags{"type": "parse_error"}, 1)
			qbErr = i.queueBuild(ctx, b, secretStore, variablesMap, workflowBuildID, isFinalAttempt, nil, nil, md, css)
		} else {
			// create expContext for evaluateConcurrency
			expContext, err := expressions.NewContext(ctx, &i.obs.Observability, parsedWorkflow, b, secretStore.GetSecretSource().String(), variablesMap)
			if err != nil {
				i.obs.Error(ctx, "unable to create expression context", kvp.Err(err))
				span.RecordError(err)
			}
			concurrency := wfparser.EvaluateWorkflowConcurrency(ctx, &i.obs.Observability, wf, workflowFilePath, expContext)
			if concurrency == nil {
				i.obs.Debug(ctx, "Unable to evaluate concurrency")
			}
			if comparePlans && len(wf.Errors) == 0 {
				// pass in wf to compare plans if there are no errors
				i.obs.Debug(ctx, "Queueing build with parsed workflow attached")
				i.obs.Statter.Counter(ctx, "parser.queue_build", statter.Tags{"type": "compare_plans"}, 1)

				evaluateConcurrencyFlag := i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, ghclient.EvaluateConcurrencyFlag, i.data.RepoGlobalID)

				if evaluateConcurrencyFlag {
					qbErr = i.queueBuild(ctx, b, secretStore, variablesMap, workflowBuildID, isFinalAttempt, wf, concurrency, md, css)
				} else {
					qbErr = i.queueBuild(ctx, b, secretStore, variablesMap, workflowBuildID, isFinalAttempt, wf, nil, md, css)
				}
			} else {
				// queue the build as normal
				i.obs.Statter.Counter(ctx, "parser.queue_build", statter.Tags{"type": "compare_errors"}, 1)
				qbErr = i.queueBuild(ctx, b, secretStore, variablesMap, workflowBuildID, isFinalAttempt, nil, nil, md, css)
			}

			if compareErrors {
				i.compareParserErrors(ctx, wf, qbErr)
			}
		}
	} else {
		// If neither flag is enabled, queue the build as normal
		i.obs.Statter.Counter(ctx, "parser.queue_build", statter.Tags{"type": "normal"}, 1)
		qbErr = i.queueBuild(ctx, b, secretStore, variablesMap, workflowBuildID, isFinalAttempt, nil, nil, md, css)
	}

	if qbErr != nil {
		return i.mapQueueErrorToStartErr(ctx, b.Backend, qbErr, errCtx)
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{"status": "success"})

	if !b.OriginTime.IsZero() {
		// Measure the overall time between an event happening (a commit being pushed, a scheduled build's next run time, ...)
		// and a successfully queued build
		i.obs.LegacyTiming(ctx, "workflow.event_to_queue", nil, time.Since(b.OriginTime))
	}

	return nil
}

func (i *buildInvoker) annotateWithSizeExceededWarning(ctx context.Context, sizeErr error, checkSuiteState *types.CheckSuiteState) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	runtimeHelper := utils.NewRuntimeHelper(i.isEnterprise, i.enterpriseVersion)
	variableLimitsDocsURL := runtimeHelper.GetDocsURL("/actions/learn-github-actions/variables#limits-for-configuration-variables")
	variablesTotalSizeLimit := "256 KB"
	if runtimeHelper.IsEnterprise() {
		variablesTotalSizeLimit = "10 MB"
	}

	defaultAnnotationRange := github.CheckAnnotationRange{
		StartLine: 1,
		EndLine:   1,
	}
	annotations := []ghclient.CheckSuiteAnnotation{
		github.CheckSuiteAnnotation{
			Title:           "Total variables size limit exceeded",
			Message:         fmt.Sprintf("Some variables failed to load because the total size exceeds the limit of %s. Workflow runs may not function as expected. See the docs for more information: %s", variablesTotalSizeLimit, variableLimitsDocsURL),
			AnnotationLevel: annotationWarningLevel,
			Location:        defaultAnnotationRange,
			Path:            ".github", // default path
		},
	}

	err := updateCheckSuiteWithAnnotations(ctx, i.ghClient, checkSuiteState, annotations)
	if err != nil {
		i.obs.Error(ctx, "error updating the checksuite with annotation", kvp.Err(sizeErr))
	}
}

func (i *buildInvoker) queueBuild(ctx context.Context, f *build.WorkflowBuild, secretStore build.SecretStore, variablesMap map[string]string, buildID int64, isFinalAttempt bool, wft *parser.WorkflowTemplate, concurrency *parser.ConcurrencySetting, md *metadata.WorkflowMetadata, css *types.CheckSuiteState) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	secretSource := secretStore.GetSecretSource().String()
	secretsMap := secretStore.GetDecryptedSecrets(ctx)

	if i.invocation.EnableDebugLogging {
		addDebugSecrets(ctx, i.obs, secretsMap)
	}

	// This tag will be added to the launch.availability.queue_run{status:success} and launch.external_api.http_result{operation:build.queue} metrics.
	mw.TagStatsWith(ctx, reqmeta.Tags{"secret_source": secretSource})

	if !i.queueBuildRateLimiter.Allow(ctx, i.data.RepoDatabaseID) {
		return tracing.RecordError(span, new(rate.QueueRateLimitError))
	}

	buildThrottled := false
	snapshotKeywordEnabled := i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, ghclient.SnapshotKeywordEnabledFlag, i.data.RepoGlobalID)

	if f.Backend == types.WorkflowBackendRunService {
		optOutResults := i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, ghclient.ActionsOptOutResultsServiceRunnerFlag, f.RunEnvironment.RepositoryID)
		optOutCacheV2 := i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, ghclient.OptOutOfCacheServiceV2, f.RunEnvironment.RepositoryID)

		features := map[string]bool{
			ghclient.ActionsUseResultsServiceRunnerFlag: !optOutResults && i.ghTwirpClient.IsFeatureEnabledForActor(ctx, ghclient.ActionsUseResultsServiceRunnerFlag, f.RunEnvironment.RepositoryID),
			ghclient.EnableCacheServiceV2:               !optOutResults && !optOutCacheV2 && i.ghTwirpClient.IsFeatureEnabledForRepository(ctx, ghclient.EnableCacheServiceV2, f.RunEnvironment.RepositoryDatabaseID),
		}

		repoTenantInfo := i.createRepoTenantInfo(f.ActionsBillingPlanOwner)
		parseOptions := []func(*template.ParseOptions){
			func(options *template.ParseOptions) {
				options.AllowSnapshotKeyword = snapshotKeywordEnabled
			},
		}

		planID, runStampURL, err := i.runServiceClient.StartPlan(ctx, f, md, css, i.receiverInternalURL, i.receiverPublicURL, i.resultsReceiverURL, secretSource, secretsMap, variablesMap, features, repoTenantInfo, true, parseOptions...)
		if err != nil {
			twerr, ok := err.(twirp.Error)
			if ok && twerr.Code() == twirp.ResourceExhausted {
				i.obs.Error(ctx, "run service start plan resource exhausted", kvp.Err(twerr))
			}
			if isFinalAttempt {
				_, transitionToError := i.repo.TransitionTo(ctx, buildID, build.WorkflowStateNeverStarted)
				if transitionToError != nil {
					i.obs.Report(ctx, errors.Wrap(transitionToError, "could not transition the workflow build to WorkflowStateNeverStarted"))
					return tracing.RecordError(span, transitionToError)
				}
			}

			switch customErr := err.(type) {
			case *wfparser.WorkflowParseError:
				// currently we don't have the same level of validation as AZP, so
				// we can have syntax errors that aren't caught by provider.ParseFlow
				return customErr

			default:
				return tracing.RecordError(span, errors.Wrap(err, "error queuing build"))
			}
		}

		i.obs.Debug(ctx, "plan queued in run service", kvp.String("gh.launch.plan_id", planID), kvp.String("gh.launch.run.stamp_url", runStampURL))
		f.ExternalID = planID
		ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.build.id", planID))

		err = i.ghTwirpClient.UpdateWorkflowRunExecution(ctx, f.RunEnvironment.RepositoryID, f.RunEnvironment.WorkflowRunID, runStampURL)
		if err != nil {
			i.obs.Report(ctx, errors.Wrap(err, "error updating workflow run execution"))
		}
	} else {
		optOutResults := i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, ghclient.ActionsOptOutResultsServiceRunnerFlag, f.RunEnvironment.RepositoryID)
		optOutCacheV2 := i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, ghclient.OptOutOfCacheServiceV2, f.RunEnvironment.RepositoryID)
		featureFlagsMap := map[string]bool{
			ghclient.ActionsUseResultsServiceRunnerFlag:     !optOutResults && i.ghTwirpClient.IsFeatureEnabledForActor(ctx, ghclient.ActionsUseResultsServiceRunnerFlag, f.RunEnvironment.RepositoryID),
			ghclient.ActionsStreamLogsViaResultsServiceFlag: !optOutResults && i.ghTwirpClient.IsFeatureEnabledForActor(ctx, ghclient.ActionsStreamLogsViaResultsServiceFlag, f.RunEnvironment.RepositoryID),
			ghclient.EnableCacheServiceV2:                   !optOutResults && !optOutCacheV2 && i.ghTwirpClient.IsFeatureEnabledForRepository(ctx, ghclient.EnableCacheServiceV2, f.RunEnvironment.RepositoryDatabaseID),
			"larger_runners_custom_image_generation":        snapshotKeywordEnabled,
			ghclient.BlockArtifactsV3Exempted:               i.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, ghclient.BlockArtifactsV3Exempted, f.RunEnvironment.RepositoryID),
		}

		queuedBuild, err := i.azpClient.Queue(ctx, f, i.receiverURL, i.resultsReceiverURL, secretSource, secretsMap, variablesMap, wft, concurrency, featureFlagsMap, i.appEnv)
		if err != nil {
			if isFinalAttempt {
				_, transitionToError := i.repo.TransitionTo(ctx, buildID, build.WorkflowStateNeverStarted)
				if transitionToError != nil {
					i.obs.Report(ctx, errors.Wrap(transitionToError, "could not transition the workflow build to WorkflowStateNeverStarted"))
					return tracing.RecordError(span, transitionToError)
				}
			}

			switch customErr := err.(type) {
			case *azperrors.AZPSyntaxError:
				// currently we don't have the same level of validation as AZP, so
				// we can have syntax errors that aren't caught by provider.ParseFlow
				return customErr

			case *azperrors.TooManyBuildsError, *azperrors.RerunPlanNotFoundError:
				return customErr

			default:
				return tracing.RecordError(span, errors.Wrap(err, "error queuing build"))
			}
		}

		// If the returned build is in the throttled state, we need to mark it as intentionally delayed
		if queuedBuild.State == azptypes.StatusThrottled {
			buildThrottled = true
		}

		f.ExternalID = strconv.Itoa(queuedBuild.ID)
		ctx = ctxstash.WithFields(ctx, kvp.Int("gh.launch.build.id", queuedBuild.ID))
	}

	i.obs.Counter(ctx, metrickeys.BuildState, map[string]string{
		metrickeys.Provider: metrickeys.ActionsService,
		metrickeys.State:    metrickeys.BuildQueued,
		"tier":              strconv.Itoa(int(f.RunEnvironment.RepositoryTier)),
		"throttled":         strconv.FormatBool(buildThrottled),
	}, 1)

	if err := i.repo.TransitionToQueued(ctx, buildID, f.ExternalID); err != nil {
		i.obs.Report(ctx, errors.Wrap(err, "could not transition the workflow build to WorkflowStateQueued"))
		return tracing.RecordError(span, err)
	}

	if buildThrottled {
		i.obs.Log(ctx, "Marking build as intentionally delayed")

		// For now, make a separate DB roundtrip
		if err := i.repo.SetWasDelayed(ctx, buildID); err != nil {
			// We do not want to fail the build in this case, so log as error and then continue
			i.obs.Report(ctx, errors.Wrap(err, "could not set was_delayed"))
		}
	}

	// Logging metrics for reusable workflows
	localRefsCount, remoteRefsCount := analyzeCallableRefs(f)
	logWorkflowCallUsageMetrics(ctx, &i.obs.Observability, localRefsCount, remoteRefsCount)

	// Logging the plan_owner_name and plan_sku for https://splunk.githubapp.com/en-US/app/gh_reference_app/actions_slas to use effectively as a fact table.
	// Logging here because logging right after getInvocationData would produce 10x or more events, and azp uses this same data for SLAs and concurrency limits.
	// plan_owner_name and billing details are confidential and should not be logged to third-party hosted services like Sentry.
	fields := []kvp.Field{
		kvp.String("gh.launch.plan_owner.name", f.ActionsBillingPlanOwner.Name),
		kvp.String("gh.launch.plan.sku", f.ActionsBillingPlanOwner.PlanSKU),
		kvp.String("gh.launch.secret.source", secretSource),
		kvp.Int("gh.launch.secrets.count", len(secretsMap)),
	}
	fields = append(fields, i.obs.GetCheckpointAqJobFields(ctx)...)
	i.obs.Debug(ctx, "queued azp run", fields...)

	msg := slometrics.NewQueueRunMessage(
		ctx, &i.obs.Observability,
		slometrics.ActorID(i.invocation.TriggeringActor.ID), slometrics.OwnerID(i.data.Owner.GlobalID), slometrics.RepositoryID(i.invocation.Target.RepositoryID), i.invocation.Event.Name, i.invocation.Event.Action,
		slometrics.WithWorkflowExecutionID(f.ExecutionID),
		slometrics.WithCallableWorkflowStats(localRefsCount, remoteRefsCount),
		slometrics.WithRerunInfo(f.RerunInfo),
	)

	i.reporter.ReportQueueRunSuccess(ctx, &i.obs.Observability, msg)
	return nil
}

func (i *buildInvoker) mapQueueErrorToStartErr(ctx context.Context, backend types.WorkflowBackend, err error, errCtx *WorkflowStartErrorContext) *WorkflowStartErr {
	switch customErr := err.(type) {
	case *wfparser.WorkflowParseError:
		{
			// Syntax error caught by the workflow parser
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "user_error"})
			i.obs.Counter(ctx, metrickeys.UserSyntaxError, map[string]string{
				metrickeys.At: metrickeys.AtQueueTime,
			}, 1)

			return NewPermanentWorkflowStartErrorWithBackend(errCtx, backend, customErr, parserErrorErrType)
		}

	case *azperrors.AZPSyntaxError:
		{
			// Syntax error caught by Actions Service
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "user_error"})
			i.obs.Counter(ctx, metrickeys.UserSyntaxError, map[string]string{
				metrickeys.At: metrickeys.AtQueueTime,
			}, 1)

			return NewPermanentWorkflowStartErrorWithBackend(errCtx, backend, customErr, azpParserErrorErrType)
		}

	case *azperrors.RerunPlanNotFoundError:
		{
			// Original plan for a partial rerun was not found
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "rerun_plan_not_found"})
			i.obs.Counter(ctx, metrickeys.RerunPlanNotFoundError, map[string]string{
				metrickeys.At: metrickeys.AtQueueTime,
			}, 1)

			return NewPermanentWorkflowStartErrorWithBackend(errCtx, backend, customErr, runErrType)
		}

	case *azperrors.TooManyBuildsError, *rate.QueueRateLimitError:
		{
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "too_many_builds"})
			i.obs.Counter(ctx, metrickeys.TooManyBuildsError, statter.Tags{}, 1)

			runtimeHelper := utils.NewRuntimeHelper(i.isEnterprise, i.enterpriseVersion)
			docsURL := runtimeHelper.GetDocsURL("/actions/reference/usage-limits-billing-and-administration#usage-limits")
			userErr := terrors.NewUserErrorf("You've exceeded the rate limit for workflow run requests. Please wait before retrying the run. For more information, see %s", docsURL)
			return NewPermanentWorkflowStartErrorWithBackend(errCtx, backend, userErr, runErrType)
		}

	}
	mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error"})
	return NewWorkflowStartErrorWithBackend(errCtx, backend, err, runErrType)
}

func (i *buildInvoker) buildExecutionGraphJSON(ctx context.Context, w *workflowparser.Workflow) string {
	graph, err := i.buildExecutionGraph(ctx, w)
	if err != nil {
		// Log errors at debug level. Panics and timeouts are sent to Sentry in buildExecutionGraph
		// anything else is likely just user error and should not be sent to Sentry.
		err := errors.Wrap(err, "error building execution graph")
		i.obs.Error(ctx, err.Error())
		return ""
	}

	var json string
	json, err = graph.ToJSON()
	if err != nil {
		i.obs.Report(ctx, errors.Wrap(err, "error serializing execution graph"))
		return ""
	}

	if i.appEnv.IsLab() || i.appEnv.IsDevelopment() {
		i.obs.Debug(ctx, "dumping workflow execution graph", kvp.String("gh.launch.execution_graph", json))
	}
	return json
}

func (i *buildInvoker) buildExecutionGraph(ctx context.Context, w *workflowparser.Workflow) (*executiongraph.ExecutionGraph, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var graph *executiongraph.ExecutionGraph
	var err error
	done := make(chan bool, 1)

	go func() {
		defer func() {
			if p := recover(); p != nil {
				var ok bool
				err, ok = p.(error)
				if !ok {
					err = fmt.Errorf("%v", p)
				}
				i.obs.Report(ctx, err, kvp.String("exception_detail", string(debug.Stack())))
			}
			done <- true
		}()

		g, buildErr := executiongraph.BuildExecutionGraph(w)
		if buildErr != nil {
			err = buildErr
			return
		}

		i.obs.Debug(ctx, "built execution graph", kvp.Int("gh.launch.stages.count", len(g.Stages)), kvp.Int("gh.launch.jobs.count", len(w.Jobs())))
		graph = &g
	}()

	select {
	case <-done:
		return graph, err
	case <-time.After(3 * time.Second):
		// If building the graph takes longer than 3 seconds, it's likely a bug in the workflow parser
		// or some other condition that we want to know about.
		err = errors.New("timed out building execution graph")
		i.obs.Report(ctx, err)
		return nil, err
	}
}

func extractTrigger(ctx context.Context, ghtwirp ghtwirp.Client, event *InvokingEvent) types.GlobalID {
	globalID := types.NilGlobalID
	var err error

	switch e := event.Ghe.(type) {
	case *githubgo.PullRequestEvent:
		globalID, err = ghtwirp.GetNextGlobalID(ctx, e.GetPullRequest().GetNodeID())
	case *githubgo.IssuesEvent:
		// Issues are copied and deleted on transfer
		if e.GetAction() != triggerDeleted && e.GetAction() != triggerTransferred {
			globalID, err = ghtwirp.GetNextGlobalID(ctx, e.GetIssue().GetNodeID())
		}
	case *githubgo.IssueCommentEvent:
		if e.GetAction() != triggerDeleted {
			globalID, err = ghtwirp.GetNextGlobalID(ctx, e.GetComment().GetNodeID())
		}
	case *githubgo.DeploymentEvent:
		globalID, err = ghtwirp.GetNextGlobalID(ctx, e.GetDeployment().GetNodeID())
	case *githubgo.ReleaseEvent:
		if e.GetAction() != triggerDeleted {
			globalID, err = ghtwirp.GetNextGlobalID(ctx, e.GetRelease().GetNodeID())
		}
	}

	// For push events we don't have the NodeID in the payload. Dotcom will take care of that case

	if err != nil {
		return types.NilGlobalID
	}

	return globalID
}

func (i *buildInvoker) HasWorkflowCycle(ctx context.Context, workflowIdentifier string, workflowPath string, event flowevents.GitHubEvent) (bool, error) {
	if workflowRunEvent, ok := event.(*githubgo.WorkflowRunEvent); ok {
		previousWorkflow := workflowRunEvent.GetWorkflow()
		if previousWorkflow != nil && strings.EqualFold(previousWorkflow.Name, workflowIdentifier) {
			return true, nil
		}

		// The following code tries to check if we have a cycle of workflow_run-triggered workflows up to a defined
		// maximum number of steps (n):
		// a - wf_run -> [x - wf_run ->]*n a
		//
		// Error handling favors running the workflow that is being checked

		// If the previous workflow run was not triggered by a workflow_run or deployment or deployment_status event, or we don't have the information to
		// there can't be a cycle, exit early
		workflowRun := workflowRunEvent.GetWorkflowRun()
		if workflowRun == nil || (workflowRun.Event != flowevents.WorkflowRun && workflowRun.Event != flowevents.Deployment && workflowRun.Event != flowevents.DeploymentStatus) {
			// Cannot reason about this chain, allow this event to run
			return false, nil
		}

		checkSuiteID := workflowRun.CheckSuiteNodeID
		n := 3

		for j := 0; j < n; j++ {
			if checkSuiteID == "" {
				// We don't know the previous check suite id, we cannot detect a cycle
				return false, nil
			}

			// Get previous run state
			buildState, ok, err := i.repo.GetStateByCheckSuiteID(ctx, types.NewGlobalID(ctx, checkSuiteID))
			if err != nil {
				return false, errors.Wrap(err, "could not fetch workflow build state for previous workflow run")
			}

			if !ok || (buildState.Event != flowevents.WorkflowRun && buildState.Event != flowevents.Deployment && buildState.Event != flowevents.DeploymentStatus) {
				// If we don't know the previous workflow build, or it wasn't triggered by a `workflow_run` event or a `deployment` event or a `deployment_status` event
				// cannot detect a cycle
				i.obs.Debug(ctx, "workflow_run cycle detection done, no cycle",
					kvp.Int("gh.launch.workflow_run_cycle.max_depth", n),
					kvp.Int("gh.launch.workflow_run_cycle.cycles_count", j),
				)
				return false, nil
			}

			if strings.EqualFold(buildState.WorkflowFilePath, workflowPath) {
				// We have detected a cycle!
				i.obs.Debug(ctx, "workflow_run cycle detection found a cycle",
					kvp.Int("gh.launch.workflow_run_cycle.max_depth", n),
					kvp.Int("gh.launch.workflow_run_cycle.cycles_count", j),
					kvp.String("gh.launch.cycle_workflow_path", buildState.WorkflowFilePath),
					kvp.String("gh.launch.cycle_check_suite_id", checkSuiteID),
				)
				return true, nil
			}

			// Update any legacy global IDs in the workflow payload to the Next Global ID format
			newPayload, err := globalidmigration.ConvertPayloadIDs(ctx, &i.obs.Observability, i.ghTwirpClient,
				"workflowinvoker.buildinvoker.hasworkflowcycle", buildState.EventPayload)
			if err != nil {
				i.obs.Report(ctx, errors.Wrap(err, "error encountered while trying to convert workflow payload global IDs"))
			} else {
				buildState.EventPayload = newPayload
			}

			event, err := flowevents.ParseEventWebHook(buildState.Event, buildState.EventPayload)
			if err != nil {
				// Allow the workflow to continue
				return false, errors.New("cannot parse previous workflow payload")
			}

			if workflowRunEvent, ok := event.(*githubgo.WorkflowRunEvent); ok {
				workflowRun = workflowRunEvent.GetWorkflowRun()
			} else if deploymentEvent, ok := event.(*githubgo.DeploymentEvent); ok {
				workflowRun = deploymentEvent.GetWorkflowRun()
			} else if deploymentStatusEvent, ok := event.(*githubgo.DeploymentStatusEvent); ok {
				workflowRun = deploymentStatusEvent.GetWorkflowRun()
			} else {
				return false, errors.New("previous workflow run payload is not a supported event")
			}

			if workflowRun == nil {
				return false, errors.New("cannot find previous workflow run event")
			}

			checkSuiteID = workflowRun.CheckSuiteNodeID
		}

		i.obs.Debug(ctx, "workflow_run cycle detection ran until max step, aborting workflow run", kvp.Int("gh.launch.workflow_run_cycle.max_depth", n))
		return true, nil
	}

	if deploymentEvent, ok := event.(*githubgo.DeploymentEvent); ok {
		previousWorkflow := deploymentEvent.GetWorkflow()
		if previousWorkflow != nil && strings.EqualFold(previousWorkflow.Name, workflowIdentifier) {
			i.obs.Debug(ctx, "deployment loop detected",
				kvp.String("gh.launch.workflow.identifier", workflowIdentifier),
			)
			return true, nil
		}
	}

	if deploymentStatusEvent, ok := event.(*githubgo.DeploymentStatusEvent); ok {
		previousWorkflow := deploymentStatusEvent.GetWorkflow()
		if previousWorkflow != nil && strings.EqualFold(previousWorkflow.Name, workflowIdentifier) {
			i.obs.Debug(ctx, "deployment status loop detected",
				kvp.String("gh.launch.workflow.identifier", workflowIdentifier),
			)
			return true, nil
		}
	}

	return false, nil
}

func (i *buildInvoker) GetRepositoryTier(ctx context.Context, repoID types.GlobalID) (types.RepositoryTier, error) {
	if i.isEnterprise {
		return types.RepositoryTier1, nil
	}

	tier, err := tiers.FetchRepositoryTier(ctx, i.obs.Logger, i.ghTwirpClient, repoID)
	if err != nil {
		return types.RepositoryTier3, err
	}

	return tier, nil
}

// By default, we won't run fork pull request workflows on public repositories if the actor is not trusted
func (i *buildInvoker) isActionRequired(
	ctx context.Context,
	repoID types.GlobalID,
	event InvokingEvent,
	existingCheckSuite *types.CheckSuiteState,
	usePRAuthor bool,
) (bool, error) {
	// This function shouldn't be called during re-runs
	if existingCheckSuite != nil {
		// Approving an Action Required run sends a check suite rerequest event (same as re-runs)
		// See https://github.com/github/security-reviews/issues/340 for more details
		// If this isn't the first attempt, we can assume the actor is trusted as they have permissions
		// to approve or rerun the workflow
		return false, nil
	}

	isRestrictedForkPREvent := flowevents.IsRestrictedForkPREvent(event.Name, event.Ghe)
	if !isRestrictedForkPREvent {
		return false, nil
	}

	if usePRAuthor {
		pr, isPullRequestBasedEvent := event.Ghe.(flowevents.HasPullRequest)
		if !isPullRequestBasedEvent {
			return false, nil
		}

		author := pr.GetPullRequest().GetUser().GetNodeID()
		if author == "" {
			i.obs.Report(ctx, fmt.Errorf("unexpected empty PR author id for PR"),
				kvp.String("gh.repo.owner.global_id", repoID.String()),
				kvp.String("gh.pull_request.id", pr.GetPullRequest().GetNodeID()))

			// We can't know if the PR author is trusted or not, assume untrusted
			return true, nil
		}

		shouldRunWorkflows, err := i.ghTwirpClient.ShouldPullRequestWorkflowsRunForUser(ctx, repoID, ghtwirp.PullRequestEventUsers{
			Actor:  i.invocation.TriggeringActor.ID,
			Author: types.NewGlobalID(ctx, author),
		})
		if err != nil {
			err := errors.Wrap(err, "Could not retrieve info for ShouldPullRequestWorkflowsRunForUser")
			i.obs.Report(ctx, err)

			// Avoid making a decision when there's an error and allow the event to be retried
			return false, err
		}

		return !shouldRunWorkflows, nil
	}

	// Use the actor that triggered the run
	// Since this isn't a re-run/rerequest event, this should be the same as the executing actor
	user := i.invocation.TriggeringActor.ID

	// If the event is a pull request closed or labeled event, we should use the PR author as the user
	// The actor that triggered the event may not be the PR author
	if event.Name == flowevents.PullRequest && (event.Action == flowevents.PullRequestClosedAction || event.Action == flowevents.PullRequestLabeledAction) {
		prEvent, ok := event.Ghe.(*githubgo.PullRequestEvent)
		if ok {
			prAuthorID := prEvent.GetPullRequest().GetUser().GetNodeID()
			if prAuthorID == "" {
				i.obs.Report(ctx, fmt.Errorf("unexpected empty PR author id for PR"),
					kvp.String("gh.repo.owner.global_id", repoID.String()),
					kvp.String("gh.pull_request.id", prEvent.GetPullRequest().GetNodeID()))

				// We can't know if the PR author is trusted or not, assume untrusted
				return true, nil
			}
			user = types.NewGlobalID(ctx, prAuthorID)
		}
	}

	shouldRunWorkflows, err := i.ghTwirpClient.ShouldPullRequestWorkflowsRunForUser(ctx, repoID, ghtwirp.PullRequestEventUsers{Actor: user})
	if err != nil {
		i.obs.Report(ctx, errors.Wrap(err, "Could not retrieve info for ShouldPullRequestWorkflowsRunForUser"))
		return false, nil
	}
	return !shouldRunWorkflows, nil
}

func logWorkflowCallUsageMetrics(ctx context.Context, obs *observability.Observability, localRefs, remoteRefs int) {
	hasLocalRefs := localRefs > 0
	hasRemoteRefs := remoteRefs > 0

	obs.Counter(ctx, metrickeys.CallableWorkflowRuns, statter.Tags{
		"has_workflow_calls": strconv.FormatBool(hasLocalRefs || hasRemoteRefs),
		"has_local_refs":     strconv.FormatBool(hasLocalRefs),
		"has_remote_refs":    strconv.FormatBool(hasRemoteRefs),
	}, 1)
	if hasLocalRefs {
		obs.Distribution(ctx, metrickeys.CallableWorkflowsRefs, statter.Tags{
			"ref": "local",
		}, float64(localRefs))
	}
	if hasRemoteRefs {
		obs.Distribution(ctx, metrickeys.CallableWorkflowsRefs, statter.Tags{
			"ref": "remote",
		}, float64(remoteRefs))
	}
}

func analyzeCallableRefs(wfb *build.WorkflowBuild) (int, int) {
	callerRepoID := wfb.RunEnvironment.RepositoryID
	localRefs := 0
	for _, rf := range wfb.ReferencedFiles {
		if rf.RepositoryID.IsEquivalent(callerRepoID) {
			localRefs++
		}
	}

	remoteRefs := len(wfb.ReferencedFiles) - localRefs
	return localRefs, remoteRefs
}

// getSecretStore determines the secret source to use for the given workflow run. Any change to this method should be considered high risk.
func (i *buildInvoker) getSecretStore(ctx context.Context, repoID types.GlobalID, b *build.WorkflowBuild) (build.SecretStore, error) {
	var actor *metadata.WorkflowMetadataActor
	if i.workflowMetadata != nil {
		actor = i.workflowMetadata.Actor
	}

	secretSource := workflowbuild.DetermineSecretSource(ctx, &i.obs.Observability, b.Event, b.GitHubEvent, i.data.ForkPRWorkflowsPolicy, actor)
	i.obs.Debug(ctx, "determined secret source to use", kvp.String("gh.launch.secret.source", secretSource.String()))

	switch secretSource {
	case workflowbuild.ActionsSecretSource:
		secretsAppID := i.actionsAppGlobalID
		return newSecretStore(ctx, i.kredzClient, i.ghTwirpClient, i.secretDecryptor, i.data, repoID, secretsAppID, secretSource, i.obs.Logger)

	case workflowbuild.DependabotSecretSource:
		if i.dependabotAppGlobalID == "" {
			// The configuration was not supplied with a global ID for Dependabot so we return a nilSecretStore.
			i.obs.Report(ctx, errors.New("can't use dependabot secrets, dependabot app global id unknown"))
			return &nilSecretStore{}, nil
		}
		secretsAppID := i.dependabotAppGlobalID
		return newSecretStore(ctx, i.kredzClient, i.ghTwirpClient, i.secretDecryptor, i.data, repoID, secretsAppID, secretSource, i.obs.Logger)

	case workflowbuild.NoSecretSource:
		return &nilSecretStore{}, nil

	default:
		i.obs.Error(ctx, "skipping secrets because secret source is unknown", kvp.String("gh.launch.secret.source", secretSource.String()))
		return &nilSecretStore{}, nil
	}
}

// If either feature flag is enabled, create a WorkflowTemplate from actions-workflow-parser
// unless this is a partial rerun of a workflow that has reusable workflows
func shouldRunParserComparison(compareErrors, comparePlans bool, b *build.WorkflowBuild) bool {
	// We want at least one of the flags enabled
	if !compareErrors && !comparePlans {
		return false
	}

	// If it's a partial rerun
	if b.RerunInfo != nil {
		// We don't want to compare anything if there are any reusable workflows
		return len(b.ResolvedFiles) <= 1
	}

	// Finally, a flag is enabled and it's not a partial rerun with a reusable workflow, so run it!
	return true
}

func (i *buildInvoker) createRepoTenantInfo(billingOwner build.ActionsBillingPlanOwner) *types.RepositoryTenantInfo {
	repoTenantInfo := &types.RepositoryTenantInfo{
		RepoTenantInfo: i.azpClient.GetRunTenantInfo(),
	}

	repoTenantInfo.OwnerTenantInfo = &twirpv1.TenantInfo{
		Id: billingOwner.TenantID,
		Urls: map[string]string{
			"PipelinesService": billingOwner.TenantURL,
		},
	}

	if billingOwner.Type == "Business" {
		repoTenantInfo.OwnerTenantInfo = &twirpv1.TenantInfo{
			Id: billingOwner.OrganizationTenantID,
			Urls: map[string]string{
				"PipelinesService": billingOwner.OrganizationTenantURL,
			},
		}

		repoTenantInfo.EnterpriseTenantInfo = &twirpv1.TenantInfo{
			Id: billingOwner.TenantID,
			Urls: map[string]string{
				"PipelinesService": billingOwner.TenantURL,
			},
		}
	}

	return repoTenantInfo
}
