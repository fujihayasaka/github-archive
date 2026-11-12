package http

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
)

// MemoryHandler handles HTTP requests for memory operations.
type MemoryHandler struct {
	service   core.MemoryService
	ghFactory github.ClientFactoryInterface
	obsv      observability.Exporters
}

// NewMemoryHandler creates a new MemoryHandler instance.
func NewMemoryHandler(service core.MemoryService, ghFactory github.ClientFactoryInterface, obsv observability.Exporters) *MemoryHandler {
	return &MemoryHandler{
		service:   service,
		ghFactory: ghFactory,
		obsv:      obsv,
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
	})
}

// handleDomainError resolves expected errors to their appropriate HTTP responses.
// If the error is not recognized, it returns a generic internal server error.
// The expected error codes are:
// - ErrEmptyRepoNWO - 400 Bad Request
// - ErrEmptyRepoOwner - 400 Bad Request
// - ErrEmptyRepoName - 400 Bad Request
// - ErrInvalidRepoNWO - 400 Bad Request
// - ErrNoMemoriesNotFound - 204 No Content
// Other errors will return a 500 Internal Server Error.
func (h *MemoryHandler) handleDomainError(w http.ResponseWriter, err error) {
	if errors.Is(err, core.ErrEmptyRepoNWO) {
		h.obsv.Statter.Increment("MemoryHandler.handleDomainError", map[string]string{"error": "ErrEmptyRepoNWO"})
		http.Error(w, "repository NWO cannot be empty", http.StatusBadRequest)
		return
	}
	if errors.Is(err, core.ErrEmptyRepoOwner) {
		h.obsv.Statter.Increment("MemoryHandler.handleDomainError", map[string]string{"error": "ErrEmptyRepoOwner"})
		http.Error(w, "repository owner cannot be empty", http.StatusBadRequest)
		return
	}
	if errors.Is(err, core.ErrEmptyRepoName) {
		h.obsv.Statter.Increment("MemoryHandler.handleDomainError", map[string]string{"error": "ErrEmptyRepoName"})
		http.Error(w, "repository name cannot be empty", http.StatusBadRequest)
		return
	}
	if errors.Is(err, core.ErrInvalidRepoNWO) {
		h.obsv.Statter.Increment("MemoryHandler.handleDomainError", map[string]string{"error": "ErrInvalidRepoNWO"})
		http.Error(w, "invalid repository NWO format", http.StatusBadRequest)
		return
	}
	if errors.Is(err, core.ErrNoMemoriesNotFound) {
		h.obsv.Statter.Increment("MemoryHandler.handleDomainError", map[string]string{"error": "ErrNoMemoriesNotFound"})
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if errors.Is(err, core.ErrFeatureNotEnabled) {
		h.obsv.Statter.Increment("MemoryHandler.handleDomainError", map[string]string{"error": "ErrFeatureNotEnabled"})
		// If the feature is not enabled for the user or repository, return a 404 Not Found
		// This is to avoid leaking information about the existence of the repository or user
		http.Error(w, "Resource not found", http.StatusNotFound)
		return
	}
	if errors.Is(err, core.ErrMemoryContainsSecrets) {
		// If the memory contains secrets, return a 400 Bad Request
		http.Error(w, "Memory contains secrets and cannot be saved", http.StatusBadRequest)
		return
	}
	if errors.Is(err, core.ErrMemoryNotFound) {
		h.obsv.Statter.Increment("MemoryHandler.handleDomainError", map[string]string{"error": "ErrMemoryNotFound"})
		http.Error(w, "Memory not found", http.StatusNotFound)
		return
	}

	http.Error(w, err.Error(), http.StatusInternalServerError)
}

// HandleCreateMemory handles the creation of a new memory.
func (h *MemoryHandler) HandleCreateMemory(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "MemoryHandler.HandleCreateMemory")
	defer span.End()
	// Extract repository NWO from URL parameters
	repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
	if err != nil {
		h.handleDomainError(w, err)
		return
	}

	// Ensure user is authenticated and authorized for the particular repository.
	userInfo, status, err := h.authorize(
		ctx,
		repoNWO,
		func(permissions github.RepositoryPermissions) bool {
			return permissions.Push
		})
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}

	// Decode the MemoryDTO from request body
	var memoryDTO MemoryDTO
	if err := json.NewDecoder(r.Body).Decode(&memoryDTO); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Convert DTO to domain object
	memory := memoryDTO.ToDomain(*repoNWO, *userInfo)

	// Create the memory using the service
	if err := h.service.CreateMemory(ctx, memory); err != nil {
		h.handleDomainError(w, err)
		return
	}

	// Return the created memory as DTO
	responseDTO := FromDomain(memory)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	if err := json.NewEncoder(w).Encode(responseDTO); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
}

// HandleSearchMemories handles memory search requests.
func (h *MemoryHandler) HandleSearchMemories(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "MemoryHandler.HandleSearchMemories")
	defer span.End()

	// Extract repository NWO from URL parameters
	repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
	if err != nil {
		h.handleDomainError(w, err)
		return
	}

	// Ensure user is authenticated and authorized for the particular repository.
	userInfo, status, err := h.authorize(
		ctx,
		repoNWO,
		func(permissions github.RepositoryPermissions) bool {
			return permissions.Pull
		})
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}

	// Decode the search request from request body
	var searchRequest MemorySearchRequest
	if err := json.NewDecoder(r.Body).Decode(&searchRequest); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	user := core.NewUser(userInfo.ID, userInfo.Login)
	// For now, we'll get all memories and filter by question in the future
	// Search for memories using the question parameter
	memories, err := h.service.GetMemories(ctx, user, *repoNWO)
	if err != nil {
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
	if err := json.NewEncoder(w).Encode(memoryDTOs); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
}

