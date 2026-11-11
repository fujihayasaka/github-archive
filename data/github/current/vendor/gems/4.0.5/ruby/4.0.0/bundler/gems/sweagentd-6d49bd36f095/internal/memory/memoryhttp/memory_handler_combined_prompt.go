package memoryhttp

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/sweagentd/internal/memory/core"
	memstdevents "github.com/github/sweagentd/internal/memory/standardevents"
	"github.com/github/sweagentd/internal/requestctx"
)

// HandleGetCombinedPrompt handles the combined prompt endpoint that returns both
// repo-scoped and user-scoped memories in a single response.
//
// Query params:
//   - repo (optional): {owner}/{repo} — when present, repo memories are fetched and
//     the user is authorized for the repository
//   - limit (optional): max memories per scope (default: maxMemoriesForContext)
func (h *MemoryHandler) HandleGetCombinedPrompt(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	// Authenticate the user.
	userInfo, ok := requestctx.User(ctx)
	if !ok || userInfo == nil {
		logger.Warn("unauthenticated request to combined prompt")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))
	user := core.NewUser(userInfo.ID, userInfo.Login)
	limit := parseLimitParam(r, uint(maxMemoriesForContext), 1000)

	// Parse the optional repo query parameter.
	repoParam := r.URL.Query().Get("repo")
	var repoNWO *core.RepoNWO
	var repository *core.Repository
	// Per the memory opt-out matrix (github/agents#945), the controls block
	// scopes asymmetrically:
	//
	//   - User opt-out / org policy / FF / ExP / featureDisallowed:
	//     block BOTH repo and user memories. Surfaced by the user-scope
	//     check (service.CheckMemoryEnabled via isMemoryDisabledForUser).
	//     mustDropAllScopes captures this case.
	//
	//   - Repo-admin opt-out (repo_memory_disabled): blocks ONLY repo
	//     memories; user memories continue to flow (when user-scope memory
	//     is enabled) because they follow the user across repos by design.
	//     mustDropRepoScope captures this case.
	//
	// When no writable scope remains (mustDropAllScopes, or mustDropRepoScope
	// plus user-scope memory not enabled for the caller), we surface a 404
	// ErrFeatureNotEnabled rather than serving a prompt with store/vote
	// tool definitions that the agent would call only to get 404s back.
	//
	// We accept the residual cross-repo data-leak risk (a user memory
	// captured in an opted-out repo could later surface elsewhere). Per the
	// discussion in github/agents#945, that risk is addressed by prompt
	// hardening and admin messaging, not by suppressing user memories. The
	// repo-admin opt-out's job is to gate the repo's own memories, not the
	// user's.
	var mustDropAllScopes, mustDropRepoScope bool

	if repoParam != "" {
		var err error
		repoNWO, err = core.NewRepoNWOFromString(repoParam)
		if err != nil {
			logger.WithError(err).Warn("invalid repo query parameter")
			h.handleDomainError(ctx, w, err)
			return
		}

		logger = logger.WithFields(kvp.String("repo_nwo", repoNWO.String()))

		// Authorize the user for the repository.
		_, repo, status, authErr := h.authorizeWithTelemetry(ctx, repoNWO, readPermission)
		if authErr != nil {
			logger.WithError(authErr).Warn("authorization failed for combined prompt repo access")
			http.Error(w, http.StatusText(status), status)
			return
		}
		repository = repo

		mustDropAllScopes, mustDropRepoScope = h.evaluateCombinedPromptScopes(ctx, logger, userInfo, repository)
	}

	// Resolve feature flags for prompt options
	copilotAgentRuntimeVersion := r.Header.Get(RuntimeClientVersionHeaderName)
	logger = logger.WithFields(kvp.String("copilot_agent_runtime_version", copilotAgentRuntimeVersion))
	userScopedEnabled := h.resolveUserScopedEnabled(ctx, logger, userInfo)

	gating := h.applyScopeGating(ctx, logger, userScopedEnabled, mustDropAllScopes, mustDropRepoScope, repository != nil)
	if gating.noAvailableScope {
		h.handleDomainError(ctx, w, core.ErrFeatureNotEnabled)
		return
	}
	if gating.dropRepoScopeOnly {
		repoNWO = nil
		repository = nil
	}

	var votingEnablementScope votingScope
	if userScopedEnabled {
		votingEnablementScope = votingScopeRepoAndUser
	} else {
		votingEnablementScope = votingScopeRepoOnly
	}
	votingEnabled := h.isVotingEnabled(ctx, repository, logger, votingEnablementScope)
	addRequestTags(ctx, map[string]string{"voting_enabled": strconv.FormatBool(votingEnabled)})

	h.serveCombinedPrompt(ctx, w, r, logger, userInfo, user, repoNWO, repository, votingEnabled, userScopedEnabled, limit)
}

