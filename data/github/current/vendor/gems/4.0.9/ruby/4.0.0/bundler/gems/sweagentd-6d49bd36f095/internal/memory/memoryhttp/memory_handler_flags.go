package memoryhttp

import (
	"context"
	"strconv"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
)

// votingScope controls which actors are evaluated when checking voting flags.
type votingScope int

const (
	// votingScopeRepoOnly checks only the repository-level voting flag.
	votingScopeRepoOnly votingScope = iota
	// votingScopeRepoAndUser checks both user-level and repository-level voting flags.
	votingScopeRepoAndUser
)

// checkUserLevelMemoryDisabled checks if memory is disabled at the user level.
// This is a fast check that doesn't require repository information or GitHub API calls.
// Returns true if memory is disabled for the user, false otherwise.
func (h *MemoryHandler) checkUserLevelMemoryDisabled(ctx context.Context) bool {
	if h.featureFlagClient == nil {
		return false
	}

	userInfo, ok := requestctx.User(ctx)
	if !ok || userInfo == nil {
		return false
	}

	return h.featureFlagClient.IsEnabledForUser(ctx, core.FeatureMemoryDisabled, int64(userInfo.ID))
}

// checkIntegrationMemoryDisabled checks if memory is disabled for the requesting
// client integration (e.g. VS Code). This is a global kill switch that is
// evaluated without user/repo/org actors — when the flag is enabled, memory is
// disabled for ALL requests from the mapped integration, regardless of who the
// user is.
//
// NOTE: This check is best-effort — it relies on clients sending the integration
// ID header (Copilot-Integration-Id). If the header is absent, the flag lookup
// is skipped and the request proceeds normally.
func (h *MemoryHandler) checkIntegrationMemoryDisabled(ctx context.Context) bool {
	if h.featureFlagClient == nil {
		return false
	}

	flag := featureflags.MemoryDisabledFlagFromContext(ctx)
	if flag == "" {
		return false
	}

	return h.featureFlagClient.IsEnabled(ctx, flag)
}

// checkRepoLevelMemoryDisabled checks if memory is disabled at the repository
// level by a repo admin via the Dotcom settings UI. Returns (true, nil) if
// disabled, (false, nil) when not disabled (the default — including when
// Dotcom has not yet populated the field), or (false, err) when the Twirp
// call failed.
func (h *MemoryHandler) checkRepoLevelMemoryDisabled(ctx context.Context, repository *core.Repository, userID int64) (bool, error) {
	if h.ghTwirp == nil {
		return false, nil
	}

	return h.ghTwirp.IsMemoryDisabledForRepo(ctx, repository.GetRepositoryID(), userID)
}

// isMemoryDisabledForUser runs the user-affecting subset of the memory
// enablement chain via service.CheckMemoryEnabled: Policy via Monolith
// Twirp, the cross-product FF kill switches, and featureDisallowed. It
// deliberately OMITS the repo-admin opt-out layer (repo_memory_disabled
// via Twirp ConfigurationForRepository) because, per the memory opt-out
// matrix agreed in github/agents#945, the repo admin's setting affects
// only repo-scoped memories. The other layers all still apply because
// they are either user-keyed (user FF) or platform-wide (Policy, owner
// FF, ExP).
//
// Returns (true, nil) when memory is disabled at a user-affecting layer,
// (false, nil) when enabled, and (true, err) on chain failure (fail closed
// at the user-affecting layer because Policy failures are harder failures).
func (h *MemoryHandler) isMemoryDisabledForUser(ctx context.Context, userInfo *requestctx.UserInfo, repository *core.Repository) (bool, error) {
	enabled, err := h.service.CheckMemoryEnabled(ctx, int64(userInfo.ID), repository)
	if err != nil {
		return true, err
	}
	return !enabled, nil
}

// isMemoryDisabledByRepoAdmin queries only the repo-admin opt-out layer
// (Twirp ConfigurationForRepository.repo_memory_disabled). Per the memory
// opt-out matrix this layer affects only repo-scoped memories; user-scoped
// memories must NOT consult it. Callers operating only on user-scope data
// should not call this helper at all.
//
// failClosedOnError controls the Twirp-error fail mode:
//   - false: fail open, log + metric. Used by the /enabled endpoint and by
//     read routes via withRepoMemoryCheck — a Dotcom blip cannot 500 every
//     repo-scoped memory read across every repo.
//   - true: propagate the error. Used by HandleGetCombinedPrompt (so the
//     caller can drop the repo scope) and by write routes via
//     withRepoMemoryCheck (so a Dotcom blip cannot silently allow writes
//     to a possibly-opted-out repo — writes are exactly what the opt-out
//     is meant to prevent).
func (h *MemoryHandler) isMemoryDisabledByRepoAdmin(ctx context.Context, repository *core.Repository, userID int64, failClosedOnError bool) (bool, error) {
	logger := h.requestLogger(ctx)

	repoDisabled, repoErr := h.checkRepoLevelMemoryDisabled(ctx, repository, userID)
	if repoErr != nil {
		if failClosedOnError {
			logger.WithError(repoErr).Warn("failed to check repo-level memory setting; failing closed at caller request")
			h.obsv.Increment(ctx, "MemoryHandler.isMemoryDisabledByRepoAdmin.error_fail_closed", memoryRequestMetricTags(ctx, nil))
			return true, repoErr
		}
		logger.WithError(repoErr).Warn("failed to check repo-level memory setting; defaulting to enabled")
		h.obsv.Increment(ctx, "MemoryHandler.isMemoryDisabledByRepoAdmin.error_fail_open", memoryRequestMetricTags(ctx, nil))
		return false, nil
	}
	if repoDisabled {
		logger.Info("memory disabled at repository level by repo admin")
		h.obsv.Increment(ctx, "MemoryHandler.isMemoryDisabledByRepoAdmin.disabled", memoryRequestMetricTags(ctx, nil))
		return true, nil
	}
	return false, nil
}

