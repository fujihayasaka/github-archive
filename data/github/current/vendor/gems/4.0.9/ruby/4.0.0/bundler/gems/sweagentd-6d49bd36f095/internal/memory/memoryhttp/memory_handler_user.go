package memoryhttp

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"

	hydroSchemasv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
	memstdevents "github.com/github/sweagentd/internal/memory/standardevents"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
)

// authenticatedUser extracts the authenticated user from the request context.
// Returns an error when no user is present (defensive — upstream auth middleware
// normally rejects unauthenticated requests before handlers run).
func (h *MemoryHandler) authenticatedUser(ctx context.Context) (*requestctx.UserInfo, error) {
	userInfo, ok := requestctx.User(ctx)
	if !ok || userInfo == nil {
		return nil, goerrors.New("no authenticated user in context")
	}
	return userInfo, nil
}

// HandleCreateUserMemory handles the creation of a new user-scoped memory.
func (h *MemoryHandler) HandleCreateUserMemory(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, err := h.authenticatedUser(ctx)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for create user memory")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID), kvp.String("username", userInfo.Login))

	var memoryDTO MemoryDTO
	err = json.NewDecoder(r.Body).Decode(&memoryDTO)
	if err != nil {
		logger.WithError(err).Warn("failed to decode memory request body")
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	memory, err := memoryDTO.ToDomain(core.RepoNWO{}, *userInfo)
	if err != nil {
		logger.WithError(err).Warn("failed to convert memory DTO to domain")
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	memory.Scope = core.MemoryScopeUser
	user := core.NewUser(userInfo.ID, userInfo.Login)

	err = h.service.CreateUserMemory(ctx, memory, user)
	if err != nil {
		logger.WithError(err).Warn("failed to create user memory")
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
	logger.WithFields(kvp.String("memory_id", memory.ID.String())).Info("user memory created successfully")

	// Publish standard event for memory store (ExP experimentation only)
	h.expEventPublisher.PublishStore(ctx, memstdevents.StoreParams{
		UserInfo:      userInfo,
		Repository:    nil,
		AgentName:     memory.Source.Agent,
		InteractionID: memory.Source.InteractionID,
		ReqCtx:        memstdevents.ExtractRequestContext(r),
		StartTime:     requestctx.RequestStartedAtOrNow(ctx),
		Scope:         "user",
	})
}

// HandleGetRecentUserMemories handles requests to get the most recent N user-scoped memories.
func (h *MemoryHandler) HandleGetRecentUserMemories(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, err := h.authenticatedUser(ctx)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for get recent user memories")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	limit := parseLimitParam(r, 10, 1000)
	logger = logger.WithFields(kvp.Uint("limit", limit))

	user := core.NewUser(userInfo.ID, userInfo.Login)
	memories, err := h.service.GetRecentUserMemories(ctx, user, limit, core.UserMemoryQuery{})
	if err != nil {
		logger.WithError(err).Warn("failed to get recent user memories")
		h.handleDomainError(ctx, w, err)
		return
	}

	verbose := h.isVerboseRequest(ctx, r, userInfo.ID, logger)
	h.writeMemoriesResponse(ctx, w, logger, "get_recent_user_memories", memories, core.MemoryScopeUser, verbose)

	// Publish standard event for memory retrieval (ExP experimentation only)
	userMemCount := int64(len(memories))
	h.expEventPublisher.PublishRetrieval(ctx, memstdevents.RetrievalParams{
		UserInfo:        userInfo,
		Repository:      nil,
		ReqCtx:          memstdevents.ExtractRequestContext(r),
		StartTime:       requestctx.RequestStartedAtOrNow(ctx),
		Scope:           "user",
		UserMemoryCount: &userMemCount,
	})
}

// HandleGetTopUserMemories handles requests for the top-scored user-scoped memories.
func (h *MemoryHandler) HandleGetTopUserMemories(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, err := h.authenticatedUser(ctx)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for get top user memories")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	limit := parseLimitParam(r, 20, 1000)
	logger = logger.WithFields(kvp.Uint("limit", limit))

	user := core.NewUser(userInfo.ID, userInfo.Login)
	memories, err := h.service.GetTopUserMemories(ctx, user, limit, core.UserMemoryQuery{})
	if err != nil {
		logger.WithError(err).Warn("failed to get top user memories")
		h.handleDomainError(ctx, w, err)
		return
	}

	verbose := h.isVerboseRequest(ctx, r, userInfo.ID, logger)
	h.writeMemoriesResponse(ctx, w, logger, "get_top_user_memories", memories, core.MemoryScopeUser, verbose)

	// Publish standard event for memory retrieval (ExP experimentation only)
	userMemCount := int64(len(memories))
	h.expEventPublisher.PublishRetrieval(ctx, memstdevents.RetrievalParams{
		UserInfo:        userInfo,
		Repository:      nil,
		ReqCtx:          memstdevents.ExtractRequestContext(r),
		StartTime:       requestctx.RequestStartedAtOrNow(ctx),
		Scope:           "user",
		UserMemoryCount: &userMemCount,
	})
}

// HandleDeleteUserMemory handles the deletion of a specific user-scoped memory by ID.
func (h *MemoryHandler) HandleDeleteUserMemory(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, err := h.authenticatedUser(ctx)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for delete user memory")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	memoryIDParam := chi.URLParam(r, "memoryId")
	if memoryIDParam == "" {
		logger.Warn("memory ID is empty")
		http.Error(w, "memory ID cannot be empty", http.StatusBadRequest)
		return
	}
	memoryID := core.MemoryID(memoryIDParam)

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID), kvp.String("memory_id", memoryIDParam))

	user := core.NewUser(userInfo.ID, userInfo.Login)

	err = h.service.DeleteUserMemory(ctx, user, memoryID)
	if err != nil {
		logger.WithError(err).Warn("failed to delete user memory")
		h.handleDomainError(ctx, w, err)
		return
	}
	h.publishUserMemoryDeleteTelemetry(ctx, "delete_single", userInfo, string(memoryID))
	// Publish StandardEvent for ExP experimentation only
	h.expEventPublisher.PublishDelete(ctx, memstdevents.DeleteParams{
		UserInfo:   userInfo,
		Repository: nil,
		ReqCtx:     memstdevents.ExtractRequestContext(r),
		StartTime:  requestctx.RequestStartedAtOrNow(ctx),
		Operation:  "delete_single",
		MemoryID:   string(memoryID),
	})

	logger.Info("user memory deleted successfully")
	w.WriteHeader(http.StatusNoContent)
}

// HandleDeleteUserMemories handles the deletion of multiple user-scoped memories by their IDs.
func (h *MemoryHandler) HandleDeleteUserMemories(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, err := h.authenticatedUser(ctx)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for delete user memories")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

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

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	user := core.NewUser(userInfo.ID, userInfo.Login)

	memoryIDs := make([]core.MemoryID, len(req.IDs))
	for i, id := range req.IDs {
		memoryIDs[i] = core.MemoryID(id)
	}

	result, err := h.service.DeleteUserMemories(ctx, user, memoryIDs)
	if err != nil {
		logger.WithError(err).Warn("failed to delete user memories")
		if result != nil && len(result.Deleted) > 0 {
			h.publishUserMemoryDeleteTelemetry(ctx, "delete_batch", userInfo, "")
			h.expEventPublisher.PublishDelete(ctx, memstdevents.DeleteParams{
				UserInfo:   userInfo,
				Repository: nil,
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
	h.publishUserMemoryDeleteTelemetry(ctx, "delete_batch", userInfo, "")
	h.expEventPublisher.PublishDelete(ctx, memstdevents.DeleteParams{
		UserInfo:   userInfo,
		Repository: nil,
		ReqCtx:     memstdevents.ExtractRequestContext(r),
		StartTime:  requestctx.RequestStartedAtOrNow(ctx),
		Operation:  "delete_batch",
	})

	logger.WithFields(kvp.Int("deleted_count", len(result.Deleted))).Info("user memories deleted successfully")
	h.writeBatchDeleteResponse(ctx, w, result)
}

// HandleDeleteAllUserMemories handles the deletion of all memories for a user.
func (h *MemoryHandler) HandleDeleteAllUserMemories(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, err := h.authenticatedUser(ctx)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for delete all user memories")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	user := core.NewUser(userInfo.ID, userInfo.Login)

	err = h.service.DeleteAllUserMemories(ctx, user)
	if err != nil {
		logger.WithError(err).Warn("failed to delete all user memories")
		h.handleDomainError(ctx, w, err)
		return
	}
	h.publishUserMemoryDeleteTelemetry(ctx, "delete_all", userInfo, "")
	h.expEventPublisher.PublishDelete(ctx, memstdevents.DeleteParams{
		UserInfo:   userInfo,
		Repository: nil,
		ReqCtx:     memstdevents.ExtractRequestContext(r),
		StartTime:  requestctx.RequestStartedAtOrNow(ctx),
		Operation:  "delete_all",
	})

	logger.Info("all user memories deleted successfully")
	w.WriteHeader(http.StatusNoContent)
}

// HandleCheckUserMemoryEnabled checks if user-scoped memory is enabled for the authenticated user.
func (h *MemoryHandler) HandleCheckUserMemoryEnabled(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, err := h.authenticatedUser(ctx)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for check user memory enabled")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	enabled, err := h.service.CheckUserMemoryEnabled(ctx, int64(userInfo.ID))
	if err != nil {
		logger.WithError(err).Error("failed to check user memory enablement")
		h.reportException(ctx, err)
		http.Error(w, "Failed to check memory enablement", http.StatusInternalServerError)
		return
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
	logger.WithFields(kvp.Bool("enabled", enabled)).Info("user memory enablement check completed")
}

// HandleVoteUserMemory handles voting on a user-scoped memory identified by its fact text.
func (h *MemoryHandler) HandleVoteUserMemory(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger := h.requestLogger(ctx)

	userInfo, err := h.authenticatedUser(ctx)
	if err != nil {
		logger.WithError(err).Warn("authorization failed for vote user memory")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

	// Decode request body
	var voteRequest VoteRequest
	err = json.NewDecoder(r.Body).Decode(&voteRequest)
	if err != nil {
		logger.WithError(err).Warn("failed to decode vote request body")
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	user := core.NewUser(userInfo.ID, userInfo.Login)

	vote, err := voteRequest.ToDomain(userInfo, nil)
	if err != nil {
		logger.WithError(err).Warn("invalid vote request")
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	err = h.service.VoteOnUserMemory(ctx, user, voteRequest.Fact, vote)
	if err != nil {
		logger.WithError(err).Warn("failed to vote on user memory")
		h.handleDomainError(ctx, w, err)
		return
	}

	logger.Info("user memory vote recorded successfully")
	w.WriteHeader(http.StatusNoContent)

	// Publish standard event for memory vote (ExP experimentation only)
	h.expEventPublisher.PublishVote(ctx, memstdevents.VoteParams{
		UserInfo:      userInfo,
		Repository:    nil,
		AgentName:     voteRequest.Agent,
		InteractionID: voteRequest.InteractionID,
		Direction:     voteRequest.Direction,
		ReqCtx:        memstdevents.ExtractRequestContext(r),
		StartTime:     requestctx.RequestStartedAtOrNow(ctx),
		Scope:         "user",
	})
}

// publishUserMemoryDeleteTelemetry publishes a telemetry event when user-scoped memories are deleted.
func (h *MemoryHandler) publishUserMemoryDeleteTelemetry(ctx context.Context, operation string, userInfo *requestctx.UserInfo, memoryID string) {
	properties := map[string]string{
		"operation":   operation,
		"scope":       "user",
		"actor_id":    strconv.FormatUint(userInfo.ID, 10),
		"actor_login": userInfo.Login,
	}
	if memoryID != "" {
		properties["memory_id"] = memoryID
	}

	err := h.obsv.HydroPbl.Publish(&hydroSchemasv0.Telemetry{
		Kind:       "memory_deleted",
		CreatedAt:  timestamppb.Now(),
		Properties: properties,
	})
	if err != nil {
		h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish user memory deletion telemetry")
	}
}