// resolveUserScopedEnabled determines whether user-scoped memory is enabled
// for the calling user by resolving plan-based feature flags and any
// additional per-integration gates.
func (h *MemoryHandler) resolveUserScopedEnabled(ctx context.Context, logger log.Logger, userInfo *requestctx.UserInfo) bool {
	// Populate context cache (memoized, so cheap if already called)
	if h.ghTwirp != nil {
		_, err := h.ghTwirp.GetCopilotUserDetails(ctx, int64(userInfo.ID))
		if err != nil {
			logger.WithError(err).Warn("failed to resolve user details for plan-based flag routing")
		}
	}
	// Single source of truth for plan → flag routing
	userScopedFlag, err := core.UserScopedMemoryFlag(ctx, int64(userInfo.ID))
	if err != nil {
		logger.WithError(err).Warn("failed to resolve user plan for flag routing",
			kvp.Int64("user_id", int64(userInfo.ID)),
		)
	}
	enabled := h.featureFlagClient != nil &&
		h.featureFlagClient.IsEnabledForUser(ctx, userScopedFlag, int64(userInfo.ID))

	// Some integrations (e.g. CCR) require an additional per-client feature flag
	// beyond the general FeatureUserScopedMemory flag.
	if enabled {
		if additionalFlag := core.UserScopedMemoryFlagFromContext(ctx); additionalFlag != "" {
			enabled = h.featureFlagClient.IsEnabledForUser(ctx, additionalFlag, int64(userInfo.ID))
		}
	}
	return enabled
}

// scopeGatingResult holds the outcome of scope gating for the combined prompt.
type scopeGatingResult struct {
	noAvailableScope  bool
	dropRepoScopeOnly bool
}

// applyScopeGating composes the gate decision that determines which memory
// scopes (if any) are available.
func (h *MemoryHandler) applyScopeGating(
	ctx context.Context, logger log.Logger,
	userScopedEnabled, mustDropAllScopes, mustDropRepoScope, hasRepo bool,
) scopeGatingResult {
	noAvailableScope := mustDropAllScopes ||
		(mustDropRepoScope && !userScopedEnabled) ||
		(!userScopedEnabled && !hasRepo)
	dropRepoScopeOnly := mustDropRepoScope && !noAvailableScope

	logger.WithFields(
		kvp.Bool("must_drop_all_scopes", mustDropAllScopes),
		kvp.Bool("must_drop_repo_scope", mustDropRepoScope),
		kvp.Bool("user_scoped_enabled", userScopedEnabled),
		kvp.Bool("no_available_scope", noAvailableScope),
		kvp.Bool("drop_repo_scope_only", dropRepoScopeOnly),
	).Info("combined prompt scope routing decision")

	if noAvailableScope {
		logger.Info("no writable memory scope for combined prompt; returning feature-not-enabled")
		h.obsv.Increment(ctx, "MemoryHandler.HandleGetCombinedPrompt.no_available_scope", memoryRequestMetricTags(ctx, nil))
	}
	if dropRepoScopeOnly {
		logger.Info("dropping repo scope from combined prompt; user scope still writable")
		h.obsv.Increment(ctx, "MemoryHandler.HandleGetCombinedPrompt.repo_scope_dropped", memoryRequestMetricTags(ctx, nil))
	}

	return scopeGatingResult{
		noAvailableScope:  noAvailableScope,
		dropRepoScopeOnly: dropRepoScopeOnly,
	}
}

