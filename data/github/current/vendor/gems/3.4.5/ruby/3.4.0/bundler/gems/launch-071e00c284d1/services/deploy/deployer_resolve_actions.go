package deploy

import (
	"context"
	fmt "fmt"
	http "net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/pkg/launchconfig"
	ghactions "github.com/github/launch/proto/monolith/core/v1"

	"github.com/github/launch/clients/authzd"
	"github.com/github/launch/clients/ghinternal"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/graphqlid"
	"github.com/github/launch/utils/requiredworkflowutils"
)

var RepositoryVisibilityValue = map[string]ghactions.RepositoryVisibility{
	"INVALID":  ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INVALID,
	"PUBLIC":   ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC,
	"PRIVATE":  ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE,
	"INTERNAL": ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INTERNAL,
}

type ownerToken struct {
	repositories repositorySet
	token        *tokens.AccessToken
	action       *pb.ActionReference
}

type resolvedActionWithVisibility struct {
	action                    *pb.ResolvedAction
	visibility                ghactions.RepositoryVisibility
	skipScopedTokenGeneration bool
}

type ActionRepoMetadata struct {
	areInternalActionsEnabled bool
	arePrivateActionsEnabled  bool
	isInternal                bool
	isPrivate                 bool
	workflowRepoID            types.GlobalID
	fromCache                 bool
	actionRepoID              int64
}

type WorkflowRepoBasedActionsResolveDecision struct {
	isSharingApplicable             bool
	shouldSkipScopedTokenGeneration bool
}

func newOwnerToken(token *tokens.AccessToken, action *pb.ActionReference, repos ...string) *ownerToken {
	return &ownerToken{
		repositories: newRepositorySet(repos),
		token:        token,
		action:       action,
	}
}

type repositorySet map[string]struct{}

func newRepositorySet(names []string) repositorySet {
	set := make(repositorySet)
	for _, name := range names {
		set.add(name)
	}
	return set
}

func (set repositorySet) add(name string) {
	set[name] = struct{}{}
}

