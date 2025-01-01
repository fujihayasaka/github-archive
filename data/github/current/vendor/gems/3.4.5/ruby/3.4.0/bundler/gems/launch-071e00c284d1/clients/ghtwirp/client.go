package ghtwirp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/fatih/semgroup"
	"github.com/github/go-kvp"
	twirpauth "github.com/github/go-twirp/client/auth"
	twirprequestid "github.com/github/go-twirp/client/requestid"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	twirpTrustTiers "github.com/github/monolith-twirp-trusttiers/proto/trusttier/v1"
	"github.com/google/uuid"
	"github.com/twitchtv/twirp"

	ghactions "github.com/github/launch/proto/monolith/core/v1"
	"github.com/github/launch/workflowparser"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/cache/cachemem"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/graphqlid"
	"github.com/github/launch/utils/requestid"
	"github.com/github/launch/utils/useragent"

	// Note:  prefer golang's built-in "errors" package over these:
	errs "github.com/pkg/errors"

	terrors "github.com/github/launch/types/errors"
)

const (
	// Plans exposed in github/github  app/models/actions_plan_owner.rb
	EnterprisePlan       = "enterprise"
	EnterpriseTrialPlan  = "enterprise_trial"
	FreePlan             = "free"
	FreeOrganizationPlan = "free_organization"
	ProPlan              = "pro"
	TeamPlan             = "team"

	InvalidType      = "Invalid"
	UserType         = "User"
	TeamType         = "Team"
	BusinessType     = "Business"
	OrganizationType = "Organization"
	RepositoryType   = "Repository"
	BotType          = "Bot"

	repoCanUseActionsCacheExpires        = 30 * time.Second
	isFeatureEnabledForActorCacheExpires = 30 * time.Second
	trustTierCacheExpires                = 3 * time.Hour
	repoAccountDetailsCacheExpires       = 3 * time.Hour
	globalIDCacheExpires                 = 24 * time.Hour
	repoOwnerIDCacheExpires              = 1 * time.Hour
	userByLoginCacheExpires              = 1 * time.Hour
	repositoryVisibilityCacheExpires     = 1 * time.Minute

	// FindRepositoriesByName twirp call has a limit of 100 repositories per call.
	FindRepositoriesByNameMaxBatchSize = 100

	ResolveActionsBatchSize = 20
)

// Client defines the interface for fetching information about users and
// repositories from GitHub.
type Client interface {
	CreateRerunExecution(ctx context.Context, input *RerunExecutionInput) error
	IsRepositoryActionsDisabled(ctx context.Context, repositoryID types.GlobalID) (bool, error)
	IsUserSpammy(ctx context.Context, actorGID types.GlobalID) (bool, error)
	IsUserFromDatabaseIDSpammy(ctx context.Context, userID int64) (bool, error)
	IsFeatureEnabledForActor(ctx context.Context, featureFlag string, actorGID types.GlobalID) bool
	IsFeatureEnabledForActors(ctx context.Context, featureFlag string, actorGIDs []types.GlobalID) bool
	IsFeatureEnabledForRepoOrOwners(ctx context.Context, featureFlag string, repoID types.GlobalID) bool
	IsFeatureEnabledForRepository(ctx context.Context, featureFlag string, id int64) bool
	IsFeatureEnabledGlobally(ctx context.Context, featureFlag string) bool
	CheckActionsAllowedByPolicy(ctx context.Context, repositoryID types.GlobalID, actions []string, includeLocalOnlyActions bool, shouldIgnoreRepoPolicies bool) (*ActionsPolicyInfo, error)
	CheckWorkflowsAllowedByPolicy(ctx context.Context, repositoryID types.GlobalID, workflows []string, shouldIgnoreRepoPolicies bool) (*WorkflowsPolicyInfo, error)
	ResolveEnvironment(ctx context.Context, environmentName string, repositoryID types.GlobalID) (*Environment, error)
	GetEnvironmentRepository(ctx context.Context, environmentGlobalID types.GlobalID) (int64, error)
	GetActorsInfo(ctx context.Context, actors []types.GlobalID) (*ActorsInfo, error)
	ShouldPullRequestWorkflowsRunForUser(ctx context.Context, repositoryID types.GlobalID, users PullRequestEventUsers) (bool, error)
	GetBillingDetails(ctx context.Context, repositoryID types.GlobalID) (*WorkflowBillingDetails, error)
	GetBillingDetailsForEntity(ctx context.Context, entityID types.GlobalID, productSku string) (*WorkflowBillingDetails, error)
	GetAccountDetails(ctx context.Context, entityID types.GlobalID) (*AccountDetails, error)
	GetRepositoryOwnersByName(ctx context.Context, nwo string) (*RepositoryOwners, error)
	GetRepositoryOwners(ctx context.Context, repoID int64) (*RepositoryOwners, error)
	GetRepositoryOwnerID(ctx context.Context, repoID int64, useCache bool) (int64, error)
	GetOrganizationOwner(ctx context.Context, orgID int64) (*OrganizationOwner, error)
	GetCommitMessage(ctx context.Context, repoID int64, commitSHA types.CommitSha) (types.CommitMessage, error)
	GetRepositories(ctx context.Context, ownerID int64) ([]*ghactions.Repository, error)
	GetTrustTier(ctx context.Context, id types.GlobalID) (types.RepositoryTier, error)
	GetUserByLogin(ctx context.Context, login string) (int64, types.GlobalID, error)
	RetireNamespace(ctx context.Context, nwo string) error
	FindRepositoriesByName(ctx context.Context, nwos []string) (*RepositoriesInfo, error)
	GetIntegrationJobSecrets(ctx context.Context, integrationName string, repositoryID, workflowRunID int64, bareJobName, environmentName string, isHostedRunner bool, dynamicEvent *flowevents.DynamicEvent) (map[string]string, error)
	IsDependabotAssociatedRef(ctx context.Context, repositoryID int64, ref string) (bool, error)
	GetNextGlobalID(ctx context.Context, legacyOrNextGID string) (types.GlobalID, error)
	GetNextGlobalIDs(ctx context.Context, legacyOrNextGIDs []string) (nextGlobalIDMap map[string]types.GlobalID, allIDsFound bool, err error)
	GetAdditionalWorkflows(ctx context.Context, repoID int64, event EventReference) (*AdditionalWorkflows, error)
	UpdateWorkflowRun(ctx context.Context, repoID types.GlobalID, workflowRunID int64, name string) error
	UpdateWorkflowRunExecution(ctx context.Context, repoID types.GlobalID, workflowRunID int64, runStampURL string) error
	GetRepositoryEventDetails(ctx context.Context, repoID int64) (string, error)
	GetRepositoryVisibility(ctx context.Context, repoID int64) (ghactions.RepositoryVisibility, error)
	FindTreeIDAndPreviousWorkflowRunToReuse(ctx context.Context, repoID types.GlobalID, workflowPath string, eventType string, commitSHA types.CommitSha) (types.CommitSha, *ReusableCheckSuite, error)
	GetAccountDetailsForRepository(ctx context.Context, repoID types.GlobalID) (*RepositoryAccountDetails, error)
	ResolveActions(ctx context.Context, actions []*Action, workflowRunID int64, jobID string, workflowRepoID int64, shouldInstrumentRequest bool, isHostedRunner bool) ([]*ResolveActionsResponse, error)
	GetWorkflowRunExecution(ctx context.Context, checkSuiteGlobalID types.GlobalID, planID uuid.UUID) (*WorkflowRunExecutionResponse, error)
}

var _ Client = (*client)(nil)

// client is a wrapper around the GitHub Twirp client.
type client struct {
	usersClient                 UsersService
	reposClient                 ReposService
	checksClient                ChecksService
	actionsFeaturesClient       MonolithFeaturesService
	actionsPoliciesClient       ActionsPoliciesService
	actionsEnvironmentsClient   ActionsEnvironmentsService
	trustTiersClient            TrustTiersService
	workflowDetailsClient       WorkflowDetailsService
	accountDetailsClient        AccountDetailsService
	resolveActionsClient        ResolveActionsService
	workflowRunExecutionsClient WorkflowRunExecutionsService
	obs                         *observability.Observability
	env                         string
	twirpCache                  launchcache.GitHubTwirpCache
	actorsClient                ActorsService
	integrationsClient          IntegrationsService
	refsClient                  RefsService
	globalIDClient              GlobalIDService
	isMultiTenant               bool
}

type RerunExecutionInput struct {
	RepositoryID        types.GlobalID
	WorkflowRunID       int64
	ActorID             types.GlobalID
	PlanID              types.WorkflowExecutionID
	Attempt             int64
	ExecutionGraph      string
	ReferencedWorkflows string
}

// An Actions environment
type Environment struct {
	GlobalID types.GlobalID
}

type WorkflowBillingDetails struct {
	IsActionsUsageAllowed   bool
	IsActionsStorageAllowed bool
	IsOwnerSpammy           bool
}

type AccountDetails struct {
	AccountType    string `json:"accountType"`
	CustomerID     int64  `json:"customerId"`
	IsBillingOwner bool   `json:"isBillingOwner"`
	TrustTier      int64  `json:"trustTier"`
}

type Entity struct {
	ID        int64
	GlobalID  types.GlobalID
	Name      string
	Type      string
	CreatedAt time.Time
}

type RepositoryOwners struct {
	Repository    Entity
	Owner         Entity
	OwnerPlanName string
	Business      *Entity
}

type ActorsInfo struct {
	Actors []*ghactions.Actor
}

func (r *RepositoryOwners) OnEnterprisePlan() bool {
	return r.OwnerPlanName == EnterprisePlan || r.OwnerPlanName == EnterpriseTrialPlan
}

