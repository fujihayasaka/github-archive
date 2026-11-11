package agenthttp

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agent"
	"github.com/github/sweagentd/internal/auth/oidc"
	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	chi "github.com/go-chi/chi/v5"
)

// exchangeTokens is the handler for OIDC and general token access and refresh.
// Currently it focuses on OIDC token exchange, but can be expanded in the future
// to handle other types of secrets. For example, refreshing or updating privileges
// for GITHUB_COPILOT_GITHUB_TOKEN.
//
// Error responses:
//   - 400 Bad Request: missing job ID, invalid request body, empty secret/MCP server names, or invalid secret name prefix.
//   - 401 Unauthorized: authorization failed or nonce validation failed.
//   - 404 Not Found: enablement check failed or OIDC token exchange feature not enabled.
//   - 500 Internal Server Error: app lookup failed, token exchange failed, or response encoding failed.
func (h *Handler) exchangeTokens(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "agenthttp.Handler.exchangeTokens")
	defer span.End()
	r = r.WithContext(ctx)
	logger := h.obsv.LoggerWithRequestTelemetry(ctx, r).Named("agenthttp.Handler.exchangeTokens")

	baseTags := h.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"endpoint": "exchange_tokens",
	})

	userInfo, err := h.authorize(ctx)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("authorization failed")
		h.recordError(ctx, baseTags, "authorization_failed")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

		return
	}

	jobID := chi.URLParam(r, "jobID")
	if jobID == "" {
		logger.WithContext(ctx).Info("job ID not provided")
		h.recordError(ctx, baseTags, "missing_job_id")
		http.Error(w, "job_id is required", http.StatusBadRequest)

		return
	}

	job, err := h.svc.GetJob(ctx, jobID)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to get job")
		h.recordError(ctx, baseTags, "get_job_failed")
		h.handleDomainError(w, err)
		return
	}

	app, appErr := h.appProvider.FindByID(ctx, job.AgentID)
	if appErr != nil {
		logger.WithContext(ctx).WithError(appErr).Error("failed to find app by ID")
		h.recordError(ctx, baseTags, "app_lookup_failed")
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)

		return
	}

	if !h.ffs.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentSkipCallbackEnablementCheck, int64(userInfo.ID)) {
		_, appErr = h.checkEnablement(ctx, app.AppID(), int64(userInfo.ID), job.RepoID)
		if appErr != nil {
			logger.WithContext(ctx).WithError(appErr).Error("enablement check failed")
			h.recordError(ctx, baseTags, "enablement_check_failed")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}
	}

	err = h.validateNonce(r, job.NonceHash)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("access validation failed")
		h.recordError(ctx, baseTags, "nonce_validation_failed")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

		return
	}

	// TODO (chuxel): Remove this ff check once the OIDC token exchange is fully rolled out and we are confident it's stable.
	// But do not remove the disallow ff check as that will be needed to turn off the feature in case of any issues.
	if !h.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentOIDCTokenExchange, job) {
		logger.WithContext(ctx).Info("OIDC token exchange is not enabled")
		h.recordError(ctx, baseTags, "oidc_token_exchange_feature_disabled")
		http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

		return
	}
	if h.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentOIDCTokenExchangeDisallow, job) ||
		h.ffs.IsEnabledForGitHubApp(ctx, featureflags.CopilotSWEAgentOIDCTokenExchangeDisallow, app.AppID()) {
		logger.WithContext(ctx).Info("OIDC token exchange is disallowed")
		h.recordError(ctx, baseTags, "oidc_token_exchange_feature_disallowed")
		http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

		return
	}

	var req tokensRequestDTO
	err = json.NewDecoder(r.Body).Decode(&req)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to decode tokens request")
		h.recordError(ctx, baseTags, "invalid_request_body")
		http.Error(w, "invalid request body", http.StatusBadRequest)

		return
	}

	// Do some up front validation on secret names
	filteredSecretNames := make([]string, 0, len(req.SecretNames))
	for _, name := range req.SecretNames {
		// GITHUB_COPILOT_OIDC_MCP_TOKEN (and suffixed variants like GITHUB_COPILOT_OIDC_MCP_TOKEN_MY_SVC)
		// are placeholder secret names resolved from the MCP server's token, not the per-secret exchange.
		if name == "GITHUB_COPILOT_OIDC_MCP_TOKEN" || strings.HasPrefix(name, "GITHUB_COPILOT_OIDC_MCP_TOKEN_") {
			continue
		}
		if !oidcconfig.IsValidSecretName(name) {
			logger.WithContext(ctx).Info("secret name missing required prefix", kvp.String("secret_name", name))
			h.recordError(ctx, baseTags, "invalid_secret_name_prefix")
			http.Error(w, "invalid prefix found in secret_names", http.StatusBadRequest)

			return
		}
		filteredSecretNames = append(filteredSecretNames, name)
	}

	if len(req.SecretNames) == 0 && len(req.MCPServerNames) == 0 {
		logger.WithContext(ctx).Info("no secret names or MCP server names provided")
		h.recordError(ctx, baseTags, "no_secret_or_mcp_server_names")
		http.Error(w, "secret_names or mcp_server_names is required", http.StatusBadRequest)

		return
	}

	statusCode := http.StatusOK
	result, err := h.svc.ExecuteTokenExchange(ctx, agent.ExecuteTokenExchangeParams{
		Job:            job,
		UserInfo:       userInfo,
		AgentName:      req.AgentName,
		AgentVersion:   req.AgentVersion,
		SecretNames:    filteredSecretNames,
		MCPServerNames: req.MCPServerNames,
		App:            app,
	})
	if err != nil {
		// If the error indicates a partial failure, continue but note a different status code
		if !errors.Is(err, oidc.ErrPartialSuccess) {
			statusCode, ok := statusCodeFromTokenExchangeError(err)
			if !ok {
				statusCode = http.StatusInternalServerError
			}
			logger.WithContext(ctx).WithError(err).Error("failed to execute token exchange")
			h.recordError(ctx, baseTags, "token_exchange_failed")
			http.Error(w, http.StatusText(statusCode), statusCode)

			return
		}
		logger.WithContext(ctx).WithError(err).Info("token exchange partially successful")
		statusCode = http.StatusPartialContent
	}

	h.writeTokenExchangeResponse(ctx, w, logger, baseTags, statusCode, result)
}

