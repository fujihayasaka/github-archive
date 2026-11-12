package memoryhttp

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"time"

	authd "github.com/github/authnd/client"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
)

type permissionCheck struct {
	label         string
	check         func(github.RepositoryPermissions) bool
	accessActions []string
	// failClosedOnRepoAdminError controls how withRepoMemoryCheck responds
	// when the repo-admin opt-out Twirp call (isMemoryDisabledByRepoAdmin)
	// returns an error. true => return 500 (fail closed); false => log
	// + metric and let the request proceed (fail open). Writes set this
	// true because they're exactly what an opted-out repo is meant to
	// prevent — accepting a brief 500 blast is better than silently
	// writing memories to such a repo during a Dotcom blip. Reads keep
	// the lower-blast-radius fail-open default.
	failClosedOnRepoAdminError bool
}

// tokenAccessCheckResult holds the result of a token access verification.
type tokenAccessCheckResult struct {
	hasAccess         bool
	privilegedRelaxed bool
}

var (
	readPermission  = permissionCheck{label: "read", check: hasReadPermission, accessActions: []string{"pull"}, failClosedOnRepoAdminError: false}
	writePermission = permissionCheck{label: "write", check: hasWritePermissions, accessActions: []string{"push"}, failClosedOnRepoAdminError: true}
)

// requireRepoAuth retrieves the userInfo, repository, and repoNWO resolved by
// withRepoMemoryCheck. If the middleware did not run, it returns an error so
// the handler can respond with 500 (defensive — should never happen in
// production because routes that use these helpers are always behind the
// middleware).
func (h *MemoryHandler) requireRepoAuth(ctx context.Context) (*requestctx.UserInfo, *core.Repository, *core.RepoNWO, error) {
	userInfo, repository, repoNWO, ok := repoAuthFromCtx(ctx)
	if !ok {
		return nil, nil, nil, goerrors.New("repo auth missing from context: handler not behind withRepoMemoryCheck")
	}
	return userInfo, repository, repoNWO, nil
}