type OrganizationOwner struct {
	Organization         Entity
	OrganizationPlanName string
	Business             *Entity
}

type ActionsPolicyInfo struct {
	IsExecutionAllowed        bool
	PolicyErrorMessage        string
	LocalOnlyActions          []string
	AreInternalActionsAllowed bool
	ArePrivateActionsAllowed  bool
}

type RepositoriesInfo struct {
	Repositories                     []*ghactions.Repository
	RepositoriesNotFoundErrorMessage string
}

type WorkflowsPolicyInfo struct {
	IsExecutionAllowed bool
	PolicyErrorMessage string
}

type RequiredWorkflow struct {
	RepoID          types.GlobalID
	OwnerID         types.GlobalID
	RepoNwo         string
	Path            string
	Ref             string
	RepoDatabaseID  int64
	RepoVisibility  ghactions.RepositoryVisibility
	WorkflowFileSha string
}

type AdditionalWorkflows struct {
	RulesetWorkflows []*RequiredWorkflow
}

type ReusableCheckSuite struct {
	GlobalID   types.GlobalID
	DatabaseID int64
}

type RepositoryAccountDetails struct {
	OwnerType ghactions.RepositoryOwner
	PlanName  ghactions.PlanName
}

type Action struct {
	Nwo  string
	Ref  string
	Path string
}

type ResolveActionsResponse struct {
	ResolvedAction *ghactions.ResolvedAction
	Error          *ResolveActionsErr
}

type ResolveActionsErr struct {
	Action    *Action
	Err       error
	ErrorCode int64
}

func (err *ResolveActionsErr) MatchesStatusCode(code int) bool {
	return code == int(err.ErrorCode)
}

func (o *OrganizationOwner) OnEnterprisePlan() bool {
	return o.OrganizationPlanName == EnterprisePlan || o.OrganizationPlanName == EnterpriseTrialPlan
}

type HTTPClient interface {
	Do(req *http.Request) (*http.Response, error)
}

// newSheddingEnabledClient wraps the next client adding
// X-Load-Shedding-Enabled to all outgoing requests.
//
// This additional header enables the Api::Middleware::LoadShedding middleware
// on github/github. Enabling the unicorns serving the internal-api to drop
// requests that have queued for longer than their propagated deadline and also
// propagate the deadline to further services.
//
// Requiring this header to enable this middleware should be temporary while we
// roll it out, in the future the addition of X-Client-Timeout-Ms will be all
// that is required.
//
// See: github/launch#4668 for changes to enabled propagating X-Client-Timeout-Ms.
// See: github/ecosystem-api#2715 for more details on this project.
func newSheddingEnabledClient(next HTTPClient) HTTPClient {
	return &sheddingEnabledClient{next: next}
}

type sheddingEnabledClient struct {
	next HTTPClient
}

func (sec *sheddingEnabledClient) Do(r *http.Request) (*http.Response, error) {
	r.Header.Add("X-Load-Shedding-Enabled", "true")

	return sec.next.Do(r)
}

// NewClient instantiates an instance of the GitHub Twirp client.
func NewClient(
	addr string,
	secret string,
	obs *observability.Observability,
	env string,
	twirpCache launchcache.GitHubTwirpCache,
	httpClient HTTPClient,
	twirpOpts []twirp.ClientOption,
	isMultiTenant bool,
) (*client, error) {
	forwardingClient := twirprequestid.NewForwarder(httpClient)
	shedClient := newSheddingEnabledClient(forwardingClient)
	rateLimitClient := newRateLimitHandler(shedClient, obs)
	twirpClient, err := twirpauth.NewRequestHMACSigner(secret, rateLimitClient)
	if err != nil {
		return nil, err
	}

	usersClient := ghactions.NewUsersAPIProtobufClient(addr, twirpClient, twirpOpts...)
	reposClient := ghactions.NewRepositoriesAPIProtobufClient(addr, twirpClient, twirpOpts...)
	actorsClient := ghactions.NewActorsAPIProtobufClient(addr, twirpClient, twirpOpts...)
	actionsEnvironmentClient := ghactions.NewEnvironmentsAPIProtobufClient(addr, twirpClient, twirpOpts...)
	actionsPoliciesClient := ghactions.NewPoliciesAPIProtobufClient(addr, twirpClient, twirpOpts...)
	workflowDetailsClient := ghactions.NewWorkflowDetailsAPIProtobufClient(addr, twirpClient, twirpOpts...)
	accountDetailsClient := ghactions.NewAccountDetailsAPIProtobufClient(addr, twirpClient, twirpOpts...)
	trustTiersClient := twirpTrustTiers.NewTrustTierAPIProtobufClient(addr, twirpClient, twirpOpts...)
	checksClient := ghactions.NewChecksAPIProtobufClient(addr, twirpClient, twirpOpts...)
	integrationsClient := ghactions.NewIntegrationsAPIProtobufClient(addr, twirpClient, twirpOpts...)
	refsClient := ghactions.NewRefsAPIProtobufClient(addr, twirpClient, twirpOpts...)
	globalIDClient := ghactions.NewGlobalIdAPIProtobufClient(addr, twirpClient, twirpOpts...)
	resolveActionsClient := ghactions.NewResolveActionsAPIProtobufClient(addr, twirpClient, twirpOpts...)
	actionsFeaturesClient := twirpFeatures.NewFeaturesAPIProtobufClient(addr, twirpClient, twirpOpts...)
	workflowRunExecutionsClient := ghactions.NewWorkflowRunExecutionsAPIProtobufClient(addr, twirpClient, twirpOpts...)

	return &client{
		usersClient:                 usersClient,
		reposClient:                 reposClient,
		actorsClient:                actorsClient,
		actionsEnvironmentsClient:   actionsEnvironmentClient,
		actionsFeaturesClient:       actionsFeaturesClient,
		actionsPoliciesClient:       actionsPoliciesClient,
		checksClient:                checksClient,
		workflowDetailsClient:       workflowDetailsClient,
		accountDetailsClient:        accountDetailsClient,
		trustTiersClient:            trustTiersClient,
		integrationsClient:          integrationsClient,
		refsClient:                  refsClient,
		globalIDClient:              globalIDClient,
		resolveActionsClient:        resolveActionsClient,
		workflowRunExecutionsClient: workflowRunExecutionsClient,
		obs:                         obs,
		env:                         env,
		twirpCache:                  twirpCache,
		isMultiTenant:               isMultiTenant,
	}, nil
}

func (c *client) setUserAgent(ctx context.Context) (context.Context, error) {
	header, ok := twirp.HTTPRequestHeaders(ctx)
	if !ok {
		header = make(http.Header)
	}

	header.Set("User-Agent", useragent.GetUserAgent(c.env))
	ctx, err := twirp.WithHTTPRequestHeaders(ctx, header)
	if err != nil {
		return ctx, errs.Wrap(err, "error setting headers")
	}

	return ctx, nil
}

// NewMockTestClient returns a new client that allows us to use mock
// implementations.
func NewMockTestClient(usersClient UsersService, reposClient ReposService, actionsEnvironmentClient ActionsEnvironmentsService, actionsFeaturesClient twirpFeatures.FeaturesAPI, actionsPoliciesClient ActionsPoliciesService, trustTiersClient twirpTrustTiers.TrustTierAPI, workflowDetailsClient WorkflowDetailsService, accountDetailsClient AccountDetailsService, checksClient ChecksService, actorsClient ActorsService, integrationsClient IntegrationsService, globalIDClient GlobalIDService, resolveActionsClient ResolveActionsService, workflowRunExecutionsClient WorkflowRunExecutionsService, isMultitenant bool) *client {
	ghTwirpCache := launchcache.NewNamespacedCache(cachemem.NewExpiringCache(1<<20), observability.NewTestObservability()).GitHubTwirp()
	return &client{
		usersClient:                 usersClient,
		reposClient:                 reposClient,
		actionsEnvironmentsClient:   actionsEnvironmentClient,
		actionsFeaturesClient:       actionsFeaturesClient,
		actionsPoliciesClient:       actionsPoliciesClient,
		trustTiersClient:            trustTiersClient,
		workflowDetailsClient:       workflowDetailsClient,
		accountDetailsClient:        accountDetailsClient,
		checksClient:                checksClient,
		actorsClient:                actorsClient,
		integrationsClient:          integrationsClient,
		obs:                         observability.NewNullObservability(),
		twirpCache:                  ghTwirpCache,
		globalIDClient:              globalIDClient,
		resolveActionsClient:        resolveActionsClient,
		workflowRunExecutionsClient: workflowRunExecutionsClient,
		isMultiTenant:               isMultitenant,
	}
}

// CreateRerunExecution will create a workflow_run_execution in dotcom.
func (c *client) CreateRerunExecution(ctx context.Context, input *RerunExecutionInput) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	_, err = c.checksClient.CreateExecution(ctx, &ghactions.CreateExecutionRequest{
		RepositoryId:        &ghactions.Identity{GlobalId: input.RepositoryID.String()},
		WorkflowRunId:       input.WorkflowRunID,
		ActorId:             &ghactions.Identity{GlobalId: input.ActorID.String()},
		PlanId:              input.PlanID.String(),
		Attempt:             input.Attempt,
		ExecutionGraph:      input.ExecutionGraph,
		ReferencedWorkflows: input.ReferencedWorkflows,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		c.obs.Error(ctx, errs.Wrap(err, "error creating rerun execution").Error())
		return tracing.RecordError(span, err)
	}

	return nil
}