// HandleGetRecentMemories handles requests to get the most recent N memories.
func (h *MemoryHandler) HandleGetRecentMemories(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "MemoryHandler.HandleGetRecentMemories")
	defer span.End()

	// Extract repository NWO from URL parameters
	repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
	if err != nil {
		h.handleDomainError(w, err)
		return
	}

	// Ensure user is authenticated and authorized for the particular repository.
	userInfo, status, err := h.authorize(
		ctx,
		repoNWO,
		func(permissions github.RepositoryPermissions) bool {
			return permissions.Pull
		})
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}

	// Parse limit from query parameter, default to 10
	limit := uint(10)
	if limitParam := r.URL.Query().Get("limit"); limitParam != "" {
		if parsedLimit, err := strconv.Atoi(limitParam); err == nil && parsedLimit > 0 {
			limit = uint(parsedLimit)
		}
	}

	user := core.NewUser(userInfo.ID, userInfo.Login)
	// Get recent memories using the service
	memories, err := h.service.GetRecentMemories(ctx, user, *repoNWO, limit)
	if err != nil {
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
	if err := json.NewEncoder(w).Encode(memoryDTOs); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
}

// HandleDeleteMemory handles the deletion of a specific memory by ID.
func (h *MemoryHandler) HandleDeleteMemory(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "MemoryHandler.HandleDeleteMemory")
	defer span.End()

	// Extract repository NWO from URL parameters
	repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
	if err != nil {
		h.handleDomainError(w, err)
		return
	}

	// Extract memory ID from URL parameters
	memoryIDParam := chi.URLParam(r, "memoryId")
	if memoryIDParam == "" {
		http.Error(w, "memory ID cannot be empty", http.StatusBadRequest)
		return
	}
	memoryID := core.MemoryID(memoryIDParam)

	// Ensure user is authenticated and authorized for the particular repository.
	userInfo, status, err := h.authorize(
		ctx,
		repoNWO,
		func(permissions github.RepositoryPermissions) bool {
			return permissions.Push
		})
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}

	user := core.NewUser(userInfo.ID, userInfo.Login)

	// Delete the memory using the service
	if err := h.service.DeleteMemory(ctx, user, *repoNWO, memoryID); err != nil {
		h.handleDomainError(w, err)
		return
	}

	// Return 204 No Content on successful deletion
	w.WriteHeader(http.StatusNoContent)
}

// HandleDeleteAllMemories handles the deletion of all memories for a repository.
func (h *MemoryHandler) HandleDeleteAllMemories(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "MemoryHandler.HandleDeleteAllMemories")
	defer span.End()

	// Extract repository NWO from URL parameters
	repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
	if err != nil {
		h.handleDomainError(w, err)
		return
	}

	// Ensure user is authenticated and authorized for the particular repository.
	userInfo, status, err := h.authorize(
		ctx,
		repoNWO,
		func(permissions github.RepositoryPermissions) bool {
			return permissions.Push
		})
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}

	user := core.NewUser(userInfo.ID, userInfo.Login)

	// Delete all memories using the service
	if err := h.service.DeleteAllMemories(ctx, user, *repoNWO); err != nil {
		h.handleDomainError(w, err)
		return
	}

	// Return 204 No Content on successful deletion
	w.WriteHeader(http.StatusNoContent)
}

func (h *MemoryHandler) authorize(
	ctx context.Context,
	repoNWO *core.RepoNWO,
	checkRepoPermissions func(repositoryPermissions github.RepositoryPermissions) bool) (*requestctx.UserInfo, int, error) {

	// Extract user info from request context
	userInfo, ok := requestctx.User(ctx)
	if !ok || userInfo == nil {
		return userInfo, http.StatusUnauthorized, fmt.Errorf("user information not found in request context")
	}

	// Ensure that the user can push to the given repository. We'll interpret
	// this to mean "can write memories for this repo" until we add fine-grained permissions
	// for memory.
	//
	// On failure, return 404 to avoid leaking the existence of a particular repository.
	permissions, err := h.getRepositoryPermissions(ctx, *repoNWO, *userInfo)
	if err != nil || !checkRepoPermissions(permissions) {
		return userInfo, http.StatusNotFound, errors.New(http.StatusText(http.StatusNotFound))
	}

	return userInfo, http.StatusOK, nil
}

func (h *MemoryHandler) getRepositoryPermissions(
	ctx context.Context,
	repoNWO core.RepoNWO,
	userInfo requestctx.UserInfo) (github.RepositoryPermissions, error) {

	gh, err := h.ghFactory.NewClientFromRepoName(ctx, repoNWO.Repo, repoNWO.Owner)
	if err != nil {
		return github.RepositoryPermissions{}, fmt.Errorf("failed to create GitHub client: %w", err)
	}

	// Only process events where the actor has write access to the repo
	repositoryPermissions, err := gh.GetUserPermissionsForRepository(ctx, repoNWO.Owner, repoNWO.Repo, userInfo.Login)
	if err != nil || repositoryPermissions == nil {
		return github.RepositoryPermissions{}, fmt.Errorf("failed to get repository permissions: %w", err)
	}

	return *repositoryPermissions, nil
}
