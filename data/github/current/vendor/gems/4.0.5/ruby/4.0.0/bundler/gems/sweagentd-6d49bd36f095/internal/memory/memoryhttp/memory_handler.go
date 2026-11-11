package memoryhttp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
	memstdevents "github.com/github/sweagentd/internal/memory/standardevents"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
)

// RuntimeClientVersionHeaderName is the HTTP header used by the runtime client to send its version.
const RuntimeClientVersionHeaderName = "Runtime-Client-Version"

// Telemetry metric names for memory handler operations.
const (
	metricRequestDuration   = "memory_handler.request_duration"
	metricRequestCount      = "memory_handler.request_count"
	metricRequestOutcome    = "memory_handler.request_outcome"
	metricResponseStatus    = "memory_handler.response_status"
	metricAuthorizeDuration = "memory_handler.authorize_duration"
	metricUserTokenFallback = "memory_handler.user_token_fallback"
	metricAuthorizeFailure  = "memory_handler.authorize_failure"
	metricTokenAccessCheck  = "memory_handler.token_access_check"
)

// copilotDeveloperIntegrationID is the Copilot-Integration-Id header value
// used by CCA (Copilot Coding Agent) in production.
const copilotDeveloperIntegrationID = "copilot-developer"

// MemoryHandler handles HTTP requests for memory operations.
type MemoryHandler struct {
	service               core.MemoryService
	ghFactory             github.ClientFactoryInterface
	obsv                  observability.Exporters
	appProvider           *agenticapp.Provider
	featureFlagClient     featureflags.Client
	ghTwirp               githubtwirp.ClientInterface
	privilegedAppChecker  github.PrivilegedAppCheckerClient
	expClient             exp.ExperimentationClient
	expEventPublisher     *memstdevents.Publisher
	isDevelopment         bool
	billingEntityResolver core.BillingEntityResolver
}

// MemoryHandlerOpts holds the dependencies for creating a MemoryHandler.
type MemoryHandlerOpts struct {
	Service               core.MemoryService
	GHFactory             github.ClientFactoryInterface
	Obsv                  observability.Exporters
	AppProvider           *agenticapp.Provider
	FeatureFlagClient     featureflags.Client
	GHTwirp               githubtwirp.ClientInterface
	PrivilegedAppChecker  github.PrivilegedAppCheckerClient
	ExpClient             exp.ExperimentationClient
	IsDevelopment         bool
	BillingEntityResolver core.BillingEntityResolver
}

// NewMemoryHandler creates a new MemoryHandler instance.
func NewMemoryHandler(opts MemoryHandlerOpts) *MemoryHandler {
	return &MemoryHandler{
		service:               opts.Service,
		ghFactory:             opts.GHFactory,
		obsv:                  opts.Obsv,
		appProvider:           opts.AppProvider,
		featureFlagClient:     opts.FeatureFlagClient,
		ghTwirp:               opts.GHTwirp,
		privilegedAppChecker:  opts.PrivilegedAppChecker,
		expClient:             opts.ExpClient,
		expEventPublisher:     memstdevents.NewPublisher(opts.Obsv, opts.FeatureFlagClient),
		isDevelopment:         opts.IsDevelopment,
		billingEntityResolver: opts.BillingEntityResolver,
	}
}

