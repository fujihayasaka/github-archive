package memoryhttp

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"

	hydroSchemasv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
)

// staffVerboseHeader is the HTTP header a caller sends to request verbose
// (staff-only) memory responses.
const staffVerboseHeader = "X-GitHub-Staff"

// writeBatchDeleteResponse encodes and writes a batch delete result as JSON.
func (h *MemoryHandler) writeBatchDeleteResponse(ctx context.Context, w http.ResponseWriter, result *core.BatchDeleteResult) {
	deleted := make([]string, len(result.Deleted))
	for i, id := range result.Deleted {
		deleted[i] = string(id)
	}
	failed := make([]string, len(result.Failed))
	for i, id := range result.Failed {
		failed[i] = string(id)
	}

	resp := BatchDeleteResponse{
		Deleted: deleted,
		Failed:  failed,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	err := json.NewEncoder(w).Encode(resp)
	if err != nil {
		h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to encode batch delete response")
	}
}

// publishHydroDeleteTelemetry publishes a Hydro telemetry event when memories are deleted.
// This function is responsible for tracking memory deletion operations for observability and analytics.
// NOTE: This is regular Hydro telemetry for operational tracking, NOT StandardEvents for ExP.
//
// Parameters:
//   - ctx: Request context for logger association
//   - operation: Type of deletion operation ("delete_single" for individual memory or "delete_all" for bulk deletion)
//   - repoNWO: Repository name with owner (owner/repo)
//   - userInfo: Information about the user performing the deletion
//   - memoryID: ID of the specific memory being deleted (empty string for bulk deletions)
//
// The function constructs a Hydro telemetry event with the deletion context and publishes it
// to the observability system. If publishing fails, the error is logged but does not propagate,
// ensuring deletion operations are not blocked by telemetry failures.
func (h *MemoryHandler) publishHydroDeleteTelemetry(ctx context.Context, operation string, repoNWO *core.RepoNWO, userInfo *requestctx.UserInfo, memoryID string) {
	properties := map[string]string{
		"operation":   operation,
		"repo_owner":  repoNWO.Owner,
		"repo_name":   repoNWO.Repo,
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
		h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish memory deletion telemetry")
	}
}

// isVerboseRequest returns true when the request carries the X-GitHub-Staff: true
// header AND the caller is a verified staff user. Non-staff callers that send the
// header silently receive the normal (non-verbose) response — no error is returned.
// In development mode, the header alone is sufficient (staff check is skipped).
func (h *MemoryHandler) isVerboseRequest(ctx context.Context, r *http.Request, userID uint64, logger log.Logger) bool {
	if r.Header.Get(staffVerboseHeader) != "true" {
		return false
	}
	if h.isDevelopment {
		return true
	}
	return h.isStaffUser(ctx, int64(userID), logger)
}

// writeMemoriesResponse converts memories to DTOs and writes them as a JSON response.
// Scope is now persisted in Cosmos DB, but we still stamp it here as a backward-compatibility
// fallback for documents written before scope was persisted.
// When verbose is true, VerboseMemoryDTOs (with score, votes, timestamps, etc.) are returned.
func (h *MemoryHandler) writeMemoriesResponse(ctx context.Context, w http.ResponseWriter, logger log.Logger, endpoint string, memories []*core.Memory, scope core.MemoryScope, verbose bool) {
	for _, memory := range memories {
		if memory.Scope == "" {
			memory.Scope = scope
		}
	}

	var payload any
	if verbose {
		dtos := make([]*VerboseMemoryDTO, len(memories))
		for i, memory := range memories {
			dtos[i] = VerboseFromDomain(memory)
		}
		payload = dtos
	} else {
		dtos := make([]*MemoryDTO, len(memories))
		for i, memory := range memories {
			dtos[i] = FromDomain(memory)
		}
		payload = dtos
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	err := json.NewEncoder(w).Encode(payload)
	if err != nil {
		logger.WithError(err).Error("failed to encode response")
		h.reportException(ctx, err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	logger.WithFields(kvp.Int("memories_count", len(memories))).Info(endpoint + " completed")
}

// parseLimitParam extracts a "limit" query parameter from the request,
// falling back to defaultLimit and capping at maxLimit.
func parseLimitParam(r *http.Request, defaultLimit, maxLimit uint) uint {
	limit := defaultLimit
	if limitParam := r.URL.Query().Get("limit"); limitParam != "" {
		parsedLimit, parseErr := strconv.Atoi(limitParam)
		if parseErr == nil && parsedLimit > 0 {
			limit = uint(parsedLimit)
		}
	}
	if limit > maxLimit {
		limit = maxLimit
	}
	return limit
}

// applyMemoryLimitExperiment checks for an active CCA memory limit experiment assignment
// and returns the experiment limit if present, otherwise returns the provided default limit.
// It also logs and emits metrics when the experiment is active.
func (h *MemoryHandler) applyMemoryLimitExperiment(ctx context.Context, defaultLimit uint, logger log.Logger) uint {
	assignment := exp.AssignmentFromContext(ctx)
	flagKey := exp.FlagKey(exp.CCAMemoryLimitExperiment)

	// Use GetString to check if the flag is actually present in the assignment,
	// not just that *some* experiment is active (assignment context could be for a
	// different experiment).
	rawVal := assignment.GetString(flagKey, "")
	if rawVal == "" {
		return defaultLimit
	}

	expLimit := assignment.GetInt(flagKey, int(defaultLimit))
	if expLimit < 0 {
		logger.Warn("invalid negative memory limit from experiment, using default",
			kvp.Int("experiment_limit", expLimit),
			kvp.Int("default_limit", int(defaultLimit)),
		)
		return defaultLimit
	}

	limit := uint(expLimit)
	h.obsv.Increment(ctx, "memory.limit_experiment", memoryRequestMetricTags(ctx, map[string]string{
		"memory_limit": strconv.FormatUint(uint64(limit), 10),
	}))

	return limit
}