func (set repositorySet) toSlice() []string {
	out := make([]string, 0, len(set))
	for k := range set {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

type resolveError struct {
	action *pb.ActionReference
	err    error
}

func (s *service) fetchTokenForRepos(ctx context.Context, owner string, ownerToken *ownerToken) (*tokens.AccessToken, error) {
	repos := ownerToken.repositories.toSlice()

	ownerID, _, err := s.cfg.GithubTwirpClient.GetUserByLogin(ctx, owner)
	if err != nil {
		return nil, errors.Wrapf(err, "fetching User ID for login %s", owner)
	}

	token, err := s.cfg.TokenService.ReadTokenForSiteScopedInstallation(ctx, ownerID, repos, false)
	if err != nil {
		return nil, errors.Wrapf(err, "requesting token for target repos for owner %v ", owner)
	}
	return token, nil
}

func (s *service) generateEmptyOwnerTokenMap(actions []*pb.ActionReference) (map[string]*ownerToken, error) {
	tokenMap := make(map[string]*ownerToken)
	// Iterate over the requested actions build the map of owner/repositories with empty tokens
	for _, action := range actions {
		repo, err := types.ParseNWO(action.Name)
		if err != nil {
			return nil, errors.Wrap(err, "parsing action name")
		}
		if ownerToken, found := tokenMap[repo.Owner]; found {
			ownerToken.repositories.add(repo.Name)
		} else {
			tokenMap[repo.Owner] = newOwnerToken(nil, action, repo.Name)
		}
	}
	return tokenMap, nil
}

func (s *service) getOwnerScopedTokenMap(ctx context.Context, actions []*pb.ActionReference) (map[string]*ownerToken, error) {
	if len(actions) == 0 {
		return nil, nil
	}
	tokenMap, err := s.generateEmptyOwnerTokenMap(actions)
	if err != nil {
		return nil, errors.Wrap(err, "unable to generate empty owner token map")
	}

	// Iterate over the actions owners and add tokens to the existing owner/repositories map
	s.cfg.Log.Debug(ctx, "Fetching scoped tokens for action repos under each owner",
		kvp.Int("gh.launch.actions_owners_count", len(tokenMap)),
	)
	for owner, ownerToken := range tokenMap {
		token, err := s.fetchTokenForRepos(ctx, owner, ownerToken)
		if err != nil {
			return nil, errors.Wrapf(err, "for action owner %q", owner)
		}
		ownerToken.token = token
	}
	return tokenMap, nil
}

//gocyclo:ignore
func (s *service) ResolveActions(ctx context.Context, r *pb.ResolveActionsRequest) (*pb.ResolveActionsResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.launch.workflow.identifier", r.GetWorkflowId()),
		kvp.String("gh.launch.job.id", r.GetJobId()),
	)
	wfbs, ok, err := s.cfg.WorkflowBuilds.GetDataForTokenRequest(ctx, r.WorkflowId)
	if err != nil {
		return nil, errors.Wrap(err, "failed to get build data")
	}
	if !ok {
		return nil, tracing.RecordError(span, svcerr.NewNotFoundError("No workflow could be found for the supplied workflow id"))
	}

	var tenantID int64
	if wfbs.GitHubTenantID != nil {
		tenantID = *wfbs.GitHubTenantID
	}

	ctx, ghTenantErr := ghtenant.ContextWithTenantID(ctx, tenantID, launchconfig.IsMultiTenant())
	if ghTenantErr != nil {
		return nil, errors.Wrap(ghTenantErr, "error setting github tenant ID in current context")
	}

	// Check policy before going further
	actionNameWithVersions := make([]string, 0, len(r.Actions))
	for _, action := range r.Actions {
		actionNameWithVersions = append(actionNameWithVersions, action.NameWithVersion())
	}

	localActionsOnly := s.IsEnterprise
	actionsPolicyInfo, err := s.cfg.GithubTwirpClient.CheckActionsAllowedByPolicy(ctx, wfbs.RepositoryID, actionNameWithVersions, localActionsOnly, requiredworkflowutils.IsRequiredWorkflow(wfbs.WorkflowFilePath))
	if err != nil {
		if terrors.IsNotFoundError(err) {
			return nil, svcerr.NewNotFoundError("Failed to retrieve Actions policy because the repository could not be found")
		}
		return nil, errors.Wrap(err, "failed to retrieve actions policy")
	}
	if !actionsPolicyInfo.IsExecutionAllowed {
		return nil, svcerr.NewFailedPrecondition(actionsPolicyInfo.PolicyErrorMessage)
	}

	// The Actions Resolve API does not need any specific permissions for public repositories, we just need an authenticated token
	// This token is also passed to the runner on GHES to access public repositories on private instances
	// For internal actions, these tokens should never be used to download an action
	// For actions resolved from Packages, these tokens should also never be used to download an action, since presigned URLs are used for packages
	actionResolvePermissions := &tokens.InstallationPermissions{
		Metadata: tokens.ReadAccess,
	}

	var token *tokens.AccessToken
	var resolveResponse *pb.ResolveActionsResponse
	tokenMap := make(map[string]*ownerToken)
	var actionRepoMap map[string]*Repository

	// Dotcom & Proxima Flow
	if !s.IsEnterprise {
		resolvedActionsResponse, err := s.resolveActionsWithTwirp(ctx, r.Actions, actionsPolicyInfo, wfbs.WorkflowRunID, r.JobId, wfbs.RepositoryID, r.IsHostedRunner)
		if err != nil {
			return nil, err
		}

		return resolvedActionsResponse, nil
	}

	// GHES Flow.
	if areInternalActionsEnabled(actionsPolicyInfo) || arePrivateActionsEnabled(actionsPolicyInfo) {
		// Always use scoped token for GHES
		token, err = s.cfg.TokenFactory.NewToken(ctx, wfbs.RepositoryID, actionResolvePermissions, nil)
		if err != nil {
			return nil, errors.Wrap(err, "failed to get the default token for resolving public actions")
		}

		actionRepoMap, tokenMap, resolveResponse, err = s.identifyActionsAndGenerateTokens(ctx, r.Actions, actionsPolicyInfo, wfbs.RepositoryID)
		if resolveResponse != nil {
			return resolveResponse, nil
		}
		if err != nil {
			return nil, err
		}
	} else if s.IsEnterprise {
		// Get a new read-only token without any specific permissions on it scoped to the caller repo for GHES
		token, err = s.cfg.TokenFactory.NewToken(ctx, wfbs.RepositoryID, actionResolvePermissions, nil)
		if err != nil {
			return nil, errors.Wrap(err, "failed to get default token")
		}
	}
	// For GHES, these are the set of actions that we won't try and fetch
	// via GH Connect if we don't find them on the local instance
	localOnlyActionsMap := make(map[string]bool)

	if s.IsEnterprise {
		for _, localOnlyAction := range actionsPolicyInfo.LocalOnlyActions {
			localOnlyActionsMap[localOnlyAction] = true
		}
	}

	s.cfg.Stats.Counter(ctx, "resolve_actions_count", nil, int64(len(r.Actions)))

	var (
		wg        sync.WaitGroup
		actionsCh = make(chan *resolvedActionWithVisibility, len(r.Actions))
		errorsCh  = make(chan *resolveError, len(r.Actions))
	)

	for _, action := range r.Actions {
		action := action // copy to a new variable

		wg.Add(1)
		go func() {
			defer wg.Done()
			actionRepoMetadata := s.getActionRepoMetadata(action, actionRepoMap, actionsPolicyInfo, wfbs.RepositoryID)
			fallbackToConnect := s.shouldFallbackToConnect(action, localOnlyActionsMap)
			resolved, err := s.resolveActionWithTokens(ctx, action, actionRepoMetadata, token, tokenMap, fallbackToConnect, wfbs.WorkflowRunID, r.JobId, actionRepoMap[strings.ToLower(action.Name)])
			if err != nil {
				errorsCh <- &resolveError{err: err, action: action}
			} else {
				actionsCh <- resolved
			}
		}()
	}

	wg.Wait()
	close(actionsCh)
	close(errorsCh)

	res := &pb.ResolveActionsResponse{}

	for resolveErr := range errorsCh {
		action := resolveErr.action
		err := resolveErr.err
		errMessage := fmt.Sprintf("Internal Server Error occurred while resolving %q", action.NameWithVersion())

		// We only want to return a custom error message if the underlying error message
		// comes from the GitHub internal API, otherwise we just return a generic
		// error message.
		ogErr, ok := errors.Cause(err).(*ghinternal.APIError)
		if ok {
			errMessage = ogErr.Error()
		}

		s.cfg.Log.Error(ctx, errMessage, kvp.String("gh.launch.action_name_version", action.NameWithVersion()), kvp.Err(err))
		res.Errors = append(res.Errors, &pb.ResolvedActionError{
			Action:  action,
			Message: errMessage,
		})
	}

	numRedirectedActions := 0
	for resolved := range actionsCh {
		res.Actions = append(res.Actions, resolved.action)
		if !strings.EqualFold(resolved.action.GetAction().GetName(), resolved.action.GetResolvedName()) {
			numRedirectedActions++
		}
	}

	s.cfg.Log.Log(ctx, "Resolved actions",
		kvp.Int("gh.launch.resolved_actions.count", len(res.Actions)),
		kvp.Int("gh.launch.redirected_actions.count", numRedirectedActions),
	)

	return res, nil
}

func (s *service) identifyActionsAndGenerateTokens(ctx context.Context, actions []*pb.ActionReference, actionsPolicyInfo *ghtwirp.ActionsPolicyInfo, workflowRepoID types.GlobalID) (map[string]*Repository, map[string]*ownerToken, *pb.ResolveActionsResponse, error) {
	tokenMap := make(map[string]*ownerToken)
	var actionRepoMap map[string]*Repository
	var repositoriesNotFoundErrorMessage string
	var err error
	isNonEnterpriseRepo := !areInternalActionsEnabled(actionsPolicyInfo) && arePrivateActionsEnabled(actionsPolicyInfo)

	// Get list of unique action repositories
	uniqueActionRepoNames := getUniqueActionRepositoryNames(actions)

	// Get repo IDs and visibility of actions referenced, by action names
	actionRepoMap, repositoriesNotFoundErrorMessage, err = s.findRepositoriesMetadata(ctx, uniqueActionRepoNames, arePrivateActionsEnabled(actionsPolicyInfo))
	if err != nil {
		return nil, nil, nil, errors.Wrap(err, "could not get repositories from name")
	}

	// Fail in case of GHEC if any of the action repositories are not found.
	// Continue for non-enterprise repos to support action redirects.
	// Also continue for GHES as we will try resolving the not found actions repositories using GitHub Connect later.
	if !isNonEnterpriseRepo && !s.IsEnterprise && s.cfg.ResolverTokenFactory == nil && (len(actionRepoMap) != len(uniqueActionRepoNames) || repositoriesNotFoundErrorMessage != "") {
		errMsg := fmt.Sprintf("Unable to resolve actions. %s", repositoriesNotFoundErrorMessage)
		return nil, nil, &pb.ResolveActionsResponse{Errors: []*pb.ResolvedActionError{{Message: errMsg}}}, nil
	}

	// Identify the actions to be identified for logging
	actionsToIdentify := whatActionsToIdentify(actionsPolicyInfo)

	// Identify internal and private actions to do authz check and get scoped tokens
	s.cfg.Log.Debug(ctx, fmt.Sprintf("Identifying if there are any %s actions", actionsToIdentify))
	var privateAndInternalActions []*pb.ActionReference
	internalRepoCounter := 0

	for _, action := range actions {
		if !isNonEnterpriseRepo && s.isRepoInternalAndAllowed(action, actionRepoMap, actionsPolicyInfo) {
			privateAndInternalActions = append(privateAndInternalActions, action)
			internalRepoCounter++
		} else if s.isRepoPrivateAndAllowed(action, actionRepoMap, actionsPolicyInfo) {
			// isRepoPrivateAndAllowed will return false if private actions ff is disabled.
			privateAndInternalActions = append(privateAndInternalActions, action)
		}
	}

	if len(privateAndInternalActions) > 0 {
		// Validate authz policy for internal and private actions access
		s.cfg.Log.Debug(ctx, fmt.Sprintf("Identified some %s actions, validating authz permissions", actionsToIdentify))
		callerRepoID, err := globalIDToRepositoryID(workflowRepoID)
		if err != nil {
			return nil, nil, nil, errors.Wrap(err, "could not get global id")
		}

		referencedRepos, selfReferencedRepo := getReferencedRepos(privateAndInternalActions, actionRepoMap, callerRepoID)
		if len(referencedRepos) > 0 {
			_, inaccessibleRepos, err := s.AuthzClient.BatchAuthorizeAndReturnInaccessibleRepos(ctx, callerRepoID, referencedRepos)
			if err != nil {
				resolveResponse, err := s.handleBatchAuthzdError(ctx, actionRepoMap, inaccessibleRepos, err)
				return nil, nil, resolveResponse, err
			}
		}

		// Get map of action repository tokens (by org/owner) to resolve internal and private repositories
		s.cfg.Log.Debug(ctx, fmt.Sprintf("Get owner-token Map for %s actions", actionsToIdentify))

		// Always generate scoped token map for GHES
		tokenMap, err = s.getOwnerScopedTokenMap(ctx, privateAndInternalActions)

		if err != nil {
			s.cfg.Log.Debug(ctx, "Failed to get owner-token Map")
			return nil, nil, nil, errors.Wrap(err, fmt.Sprintf("failed to get token for %s actions", actionsToIdentify))
		}

		s.collectInternalAndPrivateActionsUsageStats(ctx, isNonEnterpriseRepo, int64(internalRepoCounter), int64(len(privateAndInternalActions)), selfReferencedRepo, actionsPolicyInfo)
	}
	return actionRepoMap, tokenMap, nil, nil
}

func (s *service) resolveActionWithTokens(
	ctx context.Context,
	action *pb.ActionReference,
	actionRepoMetadata ActionRepoMetadata,
	t *tokens.AccessToken,
	tokenMap map[string]*ownerToken,
	fallbackToConnect bool,
	workflowRunID int64,
	jobID string,
	cachedActionRepo *Repository,
) (*resolvedActionWithVisibility, error) {
	if t == nil || actionRepoMetadata.isInternal || actionRepoMetadata.isPrivate {

		// No token given to use for all actions, check if there is an org/owner specific one
		// For internal actions (GHEC) also, check if there is an org/owner specific token
		repo, err := types.ParseNWO(action.Name)
		if err != nil {
			return nil, errors.Wrap(err, "parsing action name")
		}
		if owner, found := tokenMap[repo.Owner]; found {
			t = owner.token
		}
		if t == nil {
			return nil, errors.Wrapf(err, "could not find a token for owner %q", repo.Owner)
		}
	}

	client, err := s.cfg.InternalClientFactory.CreateWithAccessToken(t)
	if err != nil {
		return nil, errors.Wrap(err, "creating token based client")
	}

	resolvedAction, err := s.resolveAction(ctx, client, action, actionRepoMetadata, t, false, fallbackToConnect, workflowRunID, jobID, cachedActionRepo)

	if err != nil {
		return nil, errors.Wrap(err, "resolving action")
	}
	return resolvedAction, nil
}

//nolint:gocyclo // not going to risk breaking production to simplify this function
func (s *service) resolveAction(
	ctx context.Context,
	client ghinternal.Client,
	action *pb.ActionReference,
	actionRepoMetadata ActionRepoMetadata,
	bearerToken *tokens.AccessToken,
	isConnectRequest bool,
	fallbackToConnect bool,
	workflowRunID int64,
	jobID string,
	cachedActionRepo *Repository,
) (*resolvedActionWithVisibility, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	// This repositoryID corresponds to the ID of repository containing the workflow that is being run.
	repositoryID, err := globalIDToRepositoryID(actionRepoMetadata.workflowRepoID)
	if err != nil {
		return nil, errors.Wrap(err, "failed to get workflow_repository_id")
	}
	s.cfg.Log.Debug(ctx, "attempting to resolve action",
		kvp.String("gh.launch.action_name", action.Name),
		kvp.String("gh.launch.action_version", action.Version),
		kvp.Bool("gh.launch.connect_request", isConnectRequest),
		kvp.Int64("gh.launch.workflow_run.id", workflowRunID),
		kvp.String("gh.launch.job.id", jobID),
		kvp.Uint64("gh.launch.workflow_repository.id", repositoryID),
	)
	resolvedAction, err := client.ResolveAction(ctx, action.Name, types.GitRef(action.Version), workflowRunID, jobID, repositoryID)
	if err != nil {
		if apiError, ok := err.(*ghinternal.APIError); ok {
			// In case repo cache is stale then we need to handle the scenario of
			// visibility change from public/private to internal.
			checkForInternalAction := s.shouldCheckForInternalAction(actionRepoMetadata, apiError)

			// In case repo cache is stale then we need to handle the scenario of
			// visibility change from public/internal to private.
			checkForPrivateAction := s.shouldCheckForPrivateAction(actionRepoMetadata, apiError)

			if checkForInternalAction || checkForPrivateAction {
				repos, _, err := s.FindRepositoriesByName(ctx, []string{action.Name}, false, false)
				if err == nil && len(repos) == 1 {
					actionRepo := repos[0]
					if checkForInternalAction && actionRepo.Visibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INTERNAL {
						return s.resolveInternalOrPrivateAction(ctx, actionRepo, action, actionRepoMetadata, isConnectRequest, fallbackToConnect, workflowRunID, jobID, true)
					} else if checkForPrivateAction && actionRepo.Visibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE {
						return s.resolveInternalOrPrivateAction(ctx, actionRepo, action, actionRepoMetadata, isConnectRequest, fallbackToConnect, workflowRunID, jobID, false)
					}
				}
			}

			// If we're in Enterprise and we're not already doing a Connect request, attempt to get a
			// GitHub Connect Token and make a request to resolve the action using dotcom.
			if fallbackToConnect && apiError.MatchStatusCodes(http.StatusNotFound) {
				if !isConnectRequest {
					s.cfg.Log.Debug(ctx, "action not found, using connect to resolve action",
						kvp.String("gh.launch.action_name", action.Name),
						kvp.String("gh.launch.action_version", action.Version),
						kvp.Bool("gh.launch.connect_request", isConnectRequest),
					)

					var connectErr error
					var connectToken *tokens.AccessToken
					if s.cfg.ResolverTokenFactory != nil {
						connectToken, connectErr = s.cfg.ResolverTokenFactory.GetToken(ctx)
					} else {
						connectToken, connectErr = client.GetConnectToken(ctx)
					}

					if connectErr == nil {
						connectClient, err := s.cfg.InternalClientFactory.CreateConnectClient(connectToken)
						if err != nil {
							return nil, tracing.RecordError(span, err)
						}

						// We recursively call, only this time we're using the GitHub Connect
						// client and its token for our responses.
						// Don't pass a workflow run ID or job ID for Connect requests
						return s.resolveAction(ctx, connectClient, action, actionRepoMetadata, connectToken, true, true, 0, "", cachedActionRepo)
					}

					s.cfg.Log.Error(ctx, "failed to resolve action with GitHub Connect", kvp.Err(connectErr))

					// If connect is not enabled, let's link the users to the
					// documentation.
					if connectErr == ghinternal.ErrConnectNotEnabled {
						fullErrorMessage := fmt.Sprintf("%s on this server. If you want to use this action from GitHub.com, see the following documentation: https://docs.github.com/en/enterprise/admin/github-actions/managing-access-to-actions-from-githubcom", apiError.ErrorMessage)

						return nil, ghinternal.NewAPIError(http.StatusNotFound, fullErrorMessage)
					}
				}
			}
		}

		return nil, tracing.RecordError(span, err)
	}

	// If the action is resolved but the returned visibility is different from the cached visibility then update the cache and check the actions access policy
	latestVisibility, err := s.checkForStaleVisibility(ctx, actionRepoMetadata, RepositoryVisibilityValue[resolvedAction.Visibility], action.Name, cachedActionRepo, isConnectRequest)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	// Throw error if repo is private and redirected, we do not want to support actions redirecting for private actions
	if !strings.EqualFold(resolvedAction.ResolvedName, action.Name) && *latestVisibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE {
		errMsg := fmt.Sprintf("Unable to resolve action `%s`, repository not found", action.Name)
		return nil, ghinternal.NewAPIError(http.StatusNotFound, errMsg)
	}

	shouldSkipScopedTokenGeneration := s.IsEnterprise // Scoped tokens are already generated for GHES before resolve actions call, no need to generate again
	if !isConnectRequest && !s.IsEnterprise {
		wfRepoBasedActionsResolveDecision := s.buildWorkflowRepoBasedDecisionForAction(repositoryID, actionRepoMetadata, latestVisibility)
		if !wfRepoBasedActionsResolveDecision.isSharingApplicable {
			errMsg := fmt.Sprintf("Unable to resolve action `%s`, repository not found", action.Name)
			return nil, ghinternal.NewAPIError(http.StatusNotFound, errMsg)
		}
		shouldSkipScopedTokenGeneration = wfRepoBasedActionsResolveDecision.shouldSkipScopedTokenGeneration
	}

	s.cfg.Log.Debug(ctx, "successfully resolved action",
		kvp.String("gh.launch.action_name", action.Name),
		kvp.String("gh.launch.action_version", action.Version),
		kvp.Bool("gh.launch.connect_request", isConnectRequest),
		kvp.String("gh.launch.resolved_action.name", resolvedAction.ResolvedName))

	var tokenToInclude *tokens.AccessToken
	if s.IsEnterprise || (s.cfg.ResolverTokenFactory != nil && isConnectRequest) {
		tokenToInclude = bearerToken
	}

	if s.IsEnterprise && isConnectRequest {
		err = s.cfg.GithubTwirpClient.RetireNamespace(ctx, action.Name)
		if err != nil {
			s.cfg.Log.Error(ctx, "failed to retire namespace of action resolved with GitHub Connect", kvp.Err(err), kvp.String("gh.launch.action_name", action.Name))
		}
	}

	return &resolvedActionWithVisibility{
		action:                    restResolvedActionToDeployerProto(resolvedAction, action, tokenToInclude),
		visibility:                *latestVisibility,
		skipScopedTokenGeneration: shouldSkipScopedTokenGeneration,
	}, nil
}

func (s *service) buildWorkflowRepoBasedDecisionForAction(repositoryID uint64, actionRepoMetadata ActionRepoMetadata, latestVisibility *ghactions.RepositoryVisibility) *WorkflowRepoBasedActionsResolveDecision {
	if *latestVisibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC {
		// Allow all public actions
		return buildDecisionObject(true, false)
	}

	if repositoryID == uint64(actionRepoMetadata.actionRepoID) {
		// Allow action to be used by workflows in the same repo irrespective of the repo visibility
		// Skip generating scoped tokens passed to the runner for self refrencing scenarios
		return buildDecisionObject(true, true)
	}

	if *latestVisibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INTERNAL && actionRepoMetadata.areInternalActionsEnabled {
		// Allow internal actions to be used by a workflow if Internal Actions Feature is applicable to the workflow repo
		return buildDecisionObject(true, false)
	}

	if *latestVisibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE && actionRepoMetadata.arePrivateActionsEnabled {
		// Allow private actions to be used by a workflow if Private Actions Feature is applicable to the workflow repo
		return buildDecisionObject(true, false)
	}

	return buildDecisionObject(false, false)
}

func buildDecisionObject(isSharingApplicable, shouldSkipScopedTokenGeneration bool) *WorkflowRepoBasedActionsResolveDecision {
	return &WorkflowRepoBasedActionsResolveDecision{
		isSharingApplicable:             isSharingApplicable,
		shouldSkipScopedTokenGeneration: shouldSkipScopedTokenGeneration,
	}
}

func (s *service) checkForStaleVisibility(ctx context.Context, actionRepoMetadata ActionRepoMetadata, latestVisibility ghactions.RepositoryVisibility, nwo string, cachedActionRepo *Repository, isConnectRequest bool) (*ghactions.RepositoryVisibility, error) {
	// skip check for GHES since we do not use cache here and always fetch the latest data from dotcom
	if s.IsEnterprise || isConnectRequest || cachedActionRepo == nil || (!actionRepoMetadata.areInternalActionsEnabled && !actionRepoMetadata.arePrivateActionsEnabled) {
		return &latestVisibility, nil
	}

	cachedVisibility := cachedActionRepo.Visibility
	if cachedVisibility != latestVisibility {
		s.cfg.Log.Debug(ctx, fmt.Sprintf("Update visibility of the action %s in cache", nwo))
		s.UpdateRepoVisibilityCache(ctx, latestVisibility, cachedActionRepo)

		if cachedVisibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC &&
			(latestVisibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INTERNAL || latestVisibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE) {
			// If the action was previously public and is now internal or private, update the cache and validate the action repo access from workflow repo

			s.cfg.Log.Debug(ctx, fmt.Sprintf("Validating authz permissions for action %s with stale visibility", nwo))
			workflowRepoID, err := globalIDToRepositoryID(actionRepoMetadata.workflowRepoID)
			if err != nil {
				return &latestVisibility, errors.Wrap(err, "could not get database id")
			}

			if workflowRepoID != uint64(actionRepoMetadata.actionRepoID) {
				// If the action repo is not the same as the workflow repo, validate the action repo access from workflow repo
				permission, err := s.AuthzClient.Authorize(ctx, workflowRepoID, uint64(actionRepoMetadata.actionRepoID))
				if err != nil {
					return &latestVisibility, errors.Wrap(err, "could not validate authz permissions")
				}
				if !permission {
					s.cfg.Log.Debug(ctx, "Authz validation check failed")
					errMsg := fmt.Sprintf("Unable to resolve action `%s`, repository not found", nwo)
					return &latestVisibility, ghinternal.NewAPIError(http.StatusNotFound, errMsg)
				}
			}
		}

	}

	return &latestVisibility, nil
}

// Determines whether an action can be resolved via GitHub Connect if not found on the local instance
// This is only available on GitHub Enterprise and GitHub AE
// To prevent bypassing the action policy, we won't fallback
// to Connect if the action is only allowed locally
func (s *service) shouldFallbackToConnect(action *pb.ActionReference, localOnlyActionsMap map[string]bool) bool {
	return (s.IsEnterprise || s.cfg.ResolverTokenFactory != nil) && !localOnlyActionsMap[action.NameWithVersion()]
}

func (s *service) getActionRepoMetadata(action *pb.ActionReference, actionRepoMap map[string]*Repository, actionsPolicyInfo *ghtwirp.ActionsPolicyInfo, workflowRepoID types.GlobalID) ActionRepoMetadata {
	isInternal := s.isRepoInternalAndAllowed(action, actionRepoMap, actionsPolicyInfo)
	isPrivate := s.isRepoPrivateAndAllowed(action, actionRepoMap, actionsPolicyInfo)
	areInternalActionsEnabled := areInternalActionsEnabled(actionsPolicyInfo)
	arePrivateActionsEnabled := arePrivateActionsEnabled(actionsPolicyInfo)
	isRepoFromCache := false
	actionRepoID := int64(0)

	if repo, ok := actionRepoMap[strings.ToLower(action.Name)]; ok {
		isRepoFromCache = repo.FromCache
		actionRepoID = repo.ID
	}

	return ActionRepoMetadata{
		isInternal:                isInternal,
		isPrivate:                 isPrivate,
		areInternalActionsEnabled: areInternalActionsEnabled,
		arePrivateActionsEnabled:  arePrivateActionsEnabled,
		workflowRepoID:            workflowRepoID,
		fromCache:                 isRepoFromCache,
		actionRepoID:              actionRepoID,
	}
}

func (s *service) handleBatchAuthzdError(ctx context.Context, actionRepoMap map[string]*Repository, inaccessibleActions []string, authzdError error) (*pb.ResolveActionsResponse, error) {
	// There is a possibility that cache was stale and some internal repos were made private.
	// Throw a different error in that case.
	staleActionNames := make([]string, 0, len(inaccessibleActions))
	for _, actionName := range inaccessibleActions {
		if actionRepoMap[strings.ToLower(actionName)].FromCache {
			staleActionNames = append(staleActionNames, actionName)
		} else if actionRepoMap[strings.ToLower(actionName)].Visibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE {
			// Throw a different error when tyrying to access private action with sharing disabled.
			errMsg := fmt.Sprintf("Unable to resolve action `%s`, repository not found", actionName)
			s.cfg.Log.Log(ctx, "Private Action share policy is not enabled.")
			return &pb.ResolveActionsResponse{Errors: []*pb.ResolvedActionError{{Message: errMsg}}}, nil
		}
	}

	if len(staleActionNames) != 0 {
		repositories, _, err := s.FindRepositoriesByName(ctx, staleActionNames, false, false)
		if err != nil {
			return nil, errors.Wrap(err, "could not fetch action repositories information")
		}

		for _, repo := range repositories {
			if repo.Visibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE {
				errMsg := fmt.Sprintf("Unable to resolve action `%s/%s`, repository not found", repo.OwnerLogin, repo.Name)
				s.cfg.Log.Log(ctx, "Action visibility was changed from internal to private")
				return &pb.ResolveActionsResponse{Errors: []*pb.ResolvedActionError{{Message: errMsg}}}, nil
			}
		}
	}

	if terrors.IsForbiddenInternalActionError(authzdError) {
		// Internal actions feature is only available on GHES and GHEC. Show error accordingly.
		docURLPath := "/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#allowing-access-to-components-in-an-internal-repository"
		docsURL := ""
		if s.IsEnterprise {
			docsURL = utils.GetGHESDocsURL(docURLPath, s.EnterpriseVersion)
		} else {
			docsURL = utils.GetGHECDocsURL(docURLPath)
		}
		errMsg := fmt.Sprintf("Unable to resolve actions. %s Enable access using Settings in the Action repository. See %s for more information.", authzdError.Error(), docsURL)
		s.cfg.Log.Log(ctx, "Authz validation check failed for some actions")
		return &pb.ResolveActionsResponse{Errors: []*pb.ResolvedActionError{{Message: errMsg}}}, nil
	}
	return nil, errors.Wrap(authzdError, "could not validate authz permissions")
}

// Determine if we need to check if the action was made internal.
func (s *service) shouldCheckForInternalAction(actionRepoMetadata ActionRepoMetadata, apiError *ghinternal.APIError) bool {
	return !s.IsEnterprise && actionRepoMetadata.areInternalActionsEnabled && actionRepoMetadata.fromCache && !actionRepoMetadata.isInternal && apiError.MatchStatusCodes(http.StatusNotFound)
}

// Determine if we need to check if the action was made private.
func (s *service) shouldCheckForPrivateAction(actionRepoMetadata ActionRepoMetadata, apiError *ghinternal.APIError) bool {
	return !s.IsEnterprise && actionRepoMetadata.arePrivateActionsEnabled && actionRepoMetadata.fromCache && !actionRepoMetadata.isPrivate && apiError.MatchStatusCodes(http.StatusNotFound)
}

// Perfroms an authzd check and tries to resolve the internal/private action using scoped token.
// This fallback will be used when the action is stored as public in cache but is actually internal/private and present in another org.
// Resolve action API call will fail for such case since we use the installation token of workflow owner to resolve public actions.
func (s *service) resolveInternalOrPrivateAction(
	ctx context.Context,
	actionRepo *Repository,
	action *pb.ActionReference,
	actionRepoMetadata ActionRepoMetadata,
	isConnectRequest bool,
	fallbackToConnect bool,
	workflowRunID int64,
	jobID string,
	checkForInternal bool,
) (*resolvedActionWithVisibility, error) {
	actionRepoMetadata.isInternal = checkForInternal
	actionRepoMetadata.isPrivate = !checkForInternal

	if checkForInternal {
		s.cfg.Log.Debug(ctx, "Try to resolve internal action")
	} else {
		s.cfg.Log.Debug(ctx, "Try to resolve private action")
	}

	workflowRepoID, err := globalIDToRepositoryID(actionRepoMetadata.workflowRepoID)
	if err != nil {
		return nil, errors.Wrap(err, "could not get database id")
	}

	permission, err := s.AuthzClient.Authorize(ctx, workflowRepoID, uint64(actionRepo.ID))
	if err != nil {
		return nil, errors.Wrap(err, "could not validate authz permissions")
	}
	if !permission {
		s.cfg.Log.Debug(ctx, "Authz validation check failed")
		errMsg := fmt.Sprintf("Unable to resolve action `%s`, repository not found", action.Name)
		return nil, ghinternal.NewAPIError(http.StatusNotFound, errMsg)
	}

	var token *tokens.AccessToken

	ownerID, _, err := s.cfg.GithubTwirpClient.GetUserByLogin(ctx, actionRepo.OwnerLogin)
	if err != nil {
		return nil, errors.Wrapf(err, "fetching User ID for login %s", actionRepo.OwnerLogin)
	}

	token, err = s.cfg.TokenService.ReadTokenForSiteScopedInstallation(ctx, ownerID, []string{actionRepo.Name}, false)
	if err != nil {
		return nil, errors.Wrap(err, "failed to get site scoped token for enterprise internal/private actions")
	}

	client, err := s.cfg.InternalClientFactory.CreateWithAccessToken(token)
	if err != nil {
		return nil, errors.Wrap(err, "creating token based client")
	}

	return s.resolveAction(ctx, client, action, actionRepoMetadata, token, isConnectRequest, fallbackToConnect, workflowRunID, jobID, actionRepo)
}

func (s *service) isRepoInternalAndAllowed(action *pb.ActionReference, actionRepoMap map[string]*Repository, actionsPolicyInfo *ghtwirp.ActionsPolicyInfo) bool {
	if !areInternalActionsEnabled(actionsPolicyInfo) {
		return false
	}
	if actionRepo, ok := actionRepoMap[strings.ToLower(action.Name)]; ok {
		return actionRepo.Visibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INTERNAL
	}
	return false
}

func (s *service) isRepoPrivateAndAllowed(action *pb.ActionReference, actionRepoMap map[string]*Repository, actionsPolicyInfo *ghtwirp.ActionsPolicyInfo) bool {
	if !arePrivateActionsEnabled(actionsPolicyInfo) {
		return false
	}
	if actionRepo, ok := actionRepoMap[strings.ToLower(action.Name)]; ok {
		return actionRepo.Visibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE
	}
	return false
}

func getReferencedRepos(actions []*pb.ActionReference, actionRepoMap map[string]*Repository, callerRepoID uint64) ([]*authzd.RepositoryParam, *Repository) {
	var referencedRepos []*authzd.RepositoryParam
	var selfReferencedRepo *Repository
	for _, action := range actions {
		actionRepo, found := actionRepoMap[strings.ToLower(action.Name)]
		if !found {
			continue
		}
		if callerRepoID == uint64(actionRepo.ID) {
			// Allow actions from the same repository to be resolved without authz policy check
			selfReferencedRepo = actionRepo
			continue
		}
		referencedRepos = append(referencedRepos, &authzd.RepositoryParam{ID: uint64(actionRepo.ID), Name: action.Name})
	}

	return referencedRepos, selfReferencedRepo
}

func (s *service) findRepositoriesMetadata(ctx context.Context, actionNames []string, getPrivateActionFromCache bool) (map[string]*Repository, string, error) {
	repositoryMap := make(map[string]*Repository)

	repositories, repositoriesNotFoundErrorMessage, err := s.FindRepositoriesByName(ctx, actionNames, true, getPrivateActionFromCache)
	if err != nil {
		return nil, "", errors.Wrap(err, "could not fetch action repositories information")
	}

	for _, repo := range repositories {
		nwo := types.RepositoryFullName{Owner: repo.OwnerLogin, Name: repo.Name}
		repositoryMap[strings.ToLower(nwo.String())] = repo
	}

	return repositoryMap, repositoriesNotFoundErrorMessage, nil
}

func getUniqueActionRepositoryNames(actions []*pb.ActionReference) []string {
	actionNamesMap := make(map[string]bool)
	uniqueActionNames := make([]string, 0)

	for _, action := range actions {
		actionName := strings.ToLower(action.Name)
		if _, found := actionNamesMap[actionName]; !found {
			actionNamesMap[actionName] = true
			uniqueActionNames = append(uniqueActionNames, actionName)
		}
	}

	return uniqueActionNames
}

func areInternalActionsEnabled(actionsPolicyInfo *ghtwirp.ActionsPolicyInfo) bool {
	return actionsPolicyInfo.AreInternalActionsAllowed
}

func arePrivateActionsEnabled(actionsPolicyInfo *ghtwirp.ActionsPolicyInfo) bool {
	return actionsPolicyInfo.ArePrivateActionsAllowed
}

func globalIDToRepositoryID(globalID types.GlobalID) (uint64, error) {
	t, id, err := graphqlid.DecodeTypeIntID(globalID.String())
	if err != nil {
		return 0, errors.Wrap(err, "failed to decode GlobalID")
	}

	if t != "Repository" {
		return 0, errors.Wrapf(err, "unexpected global id type %s, expected Repository", t)
	}

	return (uint64)(id), nil
}

func whatActionsToIdentify(actionsPolicyInfo *ghtwirp.ActionsPolicyInfo) string {
	if areInternalActionsEnabled(actionsPolicyInfo) && arePrivateActionsEnabled(actionsPolicyInfo) {
		return "internal or private"
	} else if arePrivateActionsEnabled(actionsPolicyInfo) {
		return "private"
	}
	return "internal"
}

// Below function is used to collect the usage metrics for the Internal and Private actions
// We also seperate the self-refrencing case since we do not validate authzd policy for it
func (s *service) collectInternalAndPrivateActionsUsageStats(ctx context.Context, isNonEnterpriseRepo bool, internalRepoCounter, privateAndInternalActionsCount int64, selfReferencedRepo *Repository, actionsPolicyInfo *ghtwirp.ActionsPolicyInfo) {
	if selfReferencedRepo != nil {
		privateAndInternalActionsCount--
		if selfReferencedRepo.Visibility == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INTERNAL {
			internalRepoCounter--
			s.cfg.Stats.Counter(ctx, "resolve_self_referencing_action_count", statter.Tags{"type": "internal"}, 1)
		} else {
			s.cfg.Stats.Counter(ctx, "resolve_self_referencing_action_count", statter.Tags{"type": "private"}, 1)
		}
	}

	if isNonEnterpriseRepo {
		s.cfg.Stats.Counter(ctx, "resolve_private_actions_count", statter.Tags{"type": "non_enterprise_private_repo"}, privateAndInternalActionsCount)
	} else {
		s.cfg.Stats.Counter(ctx, "resolve_internal_actions_count", nil, internalRepoCounter)
		if arePrivateActionsEnabled(actionsPolicyInfo) {
			s.cfg.Stats.Counter(ctx, "resolve_private_actions_count", statter.Tags{"type": "enterprise_private_repo"}, privateAndInternalActionsCount-internalRepoCounter)
		}
	}
}

// We created tokens against the mysql primary, but queries for the token will come against the
// replicas. To minimize the odds of tokens showing as invalid, we try to delay the enqueuing of
// the build for the amount of replication lag.
// See: https://github.com/github/c2c-actions-support/issues/1445
func (s *service) delayResolveActionsResponseForTheAmountOfReplicationLag(ctx context.Context, tokenMap map[string]*ownerToken) error {
	tokensReadableAt := time.Now()
	for _, ownerToken := range tokenMap {
		if ownerToken.token.ValidAfter != nil && ownerToken.token.ValidAfter.After(tokensReadableAt) {
			tokensReadableAt = *ownerToken.token.ValidAfter
		}
	}

	tokensReadableIn := time.Until(tokensReadableAt)
	s.emitResponseDelay(ctx, tokensReadableIn)
	if tokensReadableIn > 0 {
		s.cfg.Log.Debug(ctx, "Delaying resolve actions response until scoped tokens are readable", kvp.Duration("gh.launch.tokens_readable_in_seconds", tokensReadableIn))

		select {
		case <-time.After(tokensReadableIn):
		case <-ctx.Done():
			s.cfg.Log.Log(ctx, "timed out waiting for scoped tokens to become readable",
				kvp.Duration("gh.launch.tokens.readable_in_seconds", tokensReadableIn),
				kvp.Time("gh.launch.tokens.readable_at_time", tokensReadableAt),
			)
			return errors.New("timed out waiting for scoped tokens to become readable")
		}
	}

	return nil
}

func (s *service) emitResponseDelay(ctx context.Context, delay time.Duration) {
	if delay < 0 {
		delay = 0
	}
	s.cfg.Obs.Distribution(ctx, "response_delay_ms", statter.Tags{"endpoint": "resolve_actions"}, float64(delay.Milliseconds()))
}

func restResolvedActionToDeployerProto(action *ghinternal.ResolvedAction, reference *pb.ActionReference, token *tokens.AccessToken) *pb.ResolvedAction {
	resp := &pb.ResolvedAction{
		Action:       reference,
		ResolvedName: action.ResolvedName,
		ResolvedSha:  action.ResolvedSha,
		TarUrl:       action.TarURL,
		ZipUrl:       action.ZipURL,
	}

	if token != nil {
		resp.Authentication = &pb.ResolvedActionAuthentication{
			Token:     token.Token,
			ExpiresAt: timestamppb.New(token.Expiry),
		}
	}

	if action.PackageVersion != "" && action.PackageManifestDigest != "" {
		resp.PackageDetails = &pb.ResolvedActionPackageDetails{
			Version:        action.PackageVersion,
			ManifestDigest: action.PackageManifestDigest,
		}
	}

	return resp
}