// IsRepositoryActionsDisabled checks to see if the repository is deleted,
// archived, spammy, or in an otherwise bad state that will disable Actions.
func (c *client) IsRepositoryActionsDisabled(ctx context.Context, repoGID types.GlobalID) (bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	cache := c.twirpCache.RepoCanUseActionsCacheFor(repoGID)

	data, cacheHit, err := cache.Get(ctx)
	if err != nil {
		c.obs.Report(ctx, errs.Wrap(err, "failed to look up cache"))
	}
	if cacheHit {
		var canUse bool
		if err := json.Unmarshal(data, &canUse); err != nil {
			c.obs.Report(ctx, errors.New("invalid IsRepositoryActionsDisabled response in cache"))
		} else {
			return !canUse, nil
		}
	}

	ctx, err = c.setUserAgent(ctx)
	if err != nil {
		return false, errs.Wrap(err, "error setting user agent")
	}

	repoID, err := graphqlid.DecodeInt64ID(repoGID.String())
	if err != nil {
		return false, tracing.RecordError(span, errs.Wrap(err, "error decoding repo global id"))
	}

	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.reposClient.CheckRepositoryActionsStatus(ctx, &ghactions.CheckRepositoryActionsStatusRequest{
		Id: repoID,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		c.obs.Report(ctx, tracing.RecordError(span, errs.Wrap(err, "error fetching repository")))
		return false, nil
	}
	canUse := res.GetCanUseActions()
	if cacheData, err := json.Marshal(canUse); err != nil {
		c.obs.Report(ctx, errs.Wrap(err, "encoding cache value to json"))
	} else if err := cache.Set(ctx, cacheData, repoCanUseActionsCacheExpires); err != nil {
		c.obs.Report(ctx, errs.Wrap(err, "setting value in cache"))
	}

	if !canUse {
		c.obs.Logger.Debug(ctx, "repository can't use Actions", kvp.String("gh.repo.global_id", string(repoGID)), kvp.String("reason", res.GetReason()))
	}

	return !canUse, nil
}

// CheckActionsAllowedByPolicy verifies that a list of Actions are allowed to be used
// by a repository based on Policy settings.
//
// If isExecutionAllowed returns false. An errorMessage will also be included describing
// why the Actions were not allowed by the policy.
func (c *client) CheckActionsAllowedByPolicy(ctx context.Context, repositoryID types.GlobalID, actions []string, includeLocalOnlyActions bool, shouldIgnoreRepoPolicies bool) (*ActionsPolicyInfo, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return nil, err
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.actionsPoliciesClient.CheckActionsPolicy(ctx, &ghactions.CheckActionsPolicyRequest{
		RepositoryId:             &ghactions.Identity{GlobalId: repositoryID.String()},
		Actions:                  actions,
		IncludeLocalOnlyActions:  includeLocalOnlyActions,
		ShouldIgnoreRepoPolicies: shouldIgnoreRepoPolicies,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		c.obs.Error(ctx, errs.Wrap(err, "error checking actions policy").Error(), kvp.String("gh.repo.global_id", repositoryID.String()))
		return nil, err
	}

	return &ActionsPolicyInfo{
		IsExecutionAllowed:        res.GetIsExecutionAllowed(),
		PolicyErrorMessage:        res.GetErrorMessage(),
		LocalOnlyActions:          res.GetLocalOnlyActions(),
		AreInternalActionsAllowed: res.GetAreInternalActionsAllowed(),
		ArePrivateActionsAllowed:  res.GetArePrivateActionsAllowed(),
	}, nil
}

// CheckWorkflowsAllowedByPolicy verifies that a list of workflows are allowed to be used
// by a repository based on Policy settings.
//
// If isExecutionAllowed returns false. An errorMessage will also be included describing
// why the workflows were not allowed by the policy.
func (c *client) CheckWorkflowsAllowedByPolicy(ctx context.Context, repositoryID types.GlobalID, workflows []string, shouldIgnoreRepoPolicies bool) (*WorkflowsPolicyInfo, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return nil, err
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.actionsPoliciesClient.CheckWorkflowsPolicy(ctx, &ghactions.CheckWorkflowsPolicyRequest{
		RepositoryId:             &ghactions.Identity{GlobalId: repositoryID.String()},
		Workflows:                workflows,
		ShouldIgnoreRepoPolicies: shouldIgnoreRepoPolicies,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		c.obs.Error(ctx, errs.Wrap(err, "error checking workflows policy").Error(), kvp.String("gh.repo.global_id", repositoryID.String()))
		return nil, err
	}

	return &WorkflowsPolicyInfo{
		IsExecutionAllowed: res.GetIsExecutionAllowed(),
		PolicyErrorMessage: res.GetErrorMessage(),
	}, nil
}

// ResolveEnvironment returns an Actions environment for a given name and repository
func (c *client) ResolveEnvironment(ctx context.Context, environment string, repositoryID types.GlobalID) (*Environment, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return nil, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.actionsEnvironmentsClient.ResolveActionsEnvironment(ctx, &ghactions.ResolveActionsEnvironmentRequest{
		Environment: environment,
		RepositoryId: &ghactions.Identity{
			GlobalId: repositoryID.String(),
		},
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		c.obs.Error(ctx, errs.Wrap(err, "error resolving actions environment").Error(), kvp.String("gh.repo.global_id", repositoryID.String()))
		return nil, tracing.RecordError(span, err)
	}

	return &Environment{
		GlobalID: types.NewGlobalID(ctx, res.GetEnvironment().GetEnvironmentId().GetGlobalId()),
	}, nil
}

// GetEnvironmentRepository returns the dotcom database id of the repository
// where the given environment is present in.
func (c *client) GetEnvironmentRepository(ctx context.Context, environmentGlobalID types.GlobalID) (int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return 0, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.actionsEnvironmentsClient.GetEnvironmentRepository(ctx, &ghactions.GetEnvironmentRepositoryRequest{
		EnvironmentId: &ghactions.Identity{
			GlobalId: environmentGlobalID.String(),
		},
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		c.obs.Error(ctx, errs.Wrap(err, "error getting environment repository").Error(), kvp.String("gh.environment.global_id", environmentGlobalID.String()))
		return 0, tracing.RecordError(span, err)
	}

	return res.RepositoryDatabaseId, nil
}

type PullRequestEventUsers struct {
	Actor  types.GlobalID
	Author types.GlobalID
}

// ShouldPullRequestWorkflowsRunForUser checks to see if pull request workflows
// should be run for a user
func (c *client) ShouldPullRequestWorkflowsRunForUser(ctx context.Context, repositoryID types.GlobalID, users PullRequestEventUsers) (bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return false, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	req := ghactions.ShouldPullRequestWorkflowsRunForUserRequest{
		User: &ghactions.Identity{
			GlobalId: users.Actor.String(),
		},
		Repository: &ghactions.Identity{
			GlobalId: repositoryID.String(),
		},
	}

	if !users.Author.IsZeroValue() {
		req.Author = &ghactions.Identity{
			GlobalId: users.Author.String(),
		}
	}

	res, err := c.usersClient.ShouldPullRequestWorkflowsRunForUser(ctx, &req)
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		c.obs.Error(ctx, errs.Wrap(err, "error calling ShouldPullRequestWorkflowsRunForUser").Error(), kvp.String("gh.repo.global_id", repositoryID.String()))
		return false, tracing.RecordError(span, err)
	}

	return res.GetRunWorkflows(), nil
}

// IsUserSpammy checks to see if the user is spammy or suspended by checking
// their visibility status.
func (c *client) IsUserSpammy(ctx context.Context, userGID types.GlobalID) (bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	nodeType, userIDStr, err := graphqlid.Decode(userGID.String())
	if err != nil {
		return false, tracing.RecordError(span, errs.Wrap(err, "error decoding user global id"))
	}

	if nodeType != UserType && nodeType != OrganizationType && nodeType != BotType {
		c.obs.Debug(ctx, "skipping spammy check for non-user type", kvp.String("graphql.node.type", nodeType))
		return false, nil
	}
	userID, err := strconv.ParseInt(userIDStr, 10, 64)
	if err != nil {
		return false, tracing.RecordError(span, errs.Wrap(err, "error parsing int from user id string"))
	}

	isSpammy, err := c.isUserSpammy(ctx, userID)
	if err != nil {
		return false, tracing.RecordError(span, err)
	}

	return isSpammy, nil
}

func (c *client) IsUserFromDatabaseIDSpammy(ctx context.Context, userID int64) (bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	isSpammy, err := c.isUserSpammy(ctx, userID)
	if err != nil {
		return false, tracing.RecordError(span, err)
	}

	return isSpammy, nil
}

// IsFeatureEnabledForActors checks if a feature flag is enabled for at least one of the multiple actors passed in.
func (c *client) IsFeatureEnabledForActors(ctx context.Context, featureFlag string, actorGIDs []types.GlobalID) bool {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	actors := make([]string, 0, len(actorGIDs))
	for _, actorGID := range actorGIDs {
		actor, err := actorGID.ToFeaturesActorID()
		if err != nil {
			c.obs.Error(ctx, errs.Wrap(err, "error getting features actor ID").Error(), kvp.String("gh.actor.global_id", actorGID.String()))
			return false
		}
		actors = append(actors, actor)
	}

	return c.isFeatureEnabledForFeatureActors(ctx, featureFlag, actors)
}

// isFeatureEnabledForFeatureActors checks if a feature flag is enabled for at least one of the multiple feature actors passed in
func (c *client) isFeatureEnabledForFeatureActors(ctx context.Context, featureFlag string, actors []string) bool {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return false
	}

	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.actionsFeaturesClient.CheckActorsFeature(ctx, &twirpFeatures.CheckActorsFeatureRequest{
		ActorIds: actors,
		Feature:  featureFlag,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		c.obs.Error(ctx, errs.Wrap(err, "error checking feature flag for actors").Error())
		return false
	}

	var isEnabled bool
	for _, result := range res.Results {
		if result.IsEnabled {
			isEnabled = result.IsEnabled
			break
		}
	}

	return isEnabled
}

// IsFeatureEnabledForActor checks if a feature is enabled for a single actor.
// Not compatible with dark-shipping features: it uses a cache and checks if the FF is enabled globally first.
func (c *client) IsFeatureEnabledForActor(ctx context.Context, featureFlag string, actorGID types.GlobalID) bool {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	// First check if the FF is fully enabled for the best cache hit rate.
	if c.IsFeatureEnabledGlobally(ctx, featureFlag) {
		return true
	}

	tags := statter.Tags{"scope": "actor"}
	defer func() {
		c.obs.Counter(ctx, "feature_flag.get", tags, 1)
	}()

	cache := c.twirpCache.FeatureFlagCacheFor(actorGID, featureFlag)
	jsonFlag, ok, err := cache.Get(ctx)
	if err != nil {
		tags["cache_hit"] = strconv.FormatBool(false)
		tags["cache_error"] = strconv.FormatBool(true)
		c.obs.Report(ctx, errs.Wrap(err, "failed to look up cache"))
	} else if ok {
		tags["cache_hit"] = strconv.FormatBool(true)
		var isEnabled bool
		err := json.Unmarshal(jsonFlag, &isEnabled)
		if err != nil {
			c.obs.Report(ctx, errors.New("invalid feature flag response in cache"))
		} else {
			return isEnabled
		}
	}
	tags["cache_hit"] = strconv.FormatBool(false)

	ctx, err = c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return false
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	isEnabled := c.IsFeatureEnabledForActors(ctx, featureFlag, []types.GlobalID{actorGID})

	// caching for future use
	isEnabledJSON, err := json.Marshal(isEnabled)
	if err != nil {
		c.obs.Report(ctx, errs.Wrap(err, "marshaling token to json for Set"))
		return isEnabled
	}

	cerr := cache.Set(ctx, isEnabledJSON, isFeatureEnabledForActorCacheExpires)
	if cerr != nil {
		c.obs.Report(ctx, errs.Wrap(cerr, "failed to write in cache"))
	}

	return isEnabled
}

// IsFeatureEnabledForRepoOrOwners checks if a feature is enabled for a repository, the repository's owner or its enterprise, if any.
// Not compatible with dark-shipping features: it uses a cache and checks if the FF is enabled globally first.
// Note: If you enable a FF for a percentage of actors, IsFeatureEnabledForRepoOrOwners will true a higher percentage of time due to checking multiple actors.
// Consider using IsFeatureEnabledForActor and a FF group instead. See https://github.com/github/c2c-actions-experience/issues/5945
func (c *client) IsFeatureEnabledForRepoOrOwners(ctx context.Context, featureFlag string, repoGID types.GlobalID) bool {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	// First check if the FF is fully enabled for the best cache hit rate.
	if c.IsFeatureEnabledGlobally(ctx, featureFlag) {
		return true
	}

	tags := statter.Tags{"scope": "repo_or_owners"}
	defer func() {
		c.obs.Counter(ctx, "feature_flag.get", tags, 1)
	}()

	cache := c.twirpCache.RepoOrOwnersFeatureFlagCacheFor(repoGID, featureFlag)
	jsonFlag, ok, err := cache.Get(ctx)
	if err != nil {
		tags["cache_hit"] = strconv.FormatBool(false)
		tags["cache_error"] = strconv.FormatBool(true)
		c.obs.Report(ctx, errs.Wrap(err, "failed to look up cache"))
	} else if ok {
		tags["cache_hit"] = strconv.FormatBool(true)
		var isEnabled bool
		err := json.Unmarshal(jsonFlag, &isEnabled)
		if err != nil {
			c.obs.Report(ctx, errors.New("invalid feature flag response in cache"))
		} else {
			return isEnabled
		}
	}
	tags["cache_hit"] = strconv.FormatBool(false)

	ffActors := []types.GlobalID{repoGID}
	owners, ownerErr := c.getRepositoryOwners(ctx, repoGID)
	if ownerErr != nil {
		c.obs.Report(ctx, errs.Wrap(ownerErr, "Failed to get repository owners"),
			kvp.String("gh.repo.global_id", repoGID.String()),
			kvp.String("code.function", "IsFeatureEnabledForRepoOrOwners"))
	} else {
		ffActors = append(ffActors, owners...)
	}

	isEnabled := c.IsFeatureEnabledForActors(ctx, featureFlag, ffActors)

	// caching for future use
	if isEnabled || ownerErr == nil {
		isEnabledJSON, err := json.Marshal(isEnabled)
		if err != nil {
			c.obs.Report(ctx, errs.Wrap(err, "marshaling token to json for Set"))
			return isEnabled
		}

		cerr := cache.Set(ctx, isEnabledJSON, isFeatureEnabledForActorCacheExpires)
		if cerr != nil {
			c.obs.Report(ctx, errs.Wrap(cerr, "failed to write in cache"))
		}
	}

	return isEnabled
}

// IsFeatureEnabledGlobally checks if a feature is enabled globally.
// Not compatible with dark-shipping features, as it caches the result.
func (c *client) IsFeatureEnabledGlobally(ctx context.Context, featureFlag string) bool {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	tags := statter.Tags{"scope": "global"}
	defer func() {
		c.obs.Counter(ctx, "feature_flag.get", tags, 1)
	}()

	// NilGlobalId represents global scope for feature flag
	cache := c.twirpCache.FeatureFlagCacheFor(types.NilGlobalID, featureFlag)
	jsonFlag, ok, err := cache.Get(ctx)
	if err != nil {
		tags["cache_hit"] = strconv.FormatBool(false)
		tags["cache_error"] = strconv.FormatBool(true)
		c.obs.Report(ctx, errs.Wrap(err, "failed to look up cache"))
	} else if ok {
		tags["cache_hit"] = strconv.FormatBool(true)
		var isEnabled bool
		err := json.Unmarshal(jsonFlag, &isEnabled)
		if err != nil {
			c.obs.Report(ctx, errors.New("invalid feature flag response in cache"))
		} else {
			return isEnabled
		}
	}
	tags["cache_hit"] = strconv.FormatBool(false)

	ctx, err = c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return false
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.actionsFeaturesClient.CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{
		Feature: featureFlag,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		c.obs.Error(ctx, errs.Wrap(err, "error checking feature flag globally").Error(), kvp.String("feature_flag.key", featureFlag))
		return false
	}

	// Monitor which FFs evaluate to globally enabled.
	c.obs.Statter.Counter(ctx, "check_global_feature", statter.Tags{"feature_flag": featureFlag, "globally_enabled": strconv.FormatBool(res.IsEnabled)}, 1)

	isEnabled := res.IsEnabled

	// Cache this response for 30 seconds.
	isEnabledJSON, err := json.Marshal(isEnabled)
	if err != nil {
		c.obs.Report(ctx, errs.Wrap(err, "marshaling token to json for Set"))
		return isEnabled
	}

	cerr := cache.Set(ctx, isEnabledJSON, 30*time.Second)
	if cerr != nil {
		c.obs.Report(ctx, errs.Wrap(cerr, "failed to write in cache"))
	}

	return isEnabled
}

// GetActorsInfo fetches information about an array of actors; in the event that an actor isn't found a nil is returned
// Can be Users, Organizations, Enterprises, or Repositories
func (c *client) GetActorsInfo(ctx context.Context, actors []types.GlobalID) (*ActorsInfo, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return nil, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	ctx, err = ghtenant.ContextWithSerializeLoginHeader(ctx, ghtenant.SerializeLoginDisplay, c.isMultiTenant)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "unable to set context login header").Error())
		return nil, tracing.RecordError(span, err)
	}

	var identities []*ghactions.Identity

	for _, a := range actors {
		identity := ghactions.Identity{
			GlobalId: a.String(),
		}

		identities = append(identities, &identity)
	}

	res, err := c.actorsClient.GetActorsInfo(ctx, &ghactions.GetActorsInfoRequest{
		ActorGlobalIds: identities,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		var actorGIDStrings []string
		for _, a := range actors {
			actorGIDStrings = append(actorGIDStrings, a.String())
		}
		c.obs.Error(ctx, errs.Wrap(err, "error fetching actors info").Error(), kvp.String("gh.launch.actor.global_ids.csv", strings.Join(actorGIDStrings, ",")))
		return nil, tracing.RecordError(span, err)
	}

	return &ActorsInfo{
		Actors: res.GetActors(),
	}, nil
}

// GetBillingDetails fetches the Actions billing details for a given repository.
func (c *client) GetBillingDetails(ctx context.Context, repositoryID types.GlobalID) (*WorkflowBillingDetails, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return nil, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.workflowDetailsClient.GetBillingDetails(ctx, &ghactions.GetBillingDetailsRequest{
		RepositoryId: &ghactions.Identity{
			GlobalId: repositoryID.String(),
		},
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		c.obs.Error(ctx, errs.Wrap(err, "error fetching workflow billing details").Error(), kvp.String("gh.repo.global_id", repositoryID.String()))
		return nil, tracing.RecordError(span, err)
	}

	return &WorkflowBillingDetails{
		IsActionsStorageAllowed: res.GetIsActionsStorageAllowed(),
		IsActionsUsageAllowed:   res.GetIsActionsUsageAllowed(),
		IsOwnerSpammy:           res.GetIsOwnerSpammy(),
	}, nil
}

// GetBillingDetailsForEntity fetches the Actions billing details for a given entity.
func (c *client) GetBillingDetailsForEntity(ctx context.Context, entityID types.GlobalID, productSku string) (*WorkflowBillingDetails, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return nil, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.workflowDetailsClient.GetBillingDetailsForEntity(ctx, &ghactions.GetBillingDetailsForEntityRequest{
		EntityId: &ghactions.Identity{
			GlobalId: entityID.String(),
		},
		ProductSku: productSku,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		c.obs.Error(ctx, errs.Wrap(err, "error fetching workflow billing details").Error(), kvp.String("gh.repo.global_id", entityID.String()))
		return nil, tracing.RecordError(span, err)
	}

	return &WorkflowBillingDetails{
		IsActionsStorageAllowed: res.GetIsActionsStorageAllowed(),
		IsActionsUsageAllowed:   res.GetIsActionsUsageAllowed(),
		IsOwnerSpammy:           res.GetIsOwnerSpammy(),
	}, nil
}

// GetAccountDetails fetches the dotcom account details for a given entity.
func (c *client) GetAccountDetails(ctx context.Context, entityID types.GlobalID) (*AccountDetails, error) {
	i := twirpCallInfo{
		errorMsg:    "error fetching account details",
		errorFields: []kvp.Field{kvp.String("global_id", entityID.String())},
	}

	req := &ghactions.GetAccountDetailsRequest{
		EntityId: &ghactions.Identity{
			GlobalId: entityID.String(),
		},
	}

	res, err := makeTwirpCall(ctx, c, c.accountDetailsClient.GetAccountDetails, i, req)
	if err != nil {
		return nil, err
	}

	return &AccountDetails{
		AccountType:    res.GetAccountType(),
		IsBillingOwner: res.GetIsBillingOwner(),
		TrustTier:      res.GetTrustTier(),
		CustomerID:     res.GetCustomerId(),
	}, nil
}

func (c *client) GetRepositoryOwnersByName(ctx context.Context, nwo string) (*RepositoryOwners, error) {
	ctx = ctxstash.WithFields(ctx, kvp.String("gh.repo.name_with_owner", nwo))
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var err error
	if len(nwo) == 0 {
		err = errors.New("nwo parameter cannot be empty")
		c.obs.Error(ctx, "caller passed an empty NWO", kvp.Err(err))
		return nil, err
	}

	// Note that FindRepositoriesByName accepts an array of NWO inputs.
	// For our purposes, we're interested in just a single repo.
	repoInfos, err := c.FindRepositoriesByName(ctx, []string{nwo})
	if err != nil {
		c.obs.Error(ctx, "error fetching repository owner info by NWO", kvp.Err(err))
		return nil, err
	}

	// If you ask FindRepositoriesByName to find n repos and it finds fewer than n,
	// it signals the shortfall via RepositoriesInfo::RepositoriesNotFoundErrorMessage (essentially, a 'soft' error)
	// In our case, n=1, so treat the shortfall as an outright failure.
	if len(repoInfos.RepositoriesNotFoundErrorMessage) > 0 {
		err = terrors.NewNotFoundError(errors.New(repoInfos.RepositoriesNotFoundErrorMessage))
		c.obs.Error(ctx, "error locating any repo matching the specified NWO", kvp.Err(err))
		return nil, err
	}

	if len(repoInfos.Repositories) == 0 {
		err = errors.New("twirp FindRepositoriesByName returned an empty array but did not signal an error")
		c.obs.Error(ctx, err.Error(), kvp.Err(err))
		return nil, err
	}

	repoDatabaseID := repoInfos.Repositories[0].Id
	return c.GetRepositoryOwners(ctx, repoDatabaseID)
}

// GetRepositoryOwners looks up the repository's owner and enterprise (if there is one),
// plus the repo NWO
func (c *client) GetRepositoryOwners(ctx context.Context, repoID int64) (*RepositoryOwners, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return nil, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.reposClient.GetRepositoryOwners(ctx, &ghactions.GetRepositoryOwnersRequest{
		Id: repoID,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.error_code", string(twerr.Code())))
		}

		c.obs.Report(ctx, tracing.RecordError(span, errs.Wrap(err, "error fetching repository owners")))
		return nil, tracing.RecordError(span, err)
	}

	out := RepositoryOwners{
		Repository:    entityFromActor(ctx, res.GetRepository()),
		Owner:         entityFromActor(ctx, res.GetOwner()),
		OwnerPlanName: res.GetOwnerPlanName(),
	}
	if business := res.GetBusiness(); business != nil {
		actor := entityFromActor(ctx, business)
		out.Business = &actor
	}

	return &out, nil
}

// GetRepositoryOwnerID looks up the repository's owner's database id and caches the result for 1 hour
// If using this method, be mindful of repository transfers which will update the owner ID in dotcom
func (c *client) GetRepositoryOwnerID(ctx context.Context, repoID int64, useCache bool) (int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	cache := c.twirpCache.RepositoryOwnerIDCacheFor(repoID)

	if useCache {
		ownerID, cacheHit, err := cache.Get(ctx)
		if err != nil {
			c.obs.Report(ctx, errs.Wrap(err, "failed to look up repository owner ID in cache"))
		}

		if cacheHit {
			return ownerID, nil
		}
	}

	info := twirpCallInfo{
		errorMsg: "error fetching repository owner id",
	}

	req := &ghactions.GetRepositoryOwnerIdRequest{
		Id: repoID,
	}

	res, err := makeTwirpCall(ctx, c, c.reposClient.GetRepositoryOwnerId, info, req)
	if err != nil {
		return 0, tracing.RecordError(span, err)
	}

	out := res.OwnerId

	if err := cache.Set(ctx, out, repoOwnerIDCacheExpires); err != nil {
		c.obs.Report(ctx, errs.Wrap(err, "could not set RepositoryOwnerID cache value"))
	}

	return out, nil
}

// GetOrganizationOwner looks up the organizations's enterprise (if there is one),
// plus its name
func (c *client) GetOrganizationOwner(ctx context.Context, orgID int64) (*OrganizationOwner, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return nil, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.usersClient.GetOrganizationOwner(ctx, &ghactions.GetOrganizationOwnerRequest{
		Id: orgID,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("error_code", string(twerr.Code())))
		}

		c.obs.Report(ctx, tracing.RecordError(span, errs.Wrap(err, "error fetching organization owner")))
		return nil, tracing.RecordError(span, err)
	}

	out := OrganizationOwner{
		Organization:         entityFromActor(ctx, res.GetOrganization()),
		OrganizationPlanName: res.GetOrganizationPlanName(),
	}
	if business := res.GetBusiness(); business != nil {
		actor := entityFromActor(ctx, business)
		out.Business = &actor
	}

	return &out, nil
}

func (c *client) GetCommitMessage(ctx context.Context, repoID int64, commitSHA types.CommitSha) (msg types.CommitMessage, err error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err = c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return types.CommitMessageZeroValue, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.reposClient.GetCommitMessage(ctx, &ghactions.GetCommitMessageRequest{
		RepositoryId: repoID,
		CommitSha:    commitSHA.String(),
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("error_code", string(twerr.Code())))
		}

		err = tracing.RecordError(span, errs.Wrap(err, "error fetching message for commit"))
		c.obs.Report(ctx, err)
		return types.CommitMessageZeroValue, err
	}

	return types.CommitMessage(res.GetCommitMessage()), nil
}

func (c *client) GetRepositories(ctx context.Context, ownerID int64) (repositories []*ghactions.Repository, err error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err = c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return nil, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.usersClient.GetRepositories(ctx, &ghactions.GetRepositoriesRequest{
		OwnerId: ownerID,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("error_code", string(twerr.Code())))
		}

		err = tracing.RecordError(span, errs.Wrap(err, "error fetching repositories for user"))
		c.obs.Report(ctx, err)
		return nil, err
	}

	return res.Repositories, nil
}

func (c *client) FindRepositoriesByName(ctx context.Context, nwos []string) (repositoriesInfo *RepositoriesInfo, err error) {
	// Process request in batches of 100 nwos as twirp call supports max 100 repos per request.
	repos := make([]*ghactions.Repository, 0)
	repositoriesNotFoundErrorMessages := make([]string, 0)
	for index := 0; index < len(nwos); index += FindRepositoriesByNameMaxBatchSize {
		end := index + FindRepositoriesByNameMaxBatchSize
		if end > len(nwos) {
			end = len(nwos)
		}

		batchNwos := nwos[index:end]
		repositoriesInfoBatch, err := c.findRepositoriesByName(ctx, batchNwos)
		if err != nil {
			return nil, err
		}

		if repositoriesInfoBatch.Repositories != nil {
			repos = append(repos, repositoriesInfoBatch.Repositories...)
		}
		if repositoriesInfoBatch.RepositoriesNotFoundErrorMessage != "" {
			repositoriesNotFoundErrorMessages = append(repositoriesNotFoundErrorMessages, repositoriesInfoBatch.RepositoriesNotFoundErrorMessage)
		}
	}

	c.obs.Counter(ctx, "find_repositories_by_name_nwos_count", nil, int64(len(nwos)))
	repositoriesInfo = &RepositoriesInfo{
		Repositories:                     repos,
		RepositoriesNotFoundErrorMessage: strings.Join(repositoriesNotFoundErrorMessages, " "),
	}

	return repositoriesInfo, nil
}

func (c *client) GetTrustTier(ctx context.Context, id types.GlobalID) (types.RepositoryTier, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	tags := statter.Tags{}
	defer func() {
		c.obs.Counter(ctx, "trust_tier.get", tags, 1)
	}()

	cache := c.twirpCache.TrustTierCacheFor(id)

	tier, cacheHit, err := cache.Get(ctx)
	if err != nil {
		tags["cache_hit"] = strconv.FormatBool(false)
		tags["cache_error"] = strconv.FormatBool(true)
		c.obs.Report(ctx, errs.Wrap(err, "failed to look up cache"))
	}
	if cacheHit {
		tags["cache_hit"] = strconv.FormatBool(true)
		return types.RepositoryTier(tier), nil
	}
	tags["cache_hit"] = strconv.FormatBool(false)

	ctx, err = c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return types.RepositoryTier(-1), tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.trustTiersClient.GetTrustTier(ctx, &twirpTrustTiers.GetTrustTierRequest{
		Id: &twirpTrustTiers.Identity{GlobalId: id.String()},
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("error_code", string(twerr.Code())))
		}

		err = tracing.RecordError(span, errs.Wrap(err, "error fetching trust tier for global id"))
		c.obs.Report(ctx, err)
		return types.RepositoryTier(-1), err
	}

	if err := cache.Set(ctx, res.TrustTier, trustTierCacheExpires); err != nil {
		c.obs.Report(ctx, errs.Wrap(err, "setting value in cache"))
	}

	return types.RepositoryTier(res.TrustTier), nil
}

