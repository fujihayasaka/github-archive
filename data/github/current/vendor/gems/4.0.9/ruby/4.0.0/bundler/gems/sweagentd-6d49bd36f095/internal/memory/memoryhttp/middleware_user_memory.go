package memoryhttp

import (
	"net/http"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
)

// withUserMemoryCheck enforces the user-affecting layers of the memory
// enablement chain on user-scoped routes: Policy via Monolith Twirp plus
// the user-keyed feature flags (memory enabled, memory disabled,
// user-scoped memory, and any per-integration override flag).
//
// Per the memory opt-out matrix agreed in github/agents#945, user-scoped
// routes are intentionally not gated by the repo-admin opt-out
// (repo_memory_disabled): user memories follow the user across repos by
// design and the repo-admin setting only affects repo memories.
//
// If memory is disabled for the user, the request is rejected with
// ErrFeatureNotEnabled (404). Service-level errors during the chain are
// treated as 500s because they are usually retryable infra issues; this
// matches withRepoMemoryCheck.
//
// The /memory/v0/user/enabled endpoint must NOT be wrapped with this
// middleware: clients call /enabled to query the chain result and expect a
// 200 with {"enabled": false} rather than a 404. The handler consults the
// same chain internally so the answer remains consistent.
//
// Defence in depth: validateUserAccess inside memory_service remains in
// place. Non-HTTP callers (other transports, batch jobs, direct tests) go
// through the service directly and bypass this middleware; the service
// layer enforcement closes that gap.
func (h *MemoryHandler) withUserMemoryCheck() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctx := r.Context()
			logger := h.requestLogger(ctx)

			userInfo, ok := requestctx.User(ctx)
			if !ok || userInfo == nil {
				logger.Warn("unauthenticated request to user-scoped memory route")
				http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
				return
			}
			logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

			enabled, err := h.service.CheckUserMemoryEnabled(ctx, int64(userInfo.ID))
			if err != nil {
				logger.WithError(err).Error("failed to evaluate user-scope memory enablement chain")
				h.reportException(ctx, err)
				http.Error(w, "Failed to check memory enablement", http.StatusInternalServerError)
				return
			}
			if !enabled {
				logger.Info("memory disabled for user by user-scope chain")
				h.obsv.Increment(ctx, "MemoryHandler.withUserMemoryCheck.user_disabled", memoryRequestMetricTags(ctx, nil))
				h.handleDomainError(ctx, w, core.ErrFeatureNotEnabled)
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
