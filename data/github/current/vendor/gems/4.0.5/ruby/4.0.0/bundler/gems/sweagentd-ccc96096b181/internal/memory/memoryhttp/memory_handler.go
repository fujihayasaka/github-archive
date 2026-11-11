package memoryhttp

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
)

// Telemetry metric names for memory handler operations.
const (
	metricRequestDuration   = "memory_handler.request_duration"
	metricRequestCount      = "memory_handler.request_count"
	metricRequestOutcome    = "memory_handler.request_outcome"
	metricResponseStatus    = "memory_handler.response_status"
	metricAuthorizeDuration = "memory_handler.authorize_duration"
	metricUserTokenFallback = "memory_handler.user_token_fallback"
)

// MemoryHandler handles HTTP requests for memory operations.
type MemoryHandler struct {
	service     core.MemoryService
	ghFactory   github.ClientFactoryInterface
	obsv        observability.Exporters
	appProvider *agenticapp.Provider
}

// NewMemoryHandler creates a new MemoryHandler instance.
func NewMemoryHandler(service core.MemoryService, ghFactory github.ClientFactoryInterface, obsv observability.Exporters, appProvider *agenticapp.Provider) *MemoryHandler {
	return &MemoryHandler{
		service:     service,
		ghFactory:   ghFactory,
		obsv:        obsv,
		appProvider: appProvider,
	}
}

// RegisterRoutes registers the HTTP routes for memory operations.
func (h *MemoryHandler) RegisterRoutes(r chi.Router) {
	r.Route("/memory/v0/{owner}/{repo}", func(r chi.Router) {
		r.Put("/", h.HandleCreateMemory)
		r.Post("/search", h.HandleSearchMemories)
		r.Get("/recent", h.HandleGetRecentMemories)
		r.Delete("/{memoryId}", h.HandleDeleteMemory)
		r.Delete("/", h.HandleDeleteAllMemories)
		r.Get("/enabled", h.HandleCheckMemoryEnabled)
	})
}