type userByLoginData struct {
	ID       int64          `json:"id"`
	GlobalID types.GlobalID `json:"global_id"`
}

func (c *client) GetUserByLogin(ctx context.Context, login string) (int64, types.GlobalID, error) {
	tags := statter.Tags{}
	defer func() {
		c.obs.Counter(ctx, "user_by_login.get", tags, 1)
	}()

	tenantID, err := ghtenant.TenantIDFromContext(ctx, c.isMultiTenant)
	if err != nil {
		return 0, types.NilGlobalID, err
	}

	cache := c.twirpCache.UserByLoginCacheFor(login, tenantID)
	cacheData, cacheHit, err := cache.Get(ctx)
	if err != nil {
		tags["cache_hit"] = strconv.FormatBool(false)
		tags["cache_error"] = strconv.FormatBool(true)
		c.obs.Logger.Error(ctx, errs.Wrap(err, "failed to look up user by login cache").Error())
	}

	tags["cache_hit"] = strconv.FormatBool(cacheHit)
	if cacheHit {
		var data userByLoginData
		if err := json.Unmarshal(cacheData, &data); err != nil {
			c.obs.Logger.Error(ctx, fmt.Errorf("failed to unmarshal user by login cache data: %w", err).Error())
		} else {
			return data.ID, data.GlobalID, nil
		}
	}

	tci := twirpCallInfo{
		errorMsg:        "error fetching user by login",
		setTenantHeader: true,
	}

	req := &ghactions.GetUserByLoginRequest{
		Login: login,
	}

	res, err := makeTwirpCall(ctx, c, c.usersClient.GetUserByLogin, tci, req)
	if err != nil {
		return 0, types.NilGlobalID, err
	}

	data := userByLoginData{
		ID:       res.Id,
		GlobalID: types.NewGlobalID(ctx, res.GetGlobalId().GetGlobalId()),
	}

	dataJSON, err := json.Marshal(data)
	if err != nil {
		c.obs.Logger.Error(ctx, fmt.Errorf("failed to marshal user by login cache data: %w", err).Error())
	} else {
		cerr := cache.Set(ctx, dataJSON, userByLoginCacheExpires)
		if cerr != nil {
			c.obs.Logger.Error(ctx, fmt.Errorf("failed to set user by login cache: %w", cerr).Error())
		}
	}

	return data.ID, data.GlobalID, nil
}

