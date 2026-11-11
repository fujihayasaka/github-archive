package memoryhttp

import (
	"context"
	"net/http"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
)

// repoAuthCtxKey is the context key for the userInfo/repository pair resolved
// by withRepoMemoryCheck so downstream handlers can avoid re-authorising.
type repoAuthCtxKey struct{}

// repoAuth holds the resolved userInfo and repository for a request that has
// passed the withRepoMemoryCheck middleware.
type repoAuth struct {
	userInfo   *requestctx.UserInfo
	repository *core.Repository
	repoNWO    *core.RepoNWO
}

// repoAuthFromCtx retrieves the userInfo, repository, and repoNWO resolved by
// withRepoMemoryCheck. Returns ok=false when the middleware did not run for
// this request (defensive: handlers wrapped by the middleware should always
// see ok=true).
func repoAuthFromCtx(ctx context.Context) (userInfo *requestctx.UserInfo, repository *core.Repository, repoNWO *core.RepoNWO, ok bool) {
	val, ok := ctx.Value(repoAuthCtxKey{}).(*repoAuth)
	if !ok || val == nil {
		return nil, nil, nil, false
	}
	return val.userInfo, val.repository, val.repoNWO, true
}

// withRepoAuth stores the resolved userInfo, repository, and repoNWO in ctx
// so that downstream handlers can read them without re-authorising.
func withRepoAuth(ctx context.Context, userInfo *requestctx.UserInfo, repository *core.Repository, repoNWO *core.RepoNWO) context.Context {
	return context.WithValue(ctx, repoAuthCtxKey{}, &repoAuth{
		userInfo:   userInfo,
		repository: repository,
		repoNWO:    repoNWO,
	})
}

// withRepoMemoryCheck authorises the request at the given permission level and
// runs the consolidated memory enablement chain. If memory is disabled at any
// level (user kill switch, Policy via Monolith Twirp, repo/owner feature flag,
// or repo admin setting), the request is rejected with ErrFeatureNotEnabled
// (404). Successful requests have userInfo, repository, and repoNWO stashed in
// ctx for downstream handlers via repoAuthFromCtx.
//
// The repo-admin Twirp error fail mode is per-permission: write routes set
// perm.failClosedOnRepoAdminError so a Dotcom blip returns 500 rather than
// silently allowing writes to a possibly-opted-out repo; read routes keep
// the lower-blast-radius fail-open default.
//
// The /enabled endpoint must NOT be wrapped with this middleware: clients call
// /enabled to query the chain result and expect a 200 with {"enabled": false}
// rather than a 404.
func (h *MemoryHandler) withRepoMemoryCheck(perm permissionCheck) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctx := r.Context()
			logger := h.requestLogger(ctx)

			repoNWO, err := core.NewRepoNWO(chi.URLParam(r, "owner"), chi.URLParam(r, "repo"))
			if err != nil {
				logger.WithError(err).Warn("invalid repository NWO")
				h.handleDomainError(ctx, w, err)
				return
			}
			logger = logger.WithFields(kvp.String("repo_nwo", repoNWO.String()))

			// Fast-path user-level kill switch — avoids GitHub API call for
			// users who have memory disabled at the user level.
			if h.checkUserLevelMemoryDisabled(ctx) {
				logger.Info("memory disabled at user level (kill switch)")
				h.obsv.Increment(ctx, "MemoryHandler.withRepoMemoryCheck.user_disabled", memoryRequestMetricTags(ctx, nil))
				h.handleDomainError(ctx, w, core.ErrFeatureNotEnabled)
				return
			}

			// Authorize, with experiment assignment for CCA so downstream code
			// can read the assignment via exp.AssignmentFromContext (parity
			// with the previous handler-level authorizeAndAssign path).
			isCCARequest := featureflags.IntegrationIDFromContext(ctx) == copilotDeveloperIntegrationID
			var (
				userInfo   *requestctx.UserInfo
				repository *core.Repository
				status     int
			)
			if isCCARequest {
				ctx, userInfo, repository, status, err = h.authorizeAndAssign(ctx, repoNWO, perm)
			} else {
				userInfo, repository, status, err = h.authorizeWithTelemetry(ctx, repoNWO, perm)
			}
			if err != nil {
				logger.WithError(err).Warn("authorization failed in withRepoMemoryCheck")
				http.Error(w, err.Error(), status)
				return
			}
			logger = logger.WithFields(kvp.Uint64("user_id", userInfo.ID))

			disabled, chainErr := h.isMemoryDisabledForRepo(ctx, userInfo, repository, perm.failClosedOnRepoAdminError)
			if chainErr != nil {
				// Treat upstream errors during the chain as 500s; service-layer
				// errors are usually retryable infra issues.
				logger.WithError(chainErr).Error("failed to evaluate memory enablement chain")
				h.reportException(ctx, chainErr)
				http.Error(w, "Failed to check memory enablement", http.StatusInternalServerError)
				return
			}
			if disabled {
				logger.Info("memory disabled for repo by chain")
				h.handleDomainError(ctx, w, core.ErrFeatureNotEnabled)
				return
			}

			ctx = withRepoAuth(ctx, userInfo, repository, repoNWO)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