// isMemoryDisabledForRepo runs the FULL chain for repo-scoped routes: the
// user-affecting layers (isMemoryDisabledForUser) OR the repo-admin
// opt-out (isMemoryDisabledByRepoAdmin). Used by repo-scoped routes
// (/enabled and withRepoMemoryCheck) where any layer's disablement
// applies.
//
// Per the memory opt-out matrix (github/agents#945), the user-affecting
// layers also block user memories and the repo-admin layer blocks only
// repo memories. Routes that surface BOTH scopes (HandleGetCombinedPrompt)
// must call the two helpers separately so they can drop scopes
// asymmetrically; this composite is intentionally repo-scope-only.
func (h *MemoryHandler) isMemoryDisabledForRepo(ctx context.Context, userInfo *requestctx.UserInfo, repository *core.Repository, failClosedOnRepoAdminError bool) (bool, error) {
	userDisabled, err := h.isMemoryDisabledForUser(ctx, userInfo, repository)
	if err != nil {
		return true, err
	}
	if userDisabled {
		return true, nil
	}
	return h.isMemoryDisabledByRepoAdmin(ctx, repository, int64(userInfo.ID), failClosedOnRepoAdminError)
}

// isVotingEnabled determines if memory voting should be enabled for this request.
// The scope parameter controls whether only the repo-level FeatureMemoryVoting flag is checked
// or both the user-level and repo-level FeatureMemoryVoting flags.
// Voting is enabled when FeatureMemoryVoting is enabled for at least one actor in scope.
func (h *MemoryHandler) isVotingEnabled(ctx context.Context, repository *core.Repository, logger log.Logger, scope votingScope) bool {
	if h.featureFlagClient == nil {
		logger.Info("voting check: no feature flag client, voting disabled")
		return false
	}

	userInfo, ok := requestctx.User(ctx)
	if !ok || userInfo == nil {
		logger.Info("voting check: no user info in context, voting disabled")
		return false
	}

	flag := featureflags.MemoryVotingFlagFromContext(ctx)
	if flag == "" {
		return false
	}

	var repoEnabled bool
	if repository != nil {
		repoEnabled = h.featureFlagClient.IsEnabledForRepo(ctx, flag, int64(repository.ID))
	}

	var userEnabled bool
	if scope == votingScopeRepoAndUser {
		userEnabled = h.featureFlagClient.IsEnabledForUser(ctx, flag, int64(userInfo.ID))
	}

	if !repoEnabled && !userEnabled {
		logger.Info("voting check: user and repo voting disabled, voting disabled")
		return false
	}

	return true
}

// getMemoryAssignment retrieves an ExP experiment assignment for the given repository.
// The assignment is used to gate memory features like limit experiments.
func (h *MemoryHandler) getMemoryAssignment(ctx context.Context, repository *core.Repository) exp.Assignment {
	logger := h.obsv.LoggerWithTelemetry(ctx)

	if h.expClient == nil {
		logger.Info("exp SDK: client is nil, returning noop assignment")
		return exp.NewNoopClient().GetAssignment(ctx, nil, nil, nil)
	}

	// Use the repository ID as the randomization unit so that all requests
	// for the same repo are consistently assigned to the same experiment variant.
	// Note: Current implementation is for RepoID as RandomizationUnit. If we want to switch to UserID as RandomizationUnit in the future, we can modify this function accordingly.
	params := map[string]string{
		string(exp.RepositoryIDKey):  strconv.FormatUint(uint64(repository.ID), 10),
		string(exp.ExtensionNameKey): exp.ExtensionNameAgenticMemory,
	}

	userInfo, ok := requestctx.User(ctx)
	if ok && userInfo != nil {
		if h.isStaffUser(ctx, int64(userInfo.ID), logger) {
			params[string(exp.StaffKey)] = "true"
		}
	}

	assignment := h.expClient.GetAssignment(ctx, params, nil, nil)
	assignmentCtx := assignment.GetAssignmentContext()

	logger.Info("exp SDK assignment result",
		kvp.String("repo_id", params[string(exp.RepositoryIDKey)]),
		kvp.String("assignment_context", assignmentCtx),
		kvp.Bool("has_assignment", assignmentCtx != ""),
		kvp.Uint64("data_version", assignment.GetDataVersion()),
	)

	return assignment
}