func (h *Handler) writeTokenExchangeResponse(
	ctx context.Context,
	w http.ResponseWriter,
	logger log.Logger,
	baseTags stats.Tags,
	statusCode int,
	result *oidc.ExchangeResult,
) {
	resp := tokensResponseDTO{SecretTokens: result.Secrets, MCPServerTokens: result.MCPServerTokens}
	for _, f := range result.Failures {
		resp.Failures = append(resp.Failures, tokenFailureDTO{
			ResponseCode: f.ResponseCode,
			Message:      f.Message,
			Error:        f.Error,
			FailureURL:   f.FailureURL,
			SecretName:   f.SecretName,
			ServerName:   f.ServerName,
		})
	}

	for _, warning := range result.Warnings {
		resp.Warnings = append(resp.Warnings, tokenWarningDTO{
			Message: warning.Message,
		})
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	err := json.NewEncoder(w).Encode(resp)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to encode tokens response")
		h.recordError(ctx, baseTags, "response_encoding_failed")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	if statusCode == http.StatusPartialContent {
		for _, f := range result.Failures {
			logger.WithContext(ctx).Info("token exchange partial failure",
				kvp.String("endpoint", "exchange_tokens"),
				kvp.String("variable_name", f.SecretName),
				kvp.String("server_name", f.ServerName),
				kvp.Int("response_code", f.ResponseCode),
				kvp.String("message", f.Message),
				kvp.String("error", f.Error),
			)
		}
		h.recordSuccessWithErrors(ctx, baseTags, "token_exchange_partially_successful")
		return
	}

	if len(resp.Failures) == 0 {
		h.recordSuccess(ctx, baseTags)
	}
}

func statusCodeFromTokenExchangeError(err error) (int, bool) {
	var ghErr *github.GitHubAPIError
	if errors.As(err, &ghErr) {
		statusCode := ghErr.StatusCode()
		switch statusCode {
		case http.StatusBadRequest, http.StatusUnauthorized, http.StatusForbidden, http.StatusNotFound, http.StatusUnprocessableEntity:
			return statusCode, true
		}
	}
	return 0, false
}