// HandleCreateMemory handles the creation of a new memory.
//
// This handler runs behind withRepoMemoryCheck(writePermission), which has
// already authorised the user and verified that memory is enabled for this
// repo (Policy + repo/owner FF + repo admin setting). Auth state is read from
// ctx via requireRepoAuth.
func (h *MemoryHandler) HandleCreateMemory(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, repository, repoNWO, err := h.requireRepoAuth(ctx)
	if err != nil {
		logger.WithError(err).Error("missing repo auth in HandleCreateMemory")
		h.reportException(ctx, err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	logger = logger.WithFields(
		kvp.String("repo_nwo", repoNWO.String()),
		kvp.Uint64("user_id", userInfo.ID),
	)

	var memoryDTO MemoryDTO
	err = json.NewDecoder(r.Body).Decode(&memoryDTO)
	if err != nil {
		logger.WithError(err).Warn("failed to decode memory request body")
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	memory, err := memoryDTO.ToDomain(*repoNWO, *userInfo)
	if err != nil {
		logger.WithError(err).Warn("failed to convert memory DTO to domain")
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	memory.Scope = core.MemoryScopeRepository

	// Create the memory using the service
	err = h.service.CreateMemory(ctx, memory, repository)
	if err != nil {
		logger.WithError(err).Warn("failed to create memory")
		h.handleDomainError(ctx, w, err)
		return
	}

	var responseDTO any = FromDomain(memory)
	if h.isVerboseRequest(ctx, r, userInfo.ID, logger) {
		responseDTO = VerboseFromDomain(memory)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	err = json.NewEncoder(w).Encode(responseDTO)
	if err != nil {
		logger.WithError(err).Error("failed to encode response")
		h.reportException(ctx, err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	logger.WithFields(kvp.String("memory_id", memory.ID.String())).Info("memory created successfully")

	// Publish standard event for memory store (ExP experimentation only)
	h.expEventPublisher.PublishStore(ctx, memstdevents.StoreParams{
		UserInfo:      userInfo,
		Repository:    repository,
		AgentName:     memory.Source.Agent,
		InteractionID: memory.Source.InteractionID, // = job ID for CCA
		ReqCtx:        memstdevents.ExtractRequestContext(r),
		StartTime:     requestctx.RequestStartedAtOrNow(ctx),
		Scope:         "repository",
	})
}

// HandleGetRecentMemories handles requests to get the most recent N memories.
//
// Runs behind withRepoMemoryCheck(readPermission); auth is read from ctx.
func (h *MemoryHandler) HandleGetRecentMemories(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, repository, repoNWO, err := h.requireRepoAuth(ctx)
	if err != nil {
		logger.WithError(err).Error("missing repo auth in HandleGetRecentMemories")
		h.reportException(ctx, err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	logger = logger.WithFields(
		kvp.String("repo_nwo", repoNWO.String()),
		kvp.Uint64("user_id", userInfo.ID),
	)

	limit := parseLimitParam(r, 10, 1000)

	logger = logger.WithFields(kvp.Uint("limit", limit))

	user := core.NewUser(userInfo.ID, userInfo.Login)
	memories, err := h.service.GetRecentMemories(ctx, user, repository, limit)
	if err != nil {
		logger.WithError(err).Warn("failed to get recent memories")
		h.handleDomainError(ctx, w, err)
		return
	}

	verbose := h.isVerboseRequest(ctx, r, userInfo.ID, logger)
	h.writeMemoriesResponse(ctx, w, logger, "get_recent_memories", memories, core.MemoryScopeRepository, verbose)

	// Publish standard event for memory retrieval (ExP experimentation only)
	repoMemCount := int64(len(memories))
	h.expEventPublisher.PublishRetrieval(ctx, memstdevents.RetrievalParams{
		UserInfo:        userInfo,
		Repository:      repository,
		ReqCtx:          memstdevents.ExtractRequestContext(r),
		StartTime:       requestctx.RequestStartedAtOrNow(ctx),
		Scope:           "repository",
		RepoMemoryCount: &repoMemCount,
	})
}

// HandleGetTopMemories handles requests for the top-scored memories for a repository.
// It fetches all memories, scores and ranks them, and returns the top N.
//
// Runs behind withRepoMemoryCheck(readPermission); auth is read from ctx.
func (h *MemoryHandler) HandleGetTopMemories(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, repository, repoNWO, err := h.requireRepoAuth(ctx)
	if err != nil {
		logger.WithError(err).Error("missing repo auth in HandleGetTopMemories")
		h.reportException(ctx, err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	logger = logger.WithFields(
		kvp.String("repo_nwo", repoNWO.String()),
		kvp.Uint64("user_id", userInfo.ID),
	)

	limit := parseLimitParam(r, 20, 1000)

	logger = logger.WithFields(kvp.Uint("limit", limit))

	user := core.NewUser(userInfo.ID, userInfo.Login)
	memories, err := h.service.GetTopMemories(ctx, user, repository, limit)
	if err != nil {
		logger.WithError(err).Warn("failed to get top memories")
		h.handleDomainError(ctx, w, err)
		return
	}

	verbose := h.isVerboseRequest(ctx, r, userInfo.ID, logger)
	h.writeMemoriesResponse(ctx, w, logger, "get_top_memories", memories, core.MemoryScopeRepository, verbose)
}

// HandleDeleteMemory handles the deletion of a specific memory by ID.
//
// Runs behind withRepoMemoryCheck(writePermission); auth is read from ctx.
func (h *MemoryHandler) HandleDeleteMemory(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, repository, repoNWO, err := h.requireRepoAuth(ctx)
	if err != nil {
		logger.WithError(err).Error("missing repo auth in HandleDeleteMemory")
		h.reportException(ctx, err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	logger = logger.WithFields(
		kvp.String("repo_nwo", repoNWO.String()),
		kvp.Uint64("user_id", userInfo.ID),
	)

	memoryIDParam := chi.URLParam(r, "memoryId")
	if memoryIDParam == "" {
		logger.Warn("memory ID is empty")
		http.Error(w, "memory ID cannot be empty", http.StatusBadRequest)
		return
	}
	memoryID := core.MemoryID(memoryIDParam)
	logger = logger.WithFields(kvp.String("memory_id", memoryIDParam))

	user := core.NewUser(userInfo.ID, userInfo.Login)

	err = h.service.DeleteMemory(ctx, user, repository, memoryID)
	if err != nil {
		logger.WithError(err).Warn("failed to delete memory")
		h.handleDomainError(ctx, w, err)
		return
	}
	h.publishHydroDeleteTelemetry(ctx, "delete_single", repoNWO, userInfo, string(memoryID))
	// Publish StandardEvent for ExP experimentation only
	h.expEventPublisher.PublishDelete(ctx, memstdevents.DeleteParams{
		UserInfo:   userInfo,
		Repository: repository,
		ReqCtx:     memstdevents.ExtractRequestContext(r),
		StartTime:  requestctx.RequestStartedAtOrNow(ctx),
		Operation:  "delete_single",
		MemoryID:   string(memoryID),
	})

	logger.Info("memory deleted successfully")
	w.WriteHeader(http.StatusNoContent)
}

// HandleVoteMemory handles voting on a specific memory identified by its fact text.
//
// Runs behind withRepoMemoryCheck(writePermission); auth is read from ctx.
func (h *MemoryHandler) HandleVoteMemory(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, repository, repoNWO, err := h.requireRepoAuth(ctx)
	if err != nil {
		logger.WithError(err).Error("missing repo auth in HandleVoteMemory")
		h.reportException(ctx, err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	logger = logger.WithFields(
		kvp.String("repo_nwo", repoNWO.String()),
		kvp.Uint64("user_id", userInfo.ID),
	)

	var voteRequest VoteRequest
	err = json.NewDecoder(r.Body).Decode(&voteRequest)
	if err != nil {
		logger.WithError(err).Warn("failed to decode vote request body")
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	user := core.NewUser(userInfo.ID, userInfo.Login)

	// This will validate the request and convert it to the domain Vote type
	vote, err := voteRequest.ToDomain(userInfo, repository)
	if err != nil {
		logger.WithError(err).Warn("Invalid vote request. Failed to convert vote request to domain object.")
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	err = h.service.VoteOnMemory(ctx, user, repository, voteRequest.Fact, vote)
	if err != nil {
		logger.WithError(err).Warn("failed to vote on memory")
		h.handleDomainError(ctx, w, err)
		return
	}

	logger.Info("vote recorded successfully")
	w.WriteHeader(http.StatusNoContent)

	// Publish standard event for memory vote (ExP experimentation only)
	h.expEventPublisher.PublishVote(ctx, memstdevents.VoteParams{
		UserInfo:      userInfo,
		Repository:    repository,
		AgentName:     voteRequest.Agent,
		InteractionID: voteRequest.InteractionID,
		Direction:     voteRequest.Direction,
		ReqCtx:        memstdevents.ExtractRequestContext(r),
		StartTime:     requestctx.RequestStartedAtOrNow(ctx),
		Scope:         "repository",
	})
}

// maxBatchDeleteSize is the maximum number of memory IDs that can be deleted in a
// single batch request. This limit prevents excessively large requests.
const maxBatchDeleteSize = 500

// HandleDeleteMemories handles the deletion of multiple memories by their IDs.
func (h *MemoryHandler) HandleDeleteMemories(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, repository, repoNWO, err := h.requireRepoAuth(ctx)
	if err != nil {
		logger.WithError(err).Error("missing repo auth in HandleDeleteMemories")
		h.reportException(ctx, err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	logger = logger.WithFields(
		kvp.String("repo_nwo", repoNWO.String()),
		kvp.Uint64("user_id", userInfo.ID),
	)

	var req BatchDeleteRequest
	err = json.NewDecoder(r.Body).Decode(&req)
	if err != nil {
		logger.WithError(err).Warn("failed to decode batch delete request body")
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if len(req.IDs) == 0 {
		logger.Warn("batch delete request with empty IDs")
		http.Error(w, "ids cannot be empty", http.StatusBadRequest)
		return
	}

	if len(req.IDs) > maxBatchDeleteSize {
		logger.WithFields(kvp.Int("ids_count", len(req.IDs))).Warn("batch delete request exceeds maximum size")
		http.Error(w, fmt.Sprintf("too many ids, maximum is %d", maxBatchDeleteSize), http.StatusBadRequest)
		return
	}

	user := core.NewUser(userInfo.ID, userInfo.Login)

	memoryIDs := make([]core.MemoryID, len(req.IDs))
	for i, id := range req.IDs {
		memoryIDs[i] = core.MemoryID(id)
	}

	result, err := h.service.DeleteMemories(ctx, user, repository, memoryIDs)
	if err != nil {
		logger.WithError(err).Warn("failed to delete memories")
		// On partial failure, return 200 with whatever we managed to delete/fail.
		if result != nil && len(result.Deleted) > 0 {
			h.publishHydroDeleteTelemetry(ctx, "delete_batch", repoNWO, userInfo, "")
			h.expEventPublisher.PublishDelete(ctx, memstdevents.DeleteParams{
				UserInfo:   userInfo,
				Repository: repository,
				ReqCtx:     memstdevents.ExtractRequestContext(r),
				StartTime:  requestctx.RequestStartedAtOrNow(ctx),
				Operation:  "delete_batch",
			})
			setRequestOutcome(ctx, outcomePartial)
			h.writeBatchDeleteResponse(ctx, w, result)
			return
		}
		h.handleDomainError(ctx, w, err)
		return
	}
	h.publishHydroDeleteTelemetry(ctx, "delete_batch", repoNWO, userInfo, "")
	h.expEventPublisher.PublishDelete(ctx, memstdevents.DeleteParams{
		UserInfo:   userInfo,
		Repository: repository,
		ReqCtx:     memstdevents.ExtractRequestContext(r),
		StartTime:  requestctx.RequestStartedAtOrNow(ctx),
		Operation:  "delete_batch",
	})

	logger.WithFields(kvp.Int("deleted_count", len(result.Deleted))).Info("memories deleted successfully")
	h.writeBatchDeleteResponse(ctx, w, result)
}

// HandleDeleteAllMemories handles the deletion of all memories for a repository.
//
// Runs behind withRepoMemoryCheck(writePermission); auth is read from ctx.
func (h *MemoryHandler) HandleDeleteAllMemories(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, repository, repoNWO, err := h.requireRepoAuth(ctx)
	if err != nil {
		logger.WithError(err).Error("missing repo auth in HandleDeleteAllMemories")
		h.reportException(ctx, err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	logger = logger.WithFields(
		kvp.String("repo_nwo", repoNWO.String()),
		kvp.Uint64("user_id", userInfo.ID),
	)

	user := core.NewUser(userInfo.ID, userInfo.Login)

	err = h.service.DeleteAllMemories(ctx, user, repository)
	if err != nil {
		logger.WithError(err).Warn("failed to delete all memories")
		h.handleDomainError(ctx, w, err)
		return
	}
	h.publishHydroDeleteTelemetry(ctx, "delete_all", repoNWO, userInfo, "")
	h.expEventPublisher.PublishDelete(ctx, memstdevents.DeleteParams{
		UserInfo:   userInfo,
		Repository: repository,
		ReqCtx:     memstdevents.ExtractRequestContext(r),
		StartTime:  requestctx.RequestStartedAtOrNow(ctx),
		Operation:  "delete_all",
	})

	logger.Info("all memories deleted successfully")
	w.WriteHeader(http.StatusNoContent)
}

// HandleCheckMemoryEnabled checks if the memory feature is enabled for the authenticated user.
//
// Unlike the other repo-scoped routes, this endpoint is NOT wrapped with
// withRepoMemoryCheck — its purpose is to query the chain and return the
// answer as JSON, not to be blocked by it. It calls the same chain helper
// (isMemoryDisabledForRepo) so the answer is consistent with what the
// middleware would enforce on other endpoints.
func (h *MemoryHandler) HandleCheckMemoryEnabled(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
	if err != nil {
		logger.WithError(err).Warn("invalid repository NWO")
		h.handleDomainError(ctx, w, err)
		return
	}

	logger = logger.WithFields(kvp.String("repo_nwo", repoNWO.String()))

	// Early check: If memory is disabled at user level, return immediately without expensive authorization.
	// This optimization avoids the GitHub API call when we already know the feature is disabled for the user.
	if h.checkUserLevelMemoryDisabled(ctx) {
		logger.Info("memory disabled at user level")
		response := MemoryEnablementResponse{Enabled: false}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		err := json.NewEncoder(w).Encode(response)
		if err != nil {
			logger.WithError(err).Error("failed to encode response")
			h.reportException(ctx, err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		return
	}

	// Check integration ID early to determine if this is a CCA request.
	// Only CCA requests need experiment assignment; other callers skip the
	// ExP SDK call to avoid unnecessary overhead.
	isCCARequest := featureflags.IntegrationIDFromContext(ctx) == copilotDeveloperIntegrationID

	var userInfo *requestctx.UserInfo
	var repository *core.Repository
	var status int
	if isCCARequest {
		ctx, userInfo, repository, status, err = h.authorizeAndAssign(ctx, repoNWO, readPermission)
	} else {
		userInfo, repository, status, err = h.authorizeWithTelemetry(ctx, repoNWO, readPermission)
	}
	if err != nil {
		logger.WithError(err).Warn("authorization failed for check memory enabled")
		http.Error(w, err.Error(), status)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	disabled, err := h.isMemoryDisabledForRepo(ctx, userInfo, repository, false)
	if err != nil {
		logger.WithError(err).Error("failed to check memory enablement")
		h.obsv.Increment(ctx, "MemoryHandler.HandleCheckMemoryEnabled.error", memoryRequestMetricTags(ctx, nil))
		h.reportException(ctx, err)
		http.Error(w, "Failed to check memory enablement", http.StatusInternalServerError)
		return
	}
	enabled := !disabled

	// If an experiment is active for this repo, check the variant to potentially override enablement.
	// When no experiment is running (or the caller is not CCA), the assignment context is empty
	// and we skip this entirely, preserving the existing behavior.
	assignment := exp.AssignmentFromContext(ctx)
	if assignmentCtx := assignment.GetAssignmentContext(); assignmentCtx != "" {
		flagKey := exp.FlagKey(exp.MemoryExperiment)
		memoryEnabled := assignment.GetBool(flagKey, true)
		h.obsv.Increment(ctx, "memory.experiment", memoryRequestMetricTags(ctx, map[string]string{"memory_enabled": strconv.FormatBool(memoryEnabled)}))
		if !memoryEnabled {
			enabled = false
		}
	}

	response := MemoryEnablementResponse{Enabled: enabled}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		logger.WithError(err).Error("failed to encode response")
		h.reportException(ctx, err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	logger.WithFields(kvp.Bool("enabled", enabled)).Info("memory enablement check completed")
}

// HandleGetPrompt returns the store-instructions prompt and the memories context prompt
// for the given repository in a single response.
//
// Deprecated: This legacy endpoint returns repo-scoped memories only.
// All active consumers (CCA, CLI, 3P MCP, CCR) have migrated to HandleGetCombinedPrompt
// which returns both repo and user memories via /memory/v0/prompt?repo=owner/repo.
// TODO: Remove this endpoint and do not add new features to this handler.
//
// Runs behind withRepoMemoryCheck(readPermission); auth (and ExP assignment
// for CCA callers) is performed by the middleware. Auth is read from ctx.
func (h *MemoryHandler) HandleGetPrompt(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, repository, repoNWO, err := h.requireRepoAuth(ctx)
	if err != nil {
		logger.WithError(err).Error("missing repo auth in HandleGetPrompt")
		h.reportException(ctx, err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	copilotIntegrationID := featureflags.IntegrationIDFromContext(ctx)
	logger = logger.WithFields(
		kvp.String("repo_nwo", repoNWO.String()),
		kvp.Uint64("user_id", userInfo.ID),
	)

	copilotAgentRuntimeVersion := r.Header.Get(RuntimeClientVersionHeaderName)
	logger = logger.WithFields(kvp.String("copilot_agent_runtime_version", copilotAgentRuntimeVersion))
	logger = logger.WithFields(kvp.String("copilot_integration_id", copilotIntegrationID))

	user := core.NewUser(userInfo.ID, userInfo.Login)
	// This handler is just for repo memories not the combined prompt thus we only want to verify enablement at the repo level
	votingEnabled := h.isVotingEnabled(ctx, repository, logger, votingScopeRepoOnly)
	addRequestTags(ctx, map[string]string{"voting_enabled": strconv.FormatBool(votingEnabled)})

	// We want to let the limit be parameterisable because of experimentation with
	// how many memories to include in the context prompt, but we also want to have
	// a reasonable default and maximum to prevent abuse.
	limit := uint(maxMemoriesForContext) // Default limit for prompt context
	if limitParam := r.URL.Query().Get("limit"); limitParam != "" {
		parsedLimit, parseErr := strconv.Atoi(limitParam)
		if parseErr == nil && parsedLimit > 0 {
			limit = uint(parsedLimit)
		}
	}

	// For CCA callers, override the limit from the experiment assignment if active.
	// This follows the same pattern as CCR's ccr_memory_limit experiment.
	if copilotIntegrationID == copilotDeveloperIntegrationID {
		limit = h.applyMemoryLimitExperiment(ctx, limit, logger)
	}

	// When voting is enabled, fetch the top-scored memories so the prompt
	// reflects vote rank order instead of pure recency.
	var memories []*core.Memory
	var memErr error
	if votingEnabled {
		memories, memErr = h.service.GetTopMemories(ctx, user, repository, limit)
	} else {
		memories, memErr = h.service.GetRecentMemories(ctx, user, repository, limit)
	}

	// No memories is fine — return empty prompt with count 0.
	if memErr != nil && !errors.Is(memErr, core.ErrNoMemoriesNotFound) {
		logger.WithError(memErr).Warn("failed to get memories for prompt")
		h.handleDomainError(ctx, w, memErr)
		return
	}

	// Count is best-effort — only fetch after successful memory retrieval
	// to avoid inflating latency on error paths.
	var totalMemoriesCount int
	count, countErr := h.service.CountMemories(ctx, user, repository)
	if countErr != nil {
		logger.WithError(countErr).Warn("failed to count total memories for repository")
	} else {
		totalMemoriesCount = count
	}

	builder := newPromptBuilder(memories, withVoting(votingEnabled))
	response, err := builder.buildResponse()
	if err != nil {
		logger.WithError(err).Error("failed to build prompt response")
		h.reportException(ctx, err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	response.MemoriesContext.TotalRepositoryMemoriesCount = totalMemoriesCount

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		logger.WithError(err).Error("failed to encode prompt response")
		h.reportException(ctx, err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	logEntry := logger.WithFields(
		kvp.Int("memories_count", builder.memoriesCount()),
		kvp.Int("total_memories_count", totalMemoriesCount),
		kvp.Int("memory_limit", int(limit)),
		kvp.Bool("memory_voting_enabled", votingEnabled),
		kvp.String("store_instructions_prompt_version", string(response.StoreInstructions.PromptVersion)),
		kvp.String("memories_context_prompt_version", string(response.MemoriesContext.PromptVersion)),
		kvp.String("tool_definition_version", string(response.StoreToolDefinition.DefinitionVersion)),
		kvp.Bool("has_vote_tool_definition", response.VoteToolDefinition != nil),
	)
	if response.VoteToolDefinition != nil {
		logEntry = logEntry.WithFields(
			kvp.String("vote_tool_definition_version", string(response.VoteToolDefinition.DefinitionVersion)),
		)
	}
	logEntry.Info("prompt retrieved successfully")

	// Publish standard event for memory retrieval (ExP experimentation only)
	repoMemCount := int64(len(memories))
	h.expEventPublisher.PublishRetrieval(ctx, memstdevents.RetrievalParams{
		UserInfo:        userInfo,
		Repository:      repository,
		ReqCtx:          memstdevents.ExtractRequestContext(r),
		StartTime:       requestctx.RequestStartedAtOrNow(ctx),
		Scope:           "repository",
		RepoMemoryCount: &repoMemCount,
	})
}

// resolveBillingFilterForRetrieval resolves the billing entity for user memory
// retrieval. Returns a non-nil *BillingEntity when billing enforcement is enabled
// and resolution succeeds, or nil when enforcement is disabled. Returns an error
// when enforcement is active but resolution fails (fail-closed).
func (h *MemoryHandler) resolveBillingFilterForRetrieval(ctx context.Context, userID int64) (*core.BillingEntity, error) {
	if h.featureFlagClient == nil || !h.featureFlagClient.IsEnabledForUser(ctx, core.FeatureMemoryBillingEnforcedRetrieval, userID) {
		return nil, nil
	}
	if h.billingEntityResolver == nil {
		return nil, goerrors.New("billing infrastructure not configured")
	}
	billingEntity, err := h.billingEntityResolver.ResolveBillingEntity(ctx, userID)
	if err != nil {
		return nil, goerrors.Errorf("billing resolution failed: %w", err)
	}
	if billingEntity.IsUnresolved() {
		return nil, core.ErrBillingEntityUnresolved
	}
	return &core.BillingEntity{
		OrganizationID: billingEntity.OrganizationID,
		EnterpriseID:   billingEntity.EnterpriseID,
		Resolved:       true,
	}, nil
}