func (c *client) RetireNamespace(ctx context.Context, nwo string) (err error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err = ghtenant.ContextWithTwirpTenantHeaders(ctx, c.isMultiTenant, c.obs.Logger)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting tenant id").Error())
		return err
	}

	ctx, err = c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	_, err = c.reposClient.RetireNamespace(ctx, &ghactions.RetireNamespaceRequest{
		Nwo: nwo,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("error_code", string(twerr.Code())))
		}

		err = tracing.RecordError(span, errs.Wrap(err, "error retiring namespace"))
		c.obs.Error(ctx, "error retiring namespace", kvp.Err(err))
		return err
	}

	return nil
}

func (c *client) GetIntegrationJobSecrets(ctx context.Context, integrationName string, repositoryID, workflowRunID int64, bareJobName, environmentName string, isHostedRunner bool, dynamicEvent *flowevents.DynamicEvent) (map[string]string, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "error setting user agent"))
	}

	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.integrationsClient.GetIntegrationJobSecrets(ctx, &ghactions.GetIntegrationJobSecretsRequest{
		IntegrationName: integrationName,
		RepositoryId:    repositoryID,
		WorkflowRunId:   workflowRunID,
		BareJobName:     bareJobName,
		EnvironmentName: environmentName,
		IsHostedRunner:  isHostedRunner,
		DynamicWorkflow: &ghactions.DynamicWorkflow{
			Ref:             dynamicEvent.Ref,
			IntegrationName: dynamicEvent.IntegrationName,
			Inputs:          dynamicEvent.Inputs,
			WorkflowName:    dynamicEvent.WorkflowName,
			Slug:            dynamicEvent.Slug,
		},
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("error_code", string(twerr.Code())))
		}

		err = tracing.RecordError(span, errs.Wrap(err, "error retrieving integration secrets"))
		c.obs.Error(ctx, "error retrieving integration secrets", kvp.Err(err))
		return nil, err
	}

	return res.GetEncryptedSecrets(), nil
}