// HandleCreateMemory handles the creation of a new memory.
func (h *MemoryHandler) HandleCreateMemory(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "MemoryHandler.HandleCreateMemory")
	defer span.End()

	logger := h.obsv.LoggerWithTelemetry(ctx)
	start := time.Now()
	endpoint := "create_memory"
	h.obsv.Statter.Increment(metricRequestCount, map[string]string{"endpoint": endpoint, "method": r.Method})

	// Extract repository NWO from URL parameters
	repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
	if err != nil {
		logger.WithError(err).Warn("invalid repository NWO")
		h.recordRequestCompletion(start, endpoint, http.StatusBadRequest, "failure")
		h.handleDomainError(w, err)
		return
	}

	logger = logger.WithFields(kvp.String("repo_nwo", repoNWO.String()))

	// Ensure user is authenticated and authorized for the particular repository.
	userInfo, repository, status, err := h.authorizeWithTelemetry(
		ctx,
		repoNWO,
		hasWritePermissions)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for create memory")
		h.recordRequestCompletion(start, endpoint, status, "failure")
		http.Error(w, err.Error(), status)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	// Decode the MemoryDTO from request body
	var memoryDTO MemoryDTO
	err = json.NewDecoder(r.Body).Decode(&memoryDTO)
	if err != nil {
		logger.WithError(err).Warn("failed to decode memory request body")
		h.recordRequestCompletion(start, endpoint, http.StatusBadRequest, "failure")
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Convert DTO to domain object
	memory := memoryDTO.ToDomain(*repoNWO, *userInfo)

	// Create the memory using the service
	err = h.service.CreateMemory(ctx, memory, repository)
	if err != nil {
		logger.WithError(err).Warn("failed to create memory")
		h.recordRequestCompletion(start, endpoint, h.errorToStatusCode(err), "failure")
		h.handleDomainError(w, err)
		return
	}

	// Return the created memory as DTO
	responseDTO := FromDomain(memory)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	err = json.NewEncoder(w).Encode(responseDTO)
	if err != nil {
		logger.WithError(err).Error("failed to encode response")
		h.recordRequestCompletion(start, endpoint, http.StatusInternalServerError, "failure")
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	logger.WithFields(kvp.String("memory_id", memory.ID.String())).Info("memory created successfully")
	h.recordRequestCompletion(start, endpoint, http.StatusCreated, "success")
}

// HandleSearchMemories handles memory search requests.
func (h *MemoryHandler) HandleSearchMemories(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "MemoryHandler.HandleSearchMemories")
	defer span.End()

	logger := h.obsv.LoggerWithTelemetry(ctx)
	start := time.Now()
	endpoint := "search_memories"
	h.obsv.Statter.Increment(metricRequestCount, map[string]string{"endpoint": endpoint, "method": r.Method})

	// Extract repository NWO from URL parameters
	repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
	if err != nil {
		logger.WithError(err).Warn("invalid repository NWO")
		h.recordRequestCompletion(start, endpoint, http.StatusBadRequest, "failure")
		h.handleDomainError(w, err)
		return
	}

	logger = logger.WithFields(kvp.String("repo_nwo", repoNWO.String()))

	// Ensure user is authenticated and authorized for the particular repository.
	userInfo, repository, status, err := h.authorizeWithTelemetry(
		ctx,
		repoNWO,
		hasReadPermission)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for search memories")
		h.recordRequestCompletion(start, endpoint, status, "failure")
		http.Error(w, err.Error(), status)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	// Decode the search request from request body
	var searchRequest MemorySearchRequest
	err = json.NewDecoder(r.Body).Decode(&searchRequest)
	if err != nil {
		logger.WithError(err).Warn("failed to decode search request body")
		h.recordRequestCompletion(start, endpoint, http.StatusBadRequest, "failure")
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	user := core.NewUser(userInfo.ID, userInfo.Login)
	// For now, we'll get all memories and filter by question in the future
	// Search for memories using the question parameter
	memories, err := h.service.GetMemories(ctx, user, repository)
	if err != nil {
		logger.WithError(err).Warn("failed to search memories")
		h.recordRequestCompletion(start, endpoint, h.errorToStatusCode(err), "failure")
		h.handleDomainError(w, err)
		return
	}

	// Convert domain objects to DTOs
	memoryDTOs := make([]*MemoryDTO, len(memories))
	for i, memory := range memories {
		memoryDTOs[i] = FromDomain(memory)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	err = json.NewEncoder(w).Encode(memoryDTOs)
	if err != nil {
		logger.WithError(err).Error("failed to encode response")
		h.recordRequestCompletion(start, endpoint, http.StatusInternalServerError, "failure")
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	logger.WithFields(kvp.Int("memories_count", len(memories))).Info("memories search completed")
	h.recordRequestCompletion(start, endpoint, http.StatusOK, "success")
}

// HandleGetRecentMemories handles requests to get the most recent N memories.
func (h *MemoryHandler) HandleGetRecentMemories(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "MemoryHandler.HandleGetRecentMemories")
	defer span.End()

	logger := h.obsv.LoggerWithTelemetry(ctx)
	start := time.Now()
	endpoint := "get_recent_memories"
	h.obsv.Statter.Increment(metricRequestCount, map[string]string{"endpoint": endpoint, "method": r.Method})

	// Extract repository NWO from URL parameters
	repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
	if err != nil {
		logger.WithError(err).Warn("invalid repository NWO")
		h.recordRequestCompletion(start, endpoint, http.StatusBadRequest, "failure")
		h.handleDomainError(w, err)
		return
	}

	logger = logger.WithFields(kvp.String("repo_nwo", repoNWO.String()))

	// Ensure user is authenticated and authorized for the particular repository.
	userInfo, repository, status, err := h.authorizeWithTelemetry(
		ctx,
		repoNWO,
		hasReadPermission)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for get recent memories")
		h.recordRequestCompletion(start, endpoint, status, "failure")
		http.Error(w, err.Error(), status)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	// Parse limit from query parameter, default to 10
	limit := uint(10)
	if limitParam := r.URL.Query().Get("limit"); limitParam != "" {
		parsedLimit, parseErr := strconv.Atoi(limitParam)
		if parseErr == nil && parsedLimit > 0 {
			limit = uint(parsedLimit)
		}
	}

	logger = logger.WithFields(kvp.Uint("limit", limit))

	user := core.NewUser(userInfo.ID, userInfo.Login)
	// Get recent memories using the service
	memories, err := h.service.GetRecentMemories(ctx, user, repository, limit)
	if err != nil {
		logger.WithError(err).Warn("failed to get recent memories")
		h.recordRequestCompletion(start, endpoint, h.errorToStatusCode(err), "failure")
		h.handleDomainError(w, err)
		return
	}

	// Convert domain objects to DTOs
	memoryDTOs := make([]*MemoryDTO, len(memories))
	for i, memory := range memories {
		memoryDTOs[i] = FromDomain(memory)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	err = json.NewEncoder(w).Encode(memoryDTOs)
	if err != nil {
		logger.WithError(err).Error("failed to encode response")
		h.recordRequestCompletion(start, endpoint, http.StatusInternalServerError, "failure")
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	logger.WithFields(kvp.Int("memories_count", len(memories))).Info("recent memories retrieved")
	h.recordRequestCompletion(start, endpoint, http.StatusOK, "success")
}

// HandleDeleteMemory handles the deletion of a specific memory by ID.
func (h *MemoryHandler) HandleDeleteMemory(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "MemoryHandler.HandleDeleteMemory")
	defer span.End()

	logger := h.obsv.LoggerWithTelemetry(ctx)
	start := time.Now()
	endpoint := "delete_memory"
	h.obsv.Statter.Increment(metricRequestCount, map[string]string{"endpoint": endpoint, "method": r.Method})

	// Extract repository NWO from URL parameters
	repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
	if err != nil {
		logger.WithError(err).Warn("invalid repository NWO")
		h.recordRequestCompletion(start, endpoint, http.StatusBadRequest, "failure")
		h.handleDomainError(w, err)
		return
	}

	logger = logger.WithFields(kvp.String("repo_nwo", repoNWO.String()))

	// Extract memory ID from URL parameters
	memoryIDParam := chi.URLParam(r, "memoryId")
	if memoryIDParam == "" {
		logger.Warn("memory ID is empty")
		h.recordRequestCompletion(start, endpoint, http.StatusBadRequest, "failure")
		http.Error(w, "memory ID cannot be empty", http.StatusBadRequest)
		return
	}
	memoryID := core.MemoryID(memoryIDParam)
	logger = logger.WithFields(kvp.String("memory_id", memoryIDParam))

	// Ensure user is authenticated and authorized for the particular repository.
	userInfo, repository, status, err := h.authorizeWithTelemetry(
		ctx,
		repoNWO,
		hasWritePermissions)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for delete memory")
		h.recordRequestCompletion(start, endpoint, status, "failure")
		http.Error(w, err.Error(), status)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	user := core.NewUser(userInfo.ID, userInfo.Login)

	// Delete the memory using the service
	err = h.service.DeleteMemory(ctx, user, repository, memoryID)
	if err != nil {
		logger.WithError(err).Warn("failed to delete memory")
		h.recordRequestCompletion(start, endpoint, h.errorToStatusCode(err), "failure")
		h.handleDomainError(w, err)
		return
	}

	logger.Info("memory deleted successfully")
	// Return 204 No Content on successful deletion
	w.WriteHeader(http.StatusNoContent)
	h.recordRequestCompletion(start, endpoint, http.StatusNoContent, "success")
}

// HandleDeleteAllMemories handles the deletion of all memories for a repository.
func (h *MemoryHandler) HandleDeleteAllMemories(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "MemoryHandler.HandleDeleteAllMemories")
	defer span.End()

	logger := h.obsv.LoggerWithTelemetry(ctx)
	start := time.Now()
	endpoint := "delete_all_memories"
	h.obsv.Statter.Increment(metricRequestCount, map[string]string{"endpoint": endpoint, "method": r.Method})

	// Extract repository NWO from URL parameters
	repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
	if err != nil {
		logger.WithError(err).Warn("invalid repository NWO")
		h.recordRequestCompletion(start, endpoint, http.StatusBadRequest, "failure")
		h.handleDomainError(w, err)
		return
	}

	logger = logger.WithFields(kvp.String("repo_nwo", repoNWO.String()))

	// Ensure user is authenticated and authorized for the particular repository.
	userInfo, repository, status, err := h.authorizeWithTelemetry(
		ctx,
		repoNWO,
		hasWritePermissions)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for delete all memories")
		h.recordRequestCompletion(start, endpoint, status, "failure")
		http.Error(w, err.Error(), status)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	user := core.NewUser(userInfo.ID, userInfo.Login)

	// Delete all memories using the service
	err = h.service.DeleteAllMemories(ctx, user, repository)
	if err != nil {
		logger.WithError(err).Warn("failed to delete all memories")
		h.recordRequestCompletion(start, endpoint, h.errorToStatusCode(err), "failure")
		h.handleDomainError(w, err)
		return
	}

	logger.Info("all memories deleted successfully")
	// Return 204 No Content on successful deletion
	w.WriteHeader(http.StatusNoContent)
	h.recordRequestCompletion(start, endpoint, http.StatusNoContent, "success")
}

// HandleCheckMemoryEnabled checks if the memory feature is enabled for the authenticated user.
func (h *MemoryHandler) HandleCheckMemoryEnabled(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "MemoryHandler.HandleCheckMemoryEnabled")
	defer span.End()

	logger := h.obsv.LoggerWithTelemetry(ctx)
	start := time.Now()
	endpoint := "check_memory_enabled"
	h.obsv.Statter.Increment(metricRequestCount, map[string]string{"endpoint": endpoint, "method": r.Method})

	// Extract repository NWO from URL parameters
	repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
	if err != nil {
		logger.WithError(err).Warn("invalid repository NWO")
		h.recordRequestCompletion(start, endpoint, http.StatusBadRequest, "failure")
		h.handleDomainError(w, err)
		return
	}

	logger = logger.WithFields(kvp.String("repo_nwo", repoNWO.String()))

	// Ensure user is authenticated and authorized for the particular repository.
	userInfo, _, status, err := h.authorizeWithTelemetry(
		ctx,
		repoNWO,
		hasReadPermission)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for check memory enabled")
		h.recordRequestCompletion(start, endpoint, status, "failure")
		http.Error(w, err.Error(), status)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	// Check if memory is enabled for the user
	enabled, err := h.service.CheckMemoryEnabled(ctx, int64(userInfo.ID))
	if err != nil {
		logger.WithError(err).Error("failed to check memory enablement")
		h.recordRequestCompletion(start, endpoint, http.StatusInternalServerError, "failure")
		h.obsv.Statter.Increment("MemoryHandler.HandleCheckMemoryEnabled.error", map[string]string{})
		http.Error(w, "Failed to check memory enablement", http.StatusInternalServerError)
		return
	}

	// Return the enablement status
	response := MemoryEnablementResponse{
		Enabled: enabled,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		logger.WithError(err).Error("failed to encode response")
		h.recordRequestCompletion(start, endpoint, http.StatusInternalServerError, "failure")
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	logger.WithFields(kvp.Bool("enabled", enabled)).Info("memory enablement check completed")
	h.recordRequestCompletion(start, endpoint, http.StatusOK, "success")
}

// handleDomainError resolves expected errors to their appropriate HTTP responses.
// If the error is not recognized, it returns a generic internal server error.
// The expected error codes are:
// - ErrEmptyRepoNWO - 400 Bad Request
// - ErrEmptyRepoOwner - 400 Bad Request
// - ErrEmptyRepoName - 400 Bad Request
// - ErrInvalidRepoNWO - 400 Bad Request
// - ErrNoMemoriesNotFound - 204 No Content
// - ErrRepositoryAccessDenied - 403 Forbidden
// - ErrRepositoryOAuthAccessRestriction - 403 Forbidden
// Other errors will return a 500 Internal Server Error.
func (h *MemoryHandler) handleDomainError(w http.ResponseWriter, err error) {
	errorName, message := h.errorToNameAndMessage(err)
	statusCode := h.errorToStatusCode(err)

	// Record telemetry for known errors
	if errorName != "" {
		h.obsv.Statter.Increment("MemoryHandler.handleDomainError", map[string]string{"error": errorName})
	}

	// Special case: ErrNoMemoriesNotFound returns 204 with no body
	if errors.Is(err, core.ErrNoMemoriesNotFound) {
		w.WriteHeader(http.StatusNoContent)
		return
	}

	// For unknown errors, use the error message directly
	if message == "" {
		message = err.Error()
	}

	http.Error(w, message, statusCode)
}

// errorToNameAndMessage maps domain errors to their telemetry names and user-facing messages.
func (h *MemoryHandler) errorToNameAndMessage(err error) (errorName, message string) {
	switch {
	case errors.Is(err, core.ErrEmptyRepoNWO):
		return "ErrEmptyRepoNWO", "repository NWO cannot be empty"
	case errors.Is(err, core.ErrEmptyRepoOwner):
		return "ErrEmptyRepoOwner", "repository owner cannot be empty"
	case errors.Is(err, core.ErrEmptyRepoName):
		return "ErrEmptyRepoName", "repository name cannot be empty"
	case errors.Is(err, core.ErrInvalidRepoNWO):
		return "ErrInvalidRepoNWO", "invalid repository NWO format"
	case errors.Is(err, core.ErrNoMemoriesNotFound):
		return "ErrNoMemoriesNotFound", ""
	case errors.Is(err, core.ErrFeatureNotEnabled):
		// Return 404 to avoid leaking information about the existence of the repository or user
		return "ErrFeatureNotEnabled", "Resource not found"
	case errors.Is(err, core.ErrMemoryContainsSecrets):
		return "ErrMemoryContainsSecrets", "Memory contains secrets and cannot be saved"
	case errors.Is(err, core.ErrMemoryNotFound):
		return "ErrMemoryNotFound", "Memory not found"
	case errors.Is(err, core.ErrRepositoryNotFound):
		return "ErrRepositoryNotFound", "Repository not found"
	case errors.Is(err, core.ErrRepositoryOAuthAccessRestriction):
		return "ErrRepositoryOAuthAccessRestriction", "Access to repository denied due to OAuth App access restrictions. An organization administrator must enable access for the app you're using. For more details, see <https://docs.github.com/organizations/managing-oauth-access-to-your-organizations-data/about-oauth-app-access-restrictions>."
	case errors.Is(err, core.ErrRepositoryAccessDenied):
		return "ErrRepositoryAccessDenied", "Access to repository denied"
	default:
		return "", ""
	}
}

// authorize checks if the user is authenticated and has the required permissions
// for the given repository NWO. It also fetches and returns the repository information,
// avoiding a separate API call later that might fail with different token authorization.
func (h *MemoryHandler) authorize(
	ctx context.Context,
	repoNWO *core.RepoNWO,
	hasRequiredPermissions func(repositoryPermissions github.RepositoryPermissions) bool,
) (*requestctx.UserInfo, *core.Repository, int, error) {
	logger := h.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("repo_nwo", repoNWO.String()),
	)

	// Extract user info from request context
	userInfo, ok := requestctx.User(ctx)
	if !ok || userInfo == nil {
		return userInfo, nil, http.StatusUnauthorized, goerrors.New("user information not found in request context")
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	// Get permissions and repository info using the same client
	permissions, repository, err := h.getRepositoryPermissionsAndInfo(ctx, *repoNWO, *userInfo)
	if err != nil {
		// Log the actual error for visibility before returning a generic 404
		logger.WithError(err).Info("authorization failed: error getting repository permissions/info")
		return userInfo, nil, http.StatusNotFound, goerrors.New(http.StatusText(http.StatusNotFound))
	}
	if !hasRequiredPermissions(permissions) {
		logger.Info("authorization failed: insufficient permissions")
		return userInfo, nil, http.StatusNotFound, goerrors.New(http.StatusText(http.StatusNotFound))
	}

	return userInfo, repository, http.StatusOK, nil
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
		h.obsv.Statter.Increment(metricUserTokenFallback, map[string]string{"outcome": "attempted"})

		gh = h.tryUserTokenFallback(userInfo)
		if gh == nil {
			logger.Warn("user token fallback failed: no user token available")
			h.obsv.Statter.Increment(metricUserTokenFallback, map[string]string{"outcome": "failed"})
			return github.RepositoryPermissions{}, nil, goerrors.Errorf("failed to create GitHub client: %w", err)
		}
		logger.Info("user token fallback succeeded")
		h.obsv.Statter.Increment(metricUserTokenFallback, map[string]string{"outcome": "succeeded"})
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

// authorizeWithTelemetry wraps authorize with duration tracking.
func (h *MemoryHandler) authorizeWithTelemetry(
	ctx context.Context,
	repoNWO *core.RepoNWO,
	hasRequiredPermissions func(repositoryPermissions github.RepositoryPermissions) bool,
) (*requestctx.UserInfo, *core.Repository, int, error) {
	start := time.Now()
	userInfo, repository, status, err := h.authorize(ctx, repoNWO, hasRequiredPermissions)
	h.obsv.Statter.DistributionMs(metricAuthorizeDuration, map[string]string{}, time.Since(start))
	return userInfo, repository, status, err
}

// recordRequestCompletion records telemetry for request completion including duration, status, and outcome.
func (h *MemoryHandler) recordRequestCompletion(start time.Time, endpoint string, statusCode int, outcome string) {
	duration := time.Since(start)
	tags := map[string]string{"endpoint": endpoint}

	// Record request duration
	h.obsv.Statter.DistributionMs(metricRequestDuration, tags, duration)

	// Record response status code
	h.obsv.Statter.Increment(metricResponseStatus, map[string]string{
		"endpoint":    endpoint,
		"status_code": strconv.Itoa(statusCode),
		"status_class": func() string {
			switch {
			case statusCode >= 200 && statusCode < 300:
				return "2xx"
			case statusCode >= 400 && statusCode < 500:
				return "4xx"
			case statusCode >= 500:
				return "5xx"
			default:
				return "other"
			}
		}(),
	})

	// Record request outcome (for temperature check / success rate calculation)
	h.obsv.Statter.Increment(metricRequestOutcome, map[string]string{
		"endpoint": endpoint,
		"outcome":  outcome,
	})
}

// errorToStatusCode maps domain errors to HTTP status codes for telemetry purposes.
func (h *MemoryHandler) errorToStatusCode(err error) int {
	switch {
	case errors.Is(err, core.ErrEmptyRepoNWO),
		errors.Is(err, core.ErrEmptyRepoOwner),
		errors.Is(err, core.ErrEmptyRepoName),
		errors.Is(err, core.ErrInvalidRepoNWO),
		errors.Is(err, core.ErrMemoryContainsSecrets):
		return http.StatusBadRequest
	case errors.Is(err, core.ErrNoMemoriesNotFound):
		return http.StatusNoContent
	case errors.Is(err, core.ErrFeatureNotEnabled),
		errors.Is(err, core.ErrMemoryNotFound),
		errors.Is(err, core.ErrRepositoryNotFound):
		return http.StatusNotFound
	case errors.Is(err, core.ErrRepositoryAccessDenied),
		errors.Is(err, core.ErrRepositoryOAuthAccessRestriction):
		return http.StatusForbidden
	default:
		return http.StatusInternalServerError
	}
}
