package skillshttp

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
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
)

type handlerRoute func(userInfo *requestctx.UserInfo, baseTags stats.Tags) http.HandlerFunc

// middleware wraps handlers with auth, repo access verification, and observability.
func (h *Handler) middleware(route handlerRoute, endpointName string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		ctx, span := h.obsv.Tracer.Start(r.Context(), "skills.Handler.middleware")
		defer span.End()
		r = r.WithContext(ctx)

		// Wrap the response writer to capture status code and error message
		rw := api.NewResponseWrapper(w)
		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r).Named("skills.Handler.middleware")
		logger.Info("skills request started")

		// Base telemetry tags for this request
		baseTags := h.obsv.TelemetryTags(ctx).Merge(stats.Tags{
			"endpoint": endpointName,
		})
		h.obsv.Increment(ctx, "skills.Handler.requests", baseTags)

		// Emit a single log event at the end of the request
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
			logger.WithFields(logKvps...).Info("skills request completed")
		}()

		repoOwner := chi.URLParam(r, "repoOwner")
		repoName := chi.URLParam(r, "repoName")

		// Need repo owner and name for authz so error if not found
		if repoOwner == "" || repoName == "" {
			h.recordError(ctx, baseTags, "missing_params")
			logger.WithContext(ctx).Info("repository owner and name cannot be empty")
			http.Error(rw, "repository owner and name cannot be empty", http.StatusBadRequest)

			return
		}

		// Verify user info present
		userInfo, ok := requestctx.User(ctx)
		if !ok || userInfo == nil {
			logger.WithContext(ctx).Info("user info not found in context")
			h.recordError(ctx, baseTags, "user_info_missing")
			http.Error(rw, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

			return
		}

		// Verify cred type is allowed - right now we just don't allow SSH certs
		if authd.CredentialType(userInfo.TokenInfo.Type) == authd.CredentialTypeSSHCertificate {
			logger.WithContext(ctx).Info("unsupported token type")
			h.recordError(ctx, baseTags, "unsupported_token_type")
			http.Error(rw, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

			return
		}

		// Verify token has access to repo
		hasAccess, err := h.verifyTokenAccess(ctx, userInfo, repoOwner, repoName)
		if err != nil {
			logger.WithContext(ctx).WithError(err).Info("failed to check token access")
			h.recordError(ctx, baseTags, "token_access_check_failed")
			http.Error(rw, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

			return
		}
		if !hasAccess {
			logger.WithContext(ctx).Info("token does not have access to repository")
			h.recordError(ctx, baseTags, "token_no_repo_access")
			http.Error(rw, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}

		route(userInfo, baseTags)(rw, r)
	}
}

func (h *Handler) verifyTokenAccess(ctx context.Context, user *requestctx.UserInfo, repoOwner, repoName string) (bool, error) {
	logger := h.obsv.LoggerWithTelemetry(ctx).Named("skills.Handler.verifyTokenAccess")

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