// authorize checks if the user is authenticated and has the required permissions
// for the given repository NWO. It also fetches and returns the repository information,
// avoiding a separate API call later that might fail with different token authorization.
//
// It first verifies the user's token has access to the repository via the Twirp
// authorization API (when available), then checks repository-level permissions.
func (h *MemoryHandler) authorize(
	ctx context.Context,
	repoNWO *core.RepoNWO,
	requiredPermissionCheck permissionCheck,
) (*requestctx.UserInfo, *core.Repository, int, error) {
	requiredPermission := requiredPermissionCheck.label

	logger := h.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("repo_nwo", repoNWO.String()),
	)

	// Extract user info from request context
	userInfo, ok := requestctx.User(ctx)
	if !ok || userInfo == nil {
		return userInfo, nil, http.StatusUnauthorized, goerrors.New(http.StatusText(http.StatusUnauthorized))
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	// Run both authorization checks concurrently to minimise latency.
	// verifyTokenAccess (Twirp BatchControlAccess) and getRepositoryPermissionsAndInfo
	// (GitHub API) are independent, so we fire them in parallel and evaluate
	// results in order: token access first, then permission level.
	//
	// A cancellable context is passed to the permissions goroutine so that if the
	// token access check fails or is denied, we can abort the in-flight GitHub API
	// call early - avoiding unnecessary load and rate-limit consumption.

	type tokenAccessResult struct {
		result tokenAccessCheckResult
		err    error
	}
	type permInfoResult struct {
		permissions github.RepositoryPermissions
		repository  *core.Repository
		err         error
	}

	permCtx, cancelPerm := context.WithCancel(ctx)
	defer cancelPerm()

	tokenCh := make(chan tokenAccessResult, 1)
	permCh := make(chan permInfoResult, 1)

	go func() {
		result, err := h.verifyTokenAccess(ctx, userInfo, repoNWO, requiredPermissionCheck.accessActions)
		tokenCh <- tokenAccessResult{result: result, err: err}
	}()

	go func() {
		permissions, repository, err := h.getRepositoryPermissionsAndInfo(permCtx, *repoNWO, *userInfo)
		permCh <- permInfoResult{permissions: permissions, repository: repository, err: err}
	}()

	// Wait for token access result first - if denied, cancel the permissions
	// goroutine's context and return immediately.
	tokenResult := <-tokenCh
	if tokenResult.err != nil {
		logger.WithError(tokenResult.err).WithFields(
			kvp.String("required_permission", requiredPermission),
		).Info("authorization failed: error verifying token access")
		h.obsv.Increment(ctx, metricAuthorizeFailure, memoryRequestMetricTags(ctx, map[string]string{
			"reason":              "token_access_error",
			"required_permission": requiredPermission,
		}))
		h.obsv.Increment(ctx, metricTokenAccessCheck, memoryRequestMetricTags(ctx, map[string]string{"outcome": "error"}))
		return userInfo, nil, http.StatusNotFound, goerrors.New("Could not verify access to this repository. Check that the repository exists and you have access to it.")
	}
	if !tokenResult.result.hasAccess {
		logger.WithFields(
			kvp.String("required_permission", requiredPermission),
		).Info("authorization failed: token does not have access to repository")
		h.obsv.Increment(ctx, metricAuthorizeFailure, memoryRequestMetricTags(ctx, map[string]string{
			"reason":              "token_no_access",
			"required_permission": requiredPermission,
		}))
		h.obsv.Increment(ctx, metricTokenAccessCheck, memoryRequestMetricTags(ctx, map[string]string{"outcome": "denied"}))
		return userInfo, nil, http.StatusNotFound, goerrors.New("Could not verify access to this repository. Check that the repository exists and you have access to it.")
	}
	h.obsv.Increment(ctx, metricTokenAccessCheck, memoryRequestMetricTags(ctx, map[string]string{
		"outcome":            "allowed",
		"privileged_relaxed": strconv.FormatBool(tokenResult.result.privilegedRelaxed),
	}))

	// Wait for permissions result.
	permResult := <-permCh
	if permResult.err != nil {
		logger.WithError(permResult.err).WithFields(
			kvp.String("required_permission", requiredPermission),
		).Info("authorization failed: error getting repository permissions/info")
		h.obsv.Increment(ctx, metricAuthorizeFailure, memoryRequestMetricTags(ctx, map[string]string{
			"reason":              "permission_fetch_error",
			"required_permission": requiredPermission,
		}))
		return userInfo, nil, http.StatusNotFound, goerrors.New("Could not verify access to this repository. Check that the repository exists and you have access to it.")
	}
	if !requiredPermissionCheck.check(permResult.permissions) {
		// If the user has no access at all, return 404 to avoid leaking repository
		// existence. The permission lookup may have succeeded via the app installation
		// token even though the user has no relationship to the repository.
		if !hasReadPermission(permResult.permissions) {
			logger.WithFields(
				kvp.String("required_permission", requiredPermission),
				kvp.String("actual_permission", permResult.permissions.Permission),
				kvp.String("actual_role", permResult.permissions.Role),
			).Info("authorization failed: no access to repository")
			h.obsv.Increment(ctx, metricAuthorizeFailure, memoryRequestMetricTags(ctx, map[string]string{
				"reason":              "no_access",
				"required_permission": requiredPermission,
			}))
			return userInfo, nil, http.StatusNotFound, goerrors.New("Could not verify access to this repository. Check that the repository exists and you have access to it.")
		}

		logger.WithFields(
			kvp.String("required_permission", requiredPermission),
			kvp.String("actual_permission", permResult.permissions.Permission),
			kvp.String("actual_role", permResult.permissions.Role),
		).Info("authorization failed: insufficient permissions")
		h.obsv.Increment(ctx, metricAuthorizeFailure, memoryRequestMetricTags(ctx, map[string]string{
			"reason":              "insufficient_permissions",
			"required_permission": requiredPermission,
			"actual_permission":   permResult.permissions.Permission,
		}))
		// The user has some level of access (but not enough for this operation),
		// so we can safely return 403 with a descriptive message without leaking
		// information about the repository's existence.
		return userInfo, nil, http.StatusForbidden, goerrors.Errorf("You don't have %s access to this repository", requiredPermission)
	}

	return userInfo, permResult.repository, http.StatusOK, nil
}