// serveCombinedPrompt fetches memories, builds the prompt response, encodes it,
// and writes it to the ResponseWriter. It also logs success telemetry and
// publishes the retrieval event.
func (h *MemoryHandler) serveCombinedPrompt(
	ctx context.Context, w http.ResponseWriter, r *http.Request,
	logger log.Logger,
	userInfo *requestctx.UserInfo, user core.User,
	repoNWO *core.RepoNWO, repository *core.Repository,
	votingEnabled, userScopedEnabled bool,
	limit uint,
) {
	fetchResult, fetchErr := h.fetchCombinedMemories(ctx, logger, user, repository, votingEnabled, limit, userScopedEnabled)
	if fetchErr != nil {
		logger.WithError(fetchErr).Error("all memory fetches failed for combined prompt")
		h.handleDomainError(ctx, w, fetchErr)
		return
	}

	builder := newCombinedPromptBuilder(
		fetchResult.repoMemories, fetchResult.userMemories,
		repoNWO, userInfo.Login,
		withVoting(votingEnabled), withUserScoped(userScopedEnabled),
	)
	response, err := builder.buildResponse()
	if err != nil {
		logger.WithError(err).Error("failed to build combined prompt response")
		h.reportException(ctx, err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Clear per-scope counts for scopes that were not requested or whose fetch
	// failed so the response distinguishes "disabled/unavailable" (field absent)
	// from "enabled with zero memories" (field present as 0).
	if !fetchResult.userOK {
		response.MemoriesContext.UserMemoriesCount = nil
	}
	if repository == nil || !fetchResult.repoOK {
		response.MemoriesContext.RepoMemoriesCount = nil
	}

	h.populateTotalCounts(ctx, logger, user, repository, fetchResult, &response)

	// Encode to a buffer first so we can return a proper error status if encoding fails,
	// rather than writing a partial/corrupted response after the status header is sent.
	var buf bytes.Buffer
	err = json.NewEncoder(&buf).Encode(response)
	if err != nil {
		logger.WithError(err).Error("failed to encode combined prompt response")
		h.reportException(ctx, err)
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = buf.WriteTo(w)

	h.logCombinedPromptSuccess(logger, response, repository != nil, votingEnabled)

	// Publish standard event for memory retrieval (ExP experimentation only)
	userCount := int64(len(fetchResult.userMemories))
	repoCount := int64(len(fetchResult.repoMemories))
	h.expEventPublisher.PublishRetrieval(ctx, memstdevents.RetrievalParams{
		UserInfo:        userInfo,
		Repository:      repository,
		ReqCtx:          memstdevents.ExtractRequestContext(r),
		StartTime:       requestctx.RequestStartedAtOrNow(ctx),
		Scope:           "combined",
		UserMemoryCount: &userCount,
		RepoMemoryCount: &repoCount,
	})
}

// memResult holds the result of a concurrent memory fetch.
type memResult struct {
	memories []*core.Memory
	err      error
}

// evaluateCombinedPromptScopes runs the two-step memory enablement check for
// a repo-scoped combined-prompt request and reports which scopes (if any)
// must be dropped from the response. Per the memory opt-out matrix in
// github/agents#945:
//
//  1. User-affecting layers (Policy + repo/owner FF + featureDisallowed)
//     gate BOTH scopes. If they say disabled -- or error -- we drop both
//     (mustDropAllScopes=true).
//  2. Repo-admin opt-out gates ONLY the repo scope. If it says disabled --
//     or errors -- we drop only the repo scope (mustDropRepoScope=true).
//     It is called fail-closed (failClosedOnError=true) because
//     combined-prompt is the data-flow injection point: a transient Dotcom
//     Twirp blip must not silently surface repo memories from a
//     possibly opted-out repo.
//
// User memories are always allowed through the repo-admin layer by design;
// they follow the user across repos and are gated only by step 1.
//
// Decision table (composes with userScopedEnabled at the gate site):
//
//	mustDropAllScopes | mustDropRepoScope | userScopedEnabled | result
//	------------------+-------------------+-------------------+----------------------------
//	true              | (n/a)             | (n/a)             | 404 (no prompt emitted)
//	false             | true              | false             | 404 (no writable scope)
//	false             | true              | true              | 200, repo scope cleared
//	false             | false             | (n/a)             | 200, both scopes served
func (h *MemoryHandler) evaluateCombinedPromptScopes(ctx context.Context, logger log.Logger, userInfo *requestctx.UserInfo, repository *core.Repository) (mustDropAllScopes, mustDropRepoScope bool) {
	userDisabled, userErr := h.isMemoryDisabledForUser(ctx, userInfo, repository)
	if userErr != nil {
		logger.WithError(userErr).Warn("user-scope memory chain errored for combined prompt; dropping all scopes")
		h.obsv.Increment(ctx, "MemoryHandler.HandleGetCombinedPrompt.user_chain_error", memoryRequestMetricTags(ctx, nil))
		return true, false
	}
	if userDisabled {
		logger.Info("memory disabled at user-scope layer; dropping all scopes from combined prompt")
		h.obsv.Increment(ctx, "MemoryHandler.HandleGetCombinedPrompt.user_disabled", memoryRequestMetricTags(ctx, nil))
		return true, false
	}

	repoAdminDisabled, repoAdminErr := h.isMemoryDisabledByRepoAdmin(ctx, repository, int64(userInfo.ID), true)
	if repoAdminErr != nil {
		logger.WithError(repoAdminErr).Warn("repo-admin check errored for combined prompt; dropping repo scope")
		h.obsv.Increment(ctx, "MemoryHandler.HandleGetCombinedPrompt.repo_admin_error", memoryRequestMetricTags(ctx, nil))
		return false, true
	}
	if repoAdminDisabled {
		logger.Info("memory disabled at repo-admin layer; dropping repo scope from combined prompt")
		h.obsv.Increment(ctx, "MemoryHandler.HandleGetCombinedPrompt.repo_admin_disabled", memoryRequestMetricTags(ctx, nil))
		return false, true
	}
	return false, false
}

// combinedFetchResult holds the results of a combined memory fetch,
// including which scopes were successfully retrieved.
type combinedFetchResult struct {
	userMemories  []*core.Memory
	repoMemories  []*core.Memory
	userOK        bool // true when user-scope fetch succeeded (or returned ErrNoMemoriesNotFound)
	repoOK        bool // true when repo-scope fetch succeeded (or returned ErrNoMemoriesNotFound)
	billingFilter *core.BillingEntity
}

// fetchCombinedMemories fetches user and repo memories concurrently with graceful degradation.
// Returns an error only when all requested scopes fail.
// Billing resolution for user memories is performed upfront; when resolution
// fails the user scope is treated as failed (graceful degradation to repo-only).
func (h *MemoryHandler) fetchCombinedMemories(ctx context.Context, logger log.Logger, user core.User, repository *core.Repository, votingEnabled bool, limit uint, userScopedEnabled bool) (*combinedFetchResult, error) {
	var billingFilter *core.BillingEntity

	repoCh := make(chan memResult, 1)
	if repository != nil {
		go func() {
			var m []*core.Memory
			var err error
			if votingEnabled {
				m, err = h.service.GetTopMemories(ctx, user, repository, limit)
			} else {
				m, err = h.service.GetRecentMemories(ctx, user, repository, limit)
			}
			repoCh <- memResult{m, err}
		}()
	} else {
		repoCh <- memResult{}
	}

	userCh := make(chan memResult, 1)
	switch {
	case !userScopedEnabled:
		userCh <- memResult{}
	default:
		bf, billingErr := h.resolveBillingFilterForRetrieval(ctx, int64(user.ID))
		if billingErr != nil {
			if errors.Is(billingErr, core.ErrBillingEntityUnresolved) {
				logger.WithError(billingErr).Warn("billing entity unresolved, skipping user memories for combined prompt")
			} else {
				logger.WithError(billingErr).Warn("billing resolution failed, skipping user memories for combined prompt")
				h.obsv.Increment(ctx, "MemoryHandler.HandleGetCombinedPrompt.billing_resolution_failed", memoryRequestMetricTags(ctx, nil))
			}
			userCh <- memResult{err: billingErr}
			break
		}
		billingFilter = bf
		go func() {
			query := core.UserMemoryQuery{BillingFilter: billingFilter}
			var m []*core.Memory
			var err error
			if votingEnabled {
				m, err = h.service.GetTopUserMemories(ctx, user, limit, query)
			} else {
				m, err = h.service.GetRecentUserMemories(ctx, user, limit, query)
			}
			userCh <- memResult{m, err}
		}()
	}

	userResult := <-userCh
	repoResult := <-repoCh

	result := &combinedFetchResult{}

	if userResult.err != nil && !errors.Is(userResult.err, core.ErrNoMemoriesNotFound) {
		if errors.Is(userResult.err, core.ErrFeatureNotEnabled) {
			logger.Info("user-scoped memory not enabled, skipping for combined prompt")
		} else if !errors.Is(userResult.err, core.ErrBillingEntityUnresolved) {
			logger.WithError(userResult.err).Warn("failed to get user memories for combined prompt")
		}
	} else if userScopedEnabled {
		result.userMemories = userResult.memories
		result.userOK = true
		result.billingFilter = billingFilter
	}

	if repository != nil {
		if repoResult.err != nil && !errors.Is(repoResult.err, core.ErrNoMemoriesNotFound) {
			if errors.Is(repoResult.err, core.ErrFeatureNotEnabled) {
				logger.Info("repo-scoped memory not enabled, skipping for combined prompt")
			} else {
				logger.WithError(repoResult.err).Warn("failed to get repo memories for combined prompt")
			}
		} else {
			result.repoMemories = repoResult.memories
			result.repoOK = true
		}
	}

	// At least one scope succeeded — return the partial result.
	if result.userOK || (repository != nil && result.repoOK) {
		return result, nil
	}

	// Both scopes failed. Prefer the repo error when the user-scope error is
	// a soft failure (billing or feature flag) and the repo error is harder.
	userSoftFailure := userResult.err == nil ||
		errors.Is(userResult.err, core.ErrFeatureNotEnabled) ||
		errors.Is(userResult.err, core.ErrBillingEntityUnresolved)
	if repository != nil && repoResult.err != nil &&
		userSoftFailure &&
		!errors.Is(repoResult.err, core.ErrFeatureNotEnabled) {
		return nil, repoResult.err
	}
	if userResult.err != nil {
		return nil, userResult.err
	}
	// User scope was skipped and repo failed — surface the repo error.
	return nil, repoResult.err
}

// populateTotalCounts sets TotalRepositoryMemoriesCount and TotalUserMemoriesCount
// on the response for scopes that were successfully fetched.
// The two count queries are fired in parallel to minimize latency.
// These are best-effort — failures are logged but don't fail the request.
func (h *MemoryHandler) populateTotalCounts(ctx context.Context, logger log.Logger, user core.User, repository *core.Repository, fetchResult *combinedFetchResult, response *MemoryPromptResponse) {
	type countResult struct {
		count int
		err   error
	}

	repoCh := make(chan countResult, 1)
	userCh := make(chan countResult, 1)

	if fetchResult.repoOK && repository != nil {
		go func() {
			count, err := h.service.CountMemories(ctx, user, repository)
			repoCh <- countResult{count, err}
		}()
	} else {
		repoCh <- countResult{}
	}

	if fetchResult.userOK {
		go func() {
			count, err := h.service.CountUserMemories(ctx, user, core.UserMemoryQuery{BillingFilter: fetchResult.billingFilter})
			userCh <- countResult{count, err}
		}()
	} else {
		userCh <- countResult{}
	}

	repoResult := <-repoCh
	if fetchResult.repoOK && repository != nil {
		if repoResult.err != nil {
			logger.WithError(repoResult.err).Warn("failed to count total repo memories for combined prompt")
		} else {
			response.MemoriesContext.TotalRepositoryMemoriesCount = repoResult.count
		}
	}

	userResult := <-userCh
	if fetchResult.userOK {
		if userResult.err != nil {
			logger.WithError(userResult.err).Warn("failed to count total user memories for combined prompt")
		} else {
			response.MemoriesContext.TotalUserMemoriesCount = &userResult.count
		}
	}
}

// logCombinedPromptSuccess logs telemetry for a successful combined prompt response.
func (h *MemoryHandler) logCombinedPromptSuccess(logger log.Logger, response MemoryPromptResponse, hasRepo, votingEnabled bool) {
	repoMemoriesCount := 0
	if response.MemoriesContext.RepoMemoriesCount != nil {
		repoMemoriesCount = *response.MemoriesContext.RepoMemoriesCount
	}
	userMemoriesCount := 0
	if response.MemoriesContext.UserMemoriesCount != nil {
		userMemoriesCount = *response.MemoriesContext.UserMemoriesCount
	}

	logEntry := logger.WithFields(
		kvp.Int("total_memories_count", response.MemoriesContext.MemoriesCount),
		kvp.Int("repo_memories_count", repoMemoriesCount),
		kvp.Int("user_memories_count", userMemoriesCount),
		kvp.Bool("has_repo", hasRepo),
		kvp.Bool("memory_voting_enabled", votingEnabled),
		kvp.String("memories_context_prompt_version", string(response.MemoriesContext.PromptVersion)),
		kvp.String("store_instructions_prompt_version", string(response.StoreInstructions.PromptVersion)),
		kvp.String("tool_definition_version", string(response.StoreToolDefinition.DefinitionVersion)),
		kvp.Bool("has_vote_tool_definition", response.VoteToolDefinition != nil),
	)
	if response.VoteToolDefinition != nil {
		logEntry = logEntry.WithFields(
			kvp.String("vote_tool_definition_version", string(response.VoteToolDefinition.DefinitionVersion)),
		)
	}
	logEntry.Info("combined prompt retrieved successfully")
}
