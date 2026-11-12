// Package customagenthttp provides HTTP handlers for managing custom agents.
package customagenthttp

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/go-chi/chi/v5"
)

// Handler is responsible for handling custom agent-related HTTP requests.
type Handler struct {
	obsv     observability.Exporters
	ffclient featureflags.Client
	svc      *customagent.Service
}

// NewHandler creates a new Handler instance with the provided observability exporters,
// feature flags client, and GitHub client factory.
// It initializes the service layer for custom agent operations.
func NewHandler(obsv observability.Exporters, ffclient featureflags.Client, svc *customagent.Service) *Handler {
	return &Handler{
		obsv:     obsv,
		ffclient: ffclient,
		svc:      svc,
	}
}

// RegisterRoutes registers the custom agent-related routes with the provided chi router.
// It defines a group of routes under the "/custom-agents" path.
func (h *Handler) RegisterRoutes(r chi.Router) {
	r.Route("/custom-agents", func(r chi.Router) {
		r.Get("/{repoOwner}/{repoName}", h.listAgents)
		r.Get("/{repoOwner}/{repoName}/{agentName}", h.getAgent)
	})

	// TODO: Remove subagents route once all clients have updated to use custom-agents
	r.Route("/subagents", func(r chi.Router) {
		r.Get("/{repoOwner}/{repoName}", h.listAgents)
		r.Get("/{repoOwner}/{repoName}/{agentName}", h.getAgent)
	})
}

type listAgentsResponse struct {
	Agents []customAgentDTO `json:"agents"`
}

func (h *Handler) listAgents(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "customagent.Handler.listAgents")
	defer span.End()
	start := time.Now()
	r = r.WithContext(ctx)

	logger := h.obsv.Logger.Named("customagent.Handler.listAgents")
	baseTags := h.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"endpoint": "list_agents",
	})
	h.obsv.Increment(ctx, "customagent.Handler.requests", baseTags)

	userInfo, ok := requestctx.User(ctx)
	if !ok || userInfo == nil {
		logger.WithContext(ctx).Info("user info not found in context")
		h.recordError(ctx, baseTags, "user_info_missing")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

		return
	}

	repoOwner, repoName := chi.URLParam(r, "repoOwner"), chi.URLParam(r, "repoName")
	if repoOwner == "" || repoName == "" {
		h.recordError(ctx, baseTags, "missing_params")
		http.Error(w, "repository owner and name cannot be empty", http.StatusBadRequest)
		return
	}

	// Query string to include/exclude invalid config
	excludeInvalidConfig := r.URL.Query().Get("exclude_invalid_config") == "true"
	if !h.ffclient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentReturnInvalidCustomAgentsByDefault, int64(userInfo.ID)) {
		excludeInvalidConfig = true
	}
	// Get the repository info for feature flag check
	enabled, err := h.svc.IsEnabledForRepoByName(ctx, int64(userInfo.ID), repoOwner, repoName)
	if err != nil {
		if errors.Is(err, customagent.ErrRepoNotFound) {
			logger.WithContext(ctx).Info("repository not found")
			h.recordError(ctx, baseTags, "repo_not_found")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}
		logger.WithContext(ctx).WithError(err).Error("failed to get repository info")
		h.recordError(ctx, baseTags, "check_enablement_failed")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}
	if !enabled {
		logger.WithContext(ctx).Info("custom agents not enabled for repository")
		http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

		return
	}

	agents, err := h.svc.ListAgents(ctx, userInfo.ID, repoOwner, repoName, excludeInvalidConfig)
	if err != nil {
		if errors.Is(err, customagent.ErrRepoNotFound) {
			logger.WithContext(ctx).Info("repository not found")
			h.recordError(ctx, baseTags, "repo_not_found")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}
		if errors.Is(err, customagent.ErrNoAgentsFound) {
			logger.WithContext(ctx).Info("no agents found for repository")
			h.recordError(ctx, baseTags, "no_agents_found")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}

		logger.WithContext(ctx).WithError(err).Error("failed to list agents")
		h.recordError(ctx, baseTags, "list_agents_failed")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}
	baseTags = baseTags.Merge(stats.Tags{
		"agent_count": strconv.Itoa(len(agents)),
	})
	h.obsv.DistributionMs(ctx, "customagent.Handler.request_duration", baseTags, time.Since(start))

	dtos := make([]customAgentDTO, 0, len(agents))
	for _, agent := range agents {
		dtos = append(dtos, makeCustomAgentDTO(agent, false))
	}

	response := listAgentsResponse{
		Agents: dtos,
	}

	w.Header().Set("Content-Type", "application/json")

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to encode response")
		h.recordError(ctx, baseTags, "encoding_failed")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	h.obsv.Increment(ctx, "customagent.Handler.success", baseTags)
}