// getRepositoryPermissionsAndInfo retrieves both the user's permissions and the repository info
// for the specified repository NWO. This combines both operations using the same GitHub client,
// avoiding a separate API call to fetch repository info later using a potentially unauthorized token.
//
// This function first attempts to use the Copilot app installation token.
// If the app is not installed on the repository, it falls back to using the user's token.
func (h *MemoryHandler) getRepositoryPermissionsAndInfo(
	ctx context.Context,
	repoNWO core.RepoNWO,
	userInfo requestctx.UserInfo,
) (github.RepositoryPermissions, *core.Repository, error) {
	logger := h.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("repo_nwo", repoNWO.String()),
		kvp.Uint64("user_id", userInfo.ID),
	)

	// First, try to create a client using the Copilot app installation token.
	// TODO (kinseydurhamgrace): We should supporting memories for any app, but not right now.
	gh, err := h.ghFactory.NewClientFromRepoName(ctx, h.appProvider.CopilotApp(), repoNWO.Repo, repoNWO.Owner, userInfo.ID)
	if err != nil {
		// App installation not found or other error - fall back to user token if available.
		logger.WithError(err).Info("app installation token unavailable, attempting user token fallback")
		h.obsv.Increment(ctx, metricUserTokenFallback, memoryRequestMetricTags(ctx, map[string]string{"outcome": "attempted"}))

		gh = h.tryUserTokenFallback(userInfo)
		if gh == nil {
			logger.Warn("user token fallback failed: no user token available")
			h.obsv.Increment(ctx, metricUserTokenFallback, memoryRequestMetricTags(ctx, map[string]string{"outcome": "failed"}))
			return github.RepositoryPermissions{}, nil, goerrors.Errorf("failed to create GitHub client: %w", err)
		}
		logger.Info("user token fallback succeeded")
		h.obsv.Increment(ctx, metricUserTokenFallback, memoryRequestMetricTags(ctx, map[string]string{"outcome": "succeeded"}))
	}

	// Only process events where the actor has write access to the repo
	repositoryPermissions, err := gh.GetUserPermissionsForRepository(ctx, repoNWO.Owner, repoNWO.Repo, userInfo.Login)
	if err != nil || repositoryPermissions == nil {
		return github.RepositoryPermissions{}, nil, goerrors.Errorf("failed to get repository permissions: %w", err)
	}

	// Fetch repository info using the same client that successfully checked permissions.
	// This avoids a separate API call later that might fail with a different token.
	ghRepo, err := gh.GetRepository(ctx, repoNWO.Owner, repoNWO.Repo)
	if err != nil || ghRepo == nil {
		return github.RepositoryPermissions{}, nil, goerrors.Errorf("failed to get repository info: %w", err)
	}

	repository := &core.Repository{
		ID:      core.RepositoryID(ghRepo.GetID()),
		NWO:     repoNWO,
		Private: ghRepo.GetPrivate(),
		OwnerID: ghRepo.GetOwner().GetID(),
	}

	return *repositoryPermissions, repository, nil
}

// tryUserTokenFallback attempts to create a GitHub client using the user's token.
// Returns nil if no user token is available.
func (h *MemoryHandler) tryUserTokenFallback(userInfo requestctx.UserInfo) github.ClientInterface {
	if userInfo.TokenInfo == nil || userInfo.TokenInfo.Token == "" {
		return nil
	}
	return h.ghFactory.NewClientForUser(userInfo.TokenInfo.Token, userInfo.ID, h.appProvider.CopilotApp())
}

// hasWritePermissions checks if the required permissions are met by the actor
// that attempts to create the memories. We expect that the actor has push permissions
// to the repository and above (write, maintain, admin).
// https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization
func hasWritePermissions(permissions github.RepositoryPermissions) bool {
	return permissions.Push || permissions.Admin || permissions.Maintain
}

// hasReadPermission checks if the required permissions are met by the actor
// that attempts to read the memories. We expect that the actor has pull permissions
// to the repository and above (read, triage, write, maintain, admin).
// https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization
func hasReadPermission(permissions github.RepositoryPermissions) bool {
	return permissions.Pull || permissions.Triage || hasWritePermissions(permissions)
}

