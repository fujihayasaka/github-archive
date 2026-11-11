// Package pluginshttp provides HTTP handlers for the plugins API.
package pluginshttp

import (
	"context"
	"fmt"
	"net/http"
	"time"

	authd "github.com/github/authnd/client"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/api"
	"github.com/github/sweagentd/internal/auth"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
)

type handlerRoute func(userInfo *requestctx.UserInfo, baseTags stats.Tags) http.HandlerFunc

func (h *Handler) middleware(route handlerRoute) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		ctx, span := h.obsv.Tracer.Start(r.Context(), "plugins.Handler.middleware")
		defer span.End()
		r = r.WithContext(ctx)

		rw := api.NewResponseWrapper(w)
		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r).Named("plugins.Handler.middleware")
		logger.Info("plugins request started")

		baseTags := h.obsv.TelemetryTags(ctx)
		h.obsv.Increment(ctx, "plugins.Handler.requests", baseTags)

		defer func() {
			duration := time.Since(start)
			logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
			logKvps := []kvp.Field{
				kvp.Int64("duration_ms", duration.Milliseconds()),
				kvp.Int("http.status_code", rw.StatusCode),
			}
			if rw.ErrMsg != "" {
				logKvps = append(logKvps, kvp.String("exception.message", rw.ErrMsg))
			}
			logger.WithFields(logKvps...).Info("plugins request completed")
		}()

		userInfo, ok := requestctx.User(ctx)
		if !ok || userInfo == nil {
			logger.WithContext(ctx).Info("user info not found in context")
			http.Error(rw, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

			return
		}

		if !h.ffs.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentPluginsListAPIEnabled, int64(userInfo.ID)) {
			logger.WithContext(ctx).Info("plugins feature flag not enabled for user")
			http.Error(rw, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}

		repoOwner := chi.URLParam(r, "repoOwner")
		repoName := chi.URLParam(r, "repoName")
		if repoOwner == "" || repoName == "" {
			logger.WithContext(ctx).Info("repository owner and name cannot be empty")
			http.Error(rw, "repository owner and name cannot be empty", http.StatusBadRequest)

			return
		}

		if authd.CredentialType(userInfo.TokenInfo.Type) == authd.CredentialTypeSSHCertificate {
			logger.WithContext(ctx).Info("unsupported token type")
			http.Error(rw, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

			return
		}

		// Verify token has access to repo
		hasAccess, err := h.verifyTokenAccess(ctx, userInfo, repoOwner, repoName)
		if err != nil {
			logger.WithContext(ctx).WithError(err).Info("failed to check token access")
			http.Error(rw, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

			return
		}
		if !hasAccess {
			logger.WithContext(ctx).Info("token does not have access to repository")
			http.Error(rw, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}

		route(userInfo, baseTags)(rw, r)
	}
}

func (h *Handler) verifyTokenAccess(ctx context.Context, user *requestctx.UserInfo, repoOwner, repoName string) (bool, error) {
	logger := h.obsv.LoggerWithTelemetry(ctx).Named("plugins.Handler.verifyTokenAccess")

	tokenHash := auth.HashToken(user.TokenInfo.Token)

	logger.WithFields(
		kvp.String("repo_owner", repoOwner),
		kvp.String("repo_name", repoName),
		kvp.String("token_hash", tokenHash),
	).Info("verifying token has read access to repo")

	nwo := fmt.Sprintf("%s/%s", repoOwner, repoName)
	rule := &githubtwirp.HasAccessCheck{
		Action:        "pull",
		ResourceType:  "Repository",
		RepositoryNWO: nwo,
	}
	hasAccess, err := h.ghTwirp.TokenHasAccess(ctx, user, []*githubtwirp.HasAccessCheck{rule})
	if err != nil {
		logger.WithFields(
			kvp.Bool("has_access", hasAccess),
			kvp.String("token_hash", tokenHash),
		).Info("failed to check token access")
		return false, err
	}
	logger.WithFields(
		kvp.Bool("has_access", hasAccess),
		kvp.String("token_hash", tokenHash),
	).Info("token access check completed")
	return hasAccess, nil
}