type customAgentDTO struct {
	Name        string                      `json:"name"`
	RepoOwnerID int64                       `json:"repo_owner_id"`
	RepoOwner   string                      `json:"repo_owner"`
	RepoID      int64                       `json:"repo_id"`
	RepoName    string                      `json:"repo_name"`
	DisplayName string                      `json:"display_name"`
	Description string                      `json:"description"`
	Prompt      string                      `json:"prompt,omitempty"`
	Tools       []string                    `json:"tools"`
	Version     string                      `json:"version"`
	MCPServers  map[string]mcpconfig.Server `json:"mcp_servers,omitempty"`
	ConfigError string                      `json:"config_error,omitempty"`
	Target      string                      `json:"target,omitempty"`
}

func makeCustomAgentDTO(agent sweagentd.CustomAgent, includePrompt bool) customAgentDTO {
	dto := customAgentDTO{
		Name:        agent.Name(),
		RepoOwnerID: agent.RepoOwnerID(),
		RepoOwner:   agent.RepoOwner(),
		RepoID:      agent.RepoID(),
		RepoName:    agent.RepoName(),
		DisplayName: agent.DisplayName(),
		Description: agent.Description(),
		Tools:       agent.Tools(),
		Version:     agent.Version(),
		MCPServers:  agent.MCPConfig().Servers,
		ConfigError: agent.ConfigError(),
		Target:      agent.Target(),
	}

	if includePrompt {
		dto.Prompt = agent.Prompt()
	}

	return dto
}

func (h *Handler) getAgent(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "customagent.Handler.getAgent")
	defer span.End()
	start := time.Now()
	r = r.WithContext(ctx)

	logger := h.obsv.Logger.Named("customagent.Handler.getAgent")
	baseTags := h.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"endpoint": "get_agent",
	})
	h.obsv.Increment(ctx, "customagent.Handler.requests", baseTags)

	userInfo, ok := requestctx.User(ctx)
	if !ok || userInfo == nil {
		logger.WithContext(ctx).Info("user info not found in context")
		h.recordError(ctx, baseTags, "user_info_missing")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

		return
	}

	repoOwner, repoName, agentName := chi.URLParam(r, "repoOwner"), chi.URLParam(r, "repoName"), chi.URLParam(r, "agentName")
	if repoOwner == "" || repoName == "" || agentName == "" {
		h.recordError(ctx, baseTags, "missing_params")
		http.Error(w, "repository owner, name, and agent name cannot be empty", http.StatusBadRequest)
		return
	}

	enabled, err := h.svc.IsEnabledForRepoByName(ctx, int64(userInfo.ID), repoOwner, repoName)
	if err != nil {
		if errors.Is(err, customagent.ErrRepoNotFound) {
			logger.WithContext(ctx).Info("repository not found")
			h.recordError(ctx, baseTags, "repo_not_found")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}
		logger.WithContext(ctx).WithError(err).Error("failed to get repository info")
		h.recordError(ctx, baseTags, "check_enablement_failed")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}
	if !enabled {
		logger.WithContext(ctx).Info("custom agents not enabled for repository")
		http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

		return
	}
	// Version can be a SHA, tag, or branch name - if empty, uses the default branch
	version := r.URL.Query().Get("version")
	agent, err := h.svc.GetAgent(ctx, userInfo.ID, repoOwner, repoName, agentName, version)
	if err != nil {
		if errors.Is(err, customagent.ErrRepoNotFound) {
			logger.WithContext(ctx).Info("repository not found")
			h.recordError(ctx, baseTags, "repo_not_found")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}
		if errors.Is(err, customagent.ErrRequestedAgentNotFound) {
			logger.WithContext(ctx).Info("agent not found for repository")
			h.recordError(ctx, baseTags, "agent_not_found")
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

			return
		}

		logger.WithContext(ctx).WithError(err).Error("failed to get agent")
		h.recordError(ctx, baseTags, "get_agent_failed")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}
	h.obsv.DistributionMs(ctx, "customagent.Handler.request_duration", baseTags, time.Since(start))

	w.Header().Set("Content-Type", "application/json")

	err = json.NewEncoder(w).Encode(makeCustomAgentDTO(agent, true))
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to encode response")
		h.recordError(ctx, baseTags, "encoding_failed")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	h.obsv.Increment(ctx, "customagent.Handler.success", baseTags)
}

// recordError is a helper function to consistently record error metrics
func (h *Handler) recordError(ctx context.Context, baseTags stats.Tags, errorReason string) {
	errorTags := baseTags.Merge(stats.Tags{
		"success":      "false",
		"error_reason": errorReason,
	})
	h.obsv.Increment(ctx, "customagent.Handler.errors", errorTags)
}