func (c *client) IsDependabotAssociatedRef(ctx context.Context, repositoryID int64, ref string) (bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		return false, tracing.RecordError(span, errs.Wrap(err, "error setting user agent"))
	}

	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.refsClient.IsDependabotAssociatedRef(ctx, &ghactions.IsDependabotAssociatedRefRequest{
		RepositoryId: repositoryID,
		Ref:          ref,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("error_code", string(twerr.Code())))
		}

		err = tracing.RecordError(span, errs.Wrap(err, "error checking if ref is associated with dependabot"))
		c.obs.Error(ctx, "error checking if ref is associated with dependabot", kvp.Err(err))
		return false, err
	}

	return res.GetIsDependabotAssociated(), nil
}

func (c *client) GetNextGlobalID(ctx context.Context, legacyOrNextGID string) (types.GlobalID, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if types.IsNextGlobalID(legacyOrNextGID) || types.IsZeroValueGlobalID(legacyOrNextGID) {
		return types.NewGlobalID(ctx, legacyOrNextGID), nil
	}

	// We know this is a legacy Global ID at this point
	legacyGID := legacyOrNextGID

	hasTwirpCache := c.twirpCache != nil

	var nextGlobalID types.GlobalID
	var cache launchcache.GitHubGlobalIDCache
	if hasTwirpCache {
		cache = c.twirpCache.GlobalIDCacheFor(legacyGID)
		nextGlobalID, cacheHit, err := cache.Get(ctx)
		if err != nil {
			c.obs.Report(ctx, errs.Wrap(err, "failed to look up cache"))
		}
		if cacheHit {
			return nextGlobalID, nil
		}
	}

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		return "", tracing.RecordError(span, errs.Wrap(err, "error setting user agent"))
	}

	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.globalIDClient.GetNextGlobalId(ctx, &ghactions.GetNextGlobalIdRequest{
		GlobalId: legacyGID,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("error_code", string(twerr.Code())))
		}

		err = tracing.RecordError(span, errs.Wrap(err, "error fetching next globalid"))
		c.obs.Error(ctx, "error fetching next globalid", kvp.Err(err), kvp.String("legacy_global_id", legacyGID))
		return "", err
	}

	nextGlobalID = types.NewGlobalID(ctx, res.GetNextGlobalId())
	if hasTwirpCache {
		if cerr := cache.Set(ctx, nextGlobalID, globalIDCacheExpires); cerr != nil {
			c.obs.Report(ctx, errs.Wrap(cerr, "setting value in cache"))
		}
	}

	return nextGlobalID, nil
}

func (c *client) GetNextGlobalIDs(ctx context.Context, legacyOrNextGIDs []string) (map[string]types.GlobalID, bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	// Convert the global ids to next global ids concurrently, up to 20 at a time.
	const maxWorkers = 20
	s := semgroup.NewGroup(ctx, maxWorkers)

	mu := &sync.Mutex{}
	allIDsFound := true
	results := make(map[string]types.GlobalID)
	for _, legacyOrNextGID := range legacyOrNextGIDs {
		legacyOrNextGID := legacyOrNextGID // https://golang.org/doc/faq#closures_and_goroutines

		s.Go(func() error {
			nextGlobalID, err := c.GetNextGlobalID(ctx, legacyOrNextGID)

			mu.Lock()
			defer mu.Unlock()

			if err != nil {
				if terrors.IsNotFoundError(err) {
					allIDsFound = false
					return nil
				}
				return err
			}

			results[legacyOrNextGID] = nextGlobalID
			return nil
		})
	}

	if err := s.Wait(); err != nil {
		c.obs.Error(ctx, "error fetching next globalids",
			kvp.Err(err),
			kvp.Int("gh.launch.global_ids_count", len(legacyOrNextGIDs)))

		return nil, false, err
	}

	return results, allIDsFound, nil
}