// verifyTokenAccess checks if the user's token has the required access actions for the given repository.
// It returns a tokenAccessCheckResult indicating access and whether privileged relaxation was applied.
// If the ghTwirp client is not configured, the check is skipped (returns hasAccess=true) to allow
// the existing permission flow.
//
// For User-to-Server tokens from privileged apps (e.g. Copilot), the required access actions are
// relaxed to only require "pull" access, since the user's actual repo-level permissions are
// independently verified by the getRepositoryPermissionsAndInfo check. This matches the pattern
// used by the Jobs API.
func (h *MemoryHandler) verifyTokenAccess(
	ctx context.Context,
	userInfo *requestctx.UserInfo,
	repoNWO *core.RepoNWO,
	accessActions []string,
) (tokenAccessCheckResult, error) {
	logger := h.obsv.LoggerWithTelemetry(ctx)

	// Skip token access check if the Twirp client is not configured.
	if h.ghTwirp == nil {
		return tokenAccessCheckResult{hasAccess: true}, nil
	}

	// Deny access if the user has no token - we cannot verify access without one.
	if userInfo.TokenInfo == nil || userInfo.TokenInfo.Token == "" {
		return tokenAccessCheckResult{}, nil
	}

	// For User-to-Server tokens from privileged apps, relax the required access
	// actions to only require "pull". The user's actual write/admin permissions
	// are verified by the separate getRepositoryPermissionsAndInfo check.
	var privilegedRelaxed bool
	if userInfo.TokenInfo.Type == string(authd.CredentialTypeUserToServerToken) && h.privilegedAppChecker != nil {
		hasCapability, err := h.privilegedAppChecker.IsCapable(ctx, userInfo.TokenInfo.ApplicationID, userInfo.TokenInfo.ApplicationType)
		if err != nil {
			// Log and fall through to the original access actions. The privileged
			// check is an additive relaxation (push → pull); a transient failure
			// should not block tokens that already satisfy the tighter check.
			logger.WithError(err).Warn("failed to check privileged app capabilities, falling back to original access actions")
		} else if hasCapability {
			logger.Info("token is from privileged app, relaxing access actions to pull-only")
			accessActions = readPermission.accessActions
			privilegedRelaxed = true
		}
	}

	nwo := fmt.Sprintf("%s/%s", repoNWO.Owner, repoNWO.Repo)
	rules := make([]*githubtwirp.HasAccessCheck, len(accessActions))
	for i, action := range accessActions {
		rules[i] = &githubtwirp.HasAccessCheck{
			Action:        action,
			ResourceType:  "Repository",
			RepositoryNWO: nwo,
		}
	}

	hasAccess, err := h.ghTwirp.TokenHasAccess(ctx, userInfo, rules)
	if err != nil {
		return tokenAccessCheckResult{}, goerrors.Errorf("failed to verify token access: %w", err)
	}

	return tokenAccessCheckResult{hasAccess: hasAccess, privilegedRelaxed: privilegedRelaxed}, nil
}

// authorizeWithTelemetry wraps authorize with duration tracking.
func (h *MemoryHandler) authorizeWithTelemetry(
	ctx context.Context,
	repoNWO *core.RepoNWO,
	requiredPermissionCheck permissionCheck,
) (*requestctx.UserInfo, *core.Repository, int, error) {
	start := time.Now()
	userInfo, repository, status, err := h.authorize(ctx, repoNWO, requiredPermissionCheck)
	h.obsv.DistributionMs(ctx, metricAuthorizeDuration, memoryRequestMetricTags(ctx, nil), time.Since(start))
	return userInfo, repository, status, err
}

// authorizeAndAssign wraps authorizeWithTelemetry and stores an experiment
// assignment in the returned context so downstream code can read it via
// exp.AssignmentFromContext.
func (h *MemoryHandler) authorizeAndAssign(
	ctx context.Context,
	repoNWO *core.RepoNWO,
	requiredPermissionCheck permissionCheck,
) (context.Context, *requestctx.UserInfo, *core.Repository, int, error) {
	userInfo, repository, status, err := h.authorizeWithTelemetry(ctx, repoNWO, requiredPermissionCheck)
	if err != nil {
		return ctx, userInfo, repository, status, err
	}

	assignment := h.getMemoryAssignment(ctx, repository)
	ctx = exp.WithAssignment(ctx, assignment)

	return ctx, userInfo, repository, status, nil
}

// isStaffUser checks whether the given user belongs to a GitHub/Microsoft staff
// organization by fetching their Copilot user details. Returns false (non-staff)
// on any error so that experiment targeting degrades gracefully.
func (h *MemoryHandler) isStaffUser(ctx context.Context, userID int64, logger log.Logger) bool {
	if h.ghTwirp == nil {
		return false
	}

	userDetails, err := h.ghTwirp.GetCopilotUserDetails(ctx, userID)
	if err != nil {
		logger.WithError(err).Warn("failed to fetch user details for staff check")
		return false
	}
	if userDetails == nil {
		return false
	}

	orgIDs := make([]uint64, len(userDetails.CopilotOrganizations))
	for i, org := range userDetails.CopilotOrganizations {
		orgIDs[i] = org.Id
	}
	return exp.IsActorStaff(orgIDs)
}