func (c *client) GetAdditionalWorkflows(ctx context.Context, repoID int64, event EventReference) (*AdditionalWorkflows, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return nil, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.reposClient.GetAdditionalWorkflows(ctx, &ghactions.GetAdditionalWorkflowsRequest{
		RepositoryId: repoID,
		EventType:    event.Type,
		BaseRef:      event.BaseRef.String(),
		BeforeOid:    event.BeforeOid.String(),
		AfterOid:     event.AfterOid.String(),
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("error_code", string(twerr.Code())))
		}

		c.obs.Error(ctx, errs.Wrap(err, "error fetching additional workflows for repository").Error(), kvp.Int64("gh.repo.id", repoID))

		return nil, tracing.RecordError(span, err)
	}

	c.obs.Debug(ctx, "Retrieved additional workflows",
		kvp.String("gh.launch.event.name", event.Type),
		kvp.Int("gh.launch.ruleset_workflows.count", len(res.RulesetWorkflows)),
	)

	additionalWorkflows := &AdditionalWorkflows{
		RulesetWorkflows: []*RequiredWorkflow{},
	}

	for _, rulesetWorkflow := range res.RulesetWorkflows {
		additionalWorkflows.RulesetWorkflows = append(additionalWorkflows.RulesetWorkflows, &RequiredWorkflow{
			RepoID:          types.NewGlobalID(ctx, rulesetWorkflow.GetRepositoryId().GetGlobalId()),
			OwnerID:         types.NewGlobalID(ctx, rulesetWorkflow.GetOwnerId().GetGlobalId()),
			RepoNwo:         rulesetWorkflow.RepositoryNwo,
			Path:            rulesetWorkflow.Path,
			Ref:             rulesetWorkflow.Ref,
			RepoDatabaseID:  rulesetWorkflow.RepoDatabaseId,
			RepoVisibility:  rulesetWorkflow.Visibility,
			WorkflowFileSha: rulesetWorkflow.WorkflowFileSha,
		})
	}

	return additionalWorkflows, nil
}

func (c *client) UpdateWorkflowRun(ctx context.Context, repoID types.GlobalID, workflowRunID int64, name string) error {
	i := twirpCallInfo{
		errorMsg: "error updating workflow run name",
	}

	req := &ghactions.UpdateWorkflowRunRequest{
		RepositoryId:  &ghactions.Identity{GlobalId: repoID.String()},
		WorkflowRunId: workflowRunID,
		RunName:       name,
	}

	_, err := makeTwirpCall(ctx, c, c.checksClient.UpdateWorkflowRun, i, req)
	if err != nil {
		return err
	}

	return nil
}

// UpdateWorkflowRunExecution updates the _latest_ workflow run execution on the workflow run specified by
// workflowRunID with the given runStampURL.
func (c *client) UpdateWorkflowRunExecution(ctx context.Context, repoID types.GlobalID, workflowRunID int64, runStampURL string) error {
	i := twirpCallInfo{
		errorMsg: "error updating workflow run execution",
	}

	req := &ghactions.UpdateWorkflowRunExecutionRequest{
		RepositoryId:  &ghactions.Identity{GlobalId: repoID.String()},
		WorkflowRunId: workflowRunID,
		RunStampUrl:   runStampURL,
	}

	_, err := makeTwirpCall(ctx, c, c.checksClient.UpdateWorkflowRunExecution, i, req)
	if err != nil {
		return err
	}

	return nil
}

func (c *client) GetRepositoryEventDetails(ctx context.Context, repoID int64) (string, error) {
	i := twirpCallInfo{
		errorMsg: "error getting repository event details",
	}

	req := &ghactions.GetRepositoryEventDetailsRequest{
		RepositoryId: repoID,
	}

	r, err := makeTwirpCall(ctx, c, c.reposClient.GetRepositoryEventDetails, i, req)
	if err != nil {
		return "", err
	}
	return r.EventPayload, nil
}

func (c *client) GetRepositoryVisibility(ctx context.Context, repoID int64) (ghactions.RepositoryVisibility, error) {
	// we are unable to resolve the visibility for a repository with an ID of 0 so return an invalid visibility. A repoID of 0
	// is expected for some usage such as large runners.
	if repoID == 0 {
		return ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INVALID, nil
	}

	tags := statter.Tags{}
	defer func() {
		c.obs.Counter(ctx, "repository_visibility.get", tags, 1)
	}()

	cache := c.twirpCache.RepositoryVisibilityCacheFor(repoID)
	cacheData, cacheHit, err := cache.Get(ctx)
	if err != nil {
		tags["cache_hit"] = strconv.FormatBool(false)
		tags["cache_error"] = strconv.FormatBool(true)
		c.obs.Logger.Error(ctx, errs.Wrap(err, "failed to get repo visibility cache").Error())
	}

	tags["cache_hit"] = strconv.FormatBool(cacheHit)
	if cacheHit {
		return ghactions.RepositoryVisibility(cacheData), nil
	}

	i := twirpCallInfo{
		errorMsg: "error getting repository visibility",
	}

	req := &ghactions.GetRepositoryVisibilityRequest{
		RepositoryId: repoID,
	}

	r, err := makeTwirpCall(ctx, c, c.reposClient.GetRepositoryVisibility, i, req)
	if err != nil {
		return ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INVALID, err
	} else {
		cerr := cache.Set(ctx, int32(r.Visibility), repositoryVisibilityCacheExpires)
		if cerr != nil {
			c.obs.Logger.Error(ctx, fmt.Errorf("failed to set repository visibility cache: %w", cerr).Error())
		}
	}

	return r.Visibility, nil
}

func (c *client) FindTreeIDAndPreviousWorkflowRunToReuse(ctx context.Context, repoID types.GlobalID, workflowPath string, eventType string, commitSHA types.CommitSha) (types.CommitSha, *ReusableCheckSuite, error) {
	i := twirpCallInfo{
		errorMsg: "error fetching treeId information and any previous workflow runs for reuse",
	}

	req := &ghactions.FindPreviousWorkflowRunToReuseRequest{
		RepositoryId: &ghactions.Identity{GlobalId: repoID.String()},
		WorkflowPath: workflowPath,
		EventType:    eventType,
		CommitSha:    commitSHA.String(),
	}

	r, err := makeTwirpCall(ctx, c, c.checksClient.FindPreviousWorkflowRunToReuse, i, req)
	if err != nil {
		return types.CommitShaZeroValue, nil, err
	}

	if r.CheckSuiteToClone != nil {
		return types.CommitSha(r.TreeId), &ReusableCheckSuite{
			GlobalID:   types.NewGlobalID(ctx, r.CheckSuiteToClone.CheckSuiteGlobalId.GlobalId),
			DatabaseID: r.CheckSuiteToClone.CheckSuiteDatabaseId,
		}, nil
	}

	return types.CommitSha(r.TreeId), nil, nil
}

func (c *client) GetAccountDetailsForRepository(ctx context.Context, repoID types.GlobalID) (*RepositoryAccountDetails, error) {
	tags := statter.Tags{}
	defer func() {
		c.obs.Counter(ctx, "get_account_details_for_repository.get", tags, 1)
	}()

	cache := c.twirpCache.RepoAccountDetailsCacheFor(repoID)

	cacheData, cacheHit, err := cache.Get(ctx)
	if err != nil {
		tags["cache_hit"] = strconv.FormatBool(false)
		tags["cache_error"] = strconv.FormatBool(true)
		c.obs.Report(ctx, errs.Wrap(err, "failed to look up cache"))
	}
	if cacheHit {
		tags["cache_hit"] = strconv.FormatBool(true)
		var repoAccountDetails RepositoryAccountDetails
		err := json.Unmarshal(cacheData, &repoAccountDetails)
		if err != nil {
			return &repoAccountDetails, nil
		}
	}
	tags["cache_hit"] = strconv.FormatBool(false)

	i := twirpCallInfo{
		errorMsg: "error fetching account details for the given repository",
	}

	req := &ghactions.GetAccountDetailsForRepositoryRequest{
		RepositoryId: &ghactions.Identity{
			GlobalId: repoID.String(),
		},
	}

	resp, err := makeTwirpCall(ctx, c, c.accountDetailsClient.GetAccountDetailsForRepository, i, req)
	if err != nil {
		return nil, err
	}

	repoAccountDetails := &RepositoryAccountDetails{
		OwnerType: resp.AccountType,
		PlanName:  resp.PlanName,
	}

	cacheData, err = json.Marshal(repoAccountDetails)
	if err != nil {
		c.obs.Report(ctx, errs.Wrap(err, "encoding cache value to json"))
		return repoAccountDetails, nil
	}

	err = cache.Set(ctx, cacheData, repoAccountDetailsCacheExpires)
	if err != nil {
		c.obs.Report(ctx, errs.Wrap(err, "setting value in cache"))
	}

	return repoAccountDetails, nil
}

func (c *client) ResolveActions(ctx context.Context, actions []*Action, workflowRunID int64, jobID string, workflowRepoID int64, shouldInstrumentRequest bool, isHostedRunner bool) ([]*ResolveActionsResponse, error) {
	i := twirpCallInfo{
		errorMsg: "error resolving actions with twirp",
	}

	c.obs.Logger.Log(ctx, "resolving actions with twirp", kvp.Int64("gh.repo.id", workflowRepoID), kvp.Int64("gh.launch.workflow_run.id", workflowRunID), kvp.Int64("gh.launch.actions_count", int64(len(actions))))

	ctx, err := ghtenant.ContextWithTwirpTenantHeaders(ctx, c.isMultiTenant, c.obs.Logger)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting tenant id").Error())
		return nil, err
	}

	const (
		OriginalEducationActionNWO            = "education/autograding"
		NewEducationActionNWO                 = "classroom-resources/autograding"
		EducationToClassroomResourcesSwapFlag = "education_to_classroom_resources_swap"
	)

	// For more information see https://github.com/github/classroom/issues/4828
	educationFlagIsEnabled := c.IsFeatureEnabledForRepository(ctx, EducationToClassroomResourcesSwapFlag, workflowRepoID)
	envIsDotcom := launchconfig.IsDotcom()

	resolveActionsResponse := make([]*ResolveActionsResponse, 0)
	for index := 0; index < len(actions); index += ResolveActionsBatchSize {
		end := index + ResolveActionsBatchSize
		if end > len(actions) {
			end = len(actions)
		}

		batchActions := actions[index:end]
		respItr := 0

		req := &ghactions.ResolveActionsRequest{
			WorkflowRunId:           workflowRunID,
			WorkflowRepoId:          workflowRepoID,
			JobId:                   jobID,
			ShouldInstrumentRequest: shouldInstrumentRequest,
			IsHostedRunner:          isHostedRunner,
		}

		req.Actions = make([]*ghactions.Action, 0)
		for _, action := range batchActions {
			// For internally owned education/autograding repo we allow redirect to classroom-resources/autograding
			// We'll be tracking how frequently this occurs with Datadog with the intention of removing the code when
			// it's near zero - for more information see https://github.com/github/classroom/issues/4828
			if envIsDotcom && educationFlagIsEnabled && action.Nwo == OriginalEducationActionNWO {
				c.obs.Statter.Counter(ctx, "classroom_action_substitution", nil, 1)
				c.obs.Logger.Log(ctx, "swapping education/autograding with classroom-resources/autograding", kvp.Int64("gh.repo.id", workflowRepoID), kvp.Int64("gh.launch.workflow_run.id", workflowRunID))
				action.Nwo = NewEducationActionNWO
			}
			req.Actions = append(req.Actions, &ghactions.Action{
				Nwo: action.Nwo,
				Ref: action.Ref,
			})
		}

		resp, err := makeTwirpCall(ctx, c, c.resolveActionsClient.ResolveActions, i, req)
		if err != nil {
			return nil, err
		}

		// The resolve action endpoint guarantees to return the response array
		// in the same order as that of the request array including errors
		for _, resolvedAction := range resp.ResolvedActions {
			switch respType := resolvedAction.GetResolvedActionContent().(type) {
			case *ghactions.ResolvedActionContent_ResolvedAction:
				// If the original action name doesn't match up with what we are returned as
				// the response action name, we probably have a redirect repo response. So we
				// always assign the input action's name as the resolved action's name

				if !strings.EqualFold(respType.ResolvedAction.Name, batchActions[respItr].Nwo) {
					respType.ResolvedAction.Name = strings.ToLower(batchActions[respItr].Nwo)
				}

				resolveActionsResponse = append(resolveActionsResponse, &ResolveActionsResponse{
					ResolvedAction: respType.ResolvedAction,
				})
			case *ghactions.ResolvedActionContent_Error:
				resolveActionsResponse = append(resolveActionsResponse, &ResolveActionsResponse{
					Error: &ResolveActionsErr{
						Action: &Action{
							Nwo:  batchActions[respItr].Nwo,
							Ref:  batchActions[respItr].Ref,
							Path: batchActions[respItr].Path,
						},
						Err:       errs.New(respType.Error.ErrorMessage),
						ErrorCode: respType.Error.ErrorCode,
					},
				})
			}

			respItr++
		}
	}

	return resolveActionsResponse, nil
}

type WorkflowRunExecutionResponse struct {
	ReferencedWorkflows []workflowparser.ReferencedWorkflow
}

func (c *client) GetWorkflowRunExecution(ctx context.Context, checkSuiteGlobalID types.GlobalID, planID uuid.UUID) (*WorkflowRunExecutionResponse, error) {
	i := twirpCallInfo{
		errorMsg: "error getting workflow run execution with twirp",
	}

	c.obs.Logger.Log(ctx, "Getting workflow run execution", kvp.String("gh.check_suite.global_id", checkSuiteGlobalID.String()), kvp.String("gh.launch.execution.id", planID.String()))

	ctx, err := ghtenant.ContextWithTwirpTenantHeaders(ctx, c.isMultiTenant, c.obs.Logger)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting tenant id").Error())
		return nil, err
	}

	req := &ghactions.GetWorkflowRunExecutionRequest{
		CheckSuiteGlobalId:             &ghactions.Identity{GlobalId: checkSuiteGlobalID.String()},
		WorkflowRunExecutionExternalId: planID.String(),
	}
	resp, err := makeTwirpCall(ctx, c, c.workflowRunExecutionsClient.GetWorkflowRunExecution, i, req)
	if err != nil {
		return nil, err
	}

	result := &WorkflowRunExecutionResponse{}
	if resp.ReferencedWorkflows != "" {
		rws := []workflowparser.ReferencedWorkflow{}
		err = json.Unmarshal([]byte(resp.ReferencedWorkflows), &rws)
		if err != nil {
			return nil, err
		}
		result.ReferencedWorkflows = rws
	}

	return result, nil
}

type twirpCallInfo struct {
	errorMsg    string
	errorFields []kvp.Field

	// setTenantHeader sets the Twirp Tenant header in Proxima
	// This should only be used for APIs that do not provide enough
	// information to determine the tenant from the request in the Twirp handler
	setTenantHeader bool
}

func makeTwirpCall[TReq any, TRes any](ctx context.Context, c *client, handler func(context.Context, *TReq) (*TRes, error), i twirpCallInfo, req *TReq) (*TRes, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error setting user agent").Error())
		return nil, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	if i.setTenantHeader {
		ctx, err = ghtenant.ContextWithTwirpTenantHeaders(ctx, c.isMultiTenant, c.obs.Logger)
		if err != nil {
			c.obs.Error(ctx, errs.Wrap(err, "error setting tenant id").Error())
			return nil, err
		}
	}

	r, err := handler(ctx, req)
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			fields := append(i.errorFields, kvp.String("error_code", string(twerr.Code())))
			ctx = ctxstash.WithFields(ctx, fields...)
		}

		c.obs.Error(ctx, errs.Wrap(err, i.errorMsg).Error())
		return nil, tracing.RecordError(span, err)
	}

	return r, nil
}

func (c *client) isUserSpammy(ctx context.Context, userID int64) (bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err := c.setUserAgent(ctx)
	if err != nil {
		return false, errs.Wrap(err, "error setting user agent")
	}

	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	res, err := c.usersClient.IsVisibleUser(ctx, &ghactions.IsVisibleUserRequest{
		UserId: userID,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("error_code", string(twerr.Code())))
			if twerr.Code() == twirp.NotFound {
				c.obs.Debug(ctx, "found user that is not visible", kvp.String("reason", "deleted"))
				return true, nil
			}
		}

		c.obs.Report(ctx, tracing.RecordError(span, errs.Wrap(err, "error checking if user is spammy")))
		return false, nil
	}

	isVisible := res.GetIsVisible()
	if !isVisible {
		c.obs.Debug(ctx, "found user that is not visible", kvp.String("reason", res.GetReason().String()))
	}

	return !isVisible, nil
}

func (c *client) getRepositoryOwners(ctx context.Context, repoGID types.GlobalID) ([]types.GlobalID, error) {
	objType, objDatabaseID, err := repoGID.Decode()
	if err != nil {
		return []types.GlobalID{}, errs.Wrap(err, "Failed to decode repoGlobalID for FF check")
	}

	if objType != RepositoryType {
		return []types.GlobalID{}, backoff.Permanent(errors.New("Wrong type for repoGID"))
	}

	repoInfo, err := c.GetRepositoryOwners(ctx, objDatabaseID)
	if err != nil {
		return []types.GlobalID{}, errs.Wrap(err, "Failed to get repository info for FF check")
	}

	owners := []types.GlobalID{repoInfo.Owner.GlobalID}
	if repoInfo.Business != nil {
		owners = append(owners, repoInfo.Business.GlobalID)
	}

	return owners, nil
}

func (c *client) findRepositoriesByName(ctx context.Context, nwos []string) (repositoriesInfo *RepositoriesInfo, err error) {
	if len(nwos) > FindRepositoriesByNameMaxBatchSize {
		return nil, errors.New("nwos length greater than supported size")
	}

	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, err = c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, "error setting user agent", kvp.Err(err))
		return nil, tracing.RecordError(span, err)
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	ctx, err = ghtenant.ContextWithTwirpTenantHeaders(ctx, c.isMultiTenant, c.obs.Logger)
	if err != nil {
		c.obs.Error(ctx, "error adding twirp tenant header to context", kvp.Err(err))
		return nil, tracing.RecordError(span, err)
	}

	res, err := c.reposClient.FindRepositoriesByName(ctx, &ghactions.FindRepositoriesByNameRequest{
		Nwos: nwos,
	})
	if err != nil {
		twerr, ok := err.(twirp.Error)
		if ok {
			ctx = ctxstash.WithFields(ctx, kvp.String("error_code", string(twerr.Code())))
		}

		err = tracing.RecordError(span, errs.Wrap(err, "error fetching repositories"))
		c.obs.Error(ctx, "error fetching repositories using nwos", kvp.Err(err))
		return nil, err
	}

	repositoriesInfo = &RepositoriesInfo{
		Repositories:                     res.GetRepositories(),
		RepositoriesNotFoundErrorMessage: res.GetRepositoriesNotFoundErrorMessage(),
	}

	return repositoriesInfo, nil
}

// The types exposed in enum in monolith/core/v1/actor.proto
var actorTypeMap = map[string]string{
	"TYPE_INVALID":      InvalidType,
	"TYPE_USER":         UserType,
	"TYPE_TEAM":         TeamType,
	"TYPE_BUSINESS":     BusinessType,
	"TYPE_ORGANIZATION": OrganizationType,
	"TYPE_REPOSITORY":   RepositoryType,
}

func entityFromActor(ctx context.Context, actor *ghactions.Actor) Entity {
	val, ok := actorTypeMap[actor.GetType().String()]
	if !ok {
		val = InvalidType
	}
	return Entity{
		ID:        actor.GetId(),
		GlobalID:  types.NewGlobalID(ctx, actor.GetGlobalId().GetGlobalId()),
		Name:      actor.GetIdString(),
		Type:      val,
		CreatedAt: actor.GetCreatedAt().AsTime(),
	}
}
