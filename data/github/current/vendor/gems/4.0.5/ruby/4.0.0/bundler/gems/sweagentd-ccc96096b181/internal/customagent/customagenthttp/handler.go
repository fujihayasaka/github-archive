// Package customagenthttp provides HTTP handlers for managing custom agents.
package customagenthttp

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
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
	ghTwirp  githubtwirp.ClientInterface
	svc      *customagent.Service
}

// NewHandler creates a new Handler instance with the provided observability exporters,
// feature flags client, and GitHub client factory.
// It initializes the service layer for custom agent operations.
func NewHandler(obsv observability.Exporters, ffclient featureflags.Client, ghTwirp githubtwirp.ClientInterface, svc *customagent.Service) *Handler {
	return &Handler{
		obsv:     obsv,
		ffclient: ffclient,
		ghTwirp:  ghTwirp,
		svc:      svc,
	}
}

// RegisterRoutes registers the custom agent-related routes with the provided chi router.
// It defines a group of routes under the "/custom-agents" path.
func (h *Handler) RegisterRoutes(r chi.Router) {
	r.Route("/custom-agents", func(r chi.Router) {
		r.Get("/{repoOwner}/{repoName}", h.middleware(h.listAgents, "http_list_agents"))
		r.Get("/{repoOwner}/{repoName}/{agentName}", h.middleware(h.getAgent, "http_get_agent"))
	})
}

type listAgentsResponse struct {
	Agents []customAgentDTO `json:"agents"`
}

func (h *Handler) listAgents(userInfo *requestctx.UserInfo, baseTags stats.Tags) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "customagent.Handler.listAgents")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r).Named("customagent.Handler.listAgents")

		repoOwner, repoName := chi.URLParam(r, "repoOwner"), chi.URLParam(r, "repoName")
		if repoOwner == "" || repoName == "" {
			h.recordError(ctx, baseTags, "missing_params")
			logger.WithContext(ctx).Info("repository owner, name, and agent name cannot be empty")
			http.Error(w, "repository owner and name cannot be empty", http.StatusBadRequest)
			return
		}
		logger = logger.WithFields(
			kvp.String("repo_owner", repoOwner),
			kvp.String("repo_name", repoName))

		// Parse include_sources parameter - comma-separated list of: repo, org, enterprise
		// Defaults to all sources if not specified
		var includeSources []string
		includeSourcesParam := r.URL.Query().Get("include_sources")
		if includeSourcesParam != "" {
			includeSources = strings.Split(includeSourcesParam, ",")
			// Trim whitespace from each source
			for i := range includeSources {
				includeSources[i] = strings.TrimSpace(includeSources[i])
				// Validate source type
				if includeSources[i] != customagent.SourceTypeRepo &&
					includeSources[i] != customagent.SourceTypeOrg &&
					includeSources[i] != customagent.SourceTypeEnterprise {
					h.recordError(ctx, baseTags, "invalid_include_source")
					http.Error(w, "invalid source type: "+includeSources[i], http.StatusBadRequest)
					return
				}
			}
		}
		// Set other query string based options
		opts := customagent.ListAgentsOpts{
			ExcludeInvalidConfig: r.URL.Query().Get("exclude_invalid_config") == "true",
			DedupeNames:          r.URL.Query().Get("dedupe") != "false",
			IncludeSources:       includeSources,
			Target:               r.URL.Query().Get("target"),
			UserID:               userInfo.ID,
		}

		// Currently mobile and dotcom expect that the agents that come back from this list API will be applicable to github-copilot
		// and would include a `config_error` field otherwise. To maintain backward compatibility, we default to [customagent.TargetGitHubCopilot],
		// but this feature flag will allow us to change this behavior in the future as these other clients start specifying target explicitly.
		if !h.ffclient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentCustomAgentListDefaultToAll, int64(userInfo.ID)) {
			if opts.Target == customagent.TargetEmpty {
				opts.Target = customagent.TargetGitHubCopilot
			}
		}

		agents, err := h.svc.ListAgents(ctx, repoOwner, repoName, opts)
		if err != nil {
			if errors.Is(err, customagent.ErrRepoNotFound) {
				logger.WithContext(ctx).Info("repository not found")
				h.recordError(ctx, baseTags, "repo_not_found")
				http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

				return
			}
			if !errors.Is(err, customagent.ErrNoAgentsFound) {
				logger.WithContext(ctx).WithError(err).Error("failed to list agents")
				h.recordError(ctx, baseTags, "list_agents_failed")
				http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

				return
			}
			// User has access to the repo (verified by IsEnabledForRepoByName above)
			// but no custom agents are defined. Return empty list instead of 404.
			logger.WithContext(ctx).Info("no agents found for repository, returning empty list")
			agents = make([]sweagentd.CustomAgent, 0)
		}
		baseTags = baseTags.Merge(stats.Tags{
			"agent_count": strconv.Itoa(len(agents)),
		})

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
			h.obsv.LogAndReportError(ctx, err, "customagent.Handler failed to encode listAgents response")
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

			return
		}

		h.obsv.Increment(ctx, "customagent.Handler.success", baseTags)
	}
}

type customAgentDTO struct {
	Name             string                         `json:"name"`
	RepoOwnerID      int64                          `json:"repo_owner_id"`
	RepoOwner        string                         `json:"repo_owner"`
	RepoID           int64                          `json:"repo_id"`
	RepoName         string                         `json:"repo_name"`
	DisplayName      string                         `json:"display_name"`
	Description      string                         `json:"description"`
	Prompt           string                         `json:"prompt,omitempty"`
	Tools            []string                       `json:"tools"`
	Version          string                         `json:"version"`
	MCPServers       map[string]mcpconfig.Server    `json:"mcp_servers,omitempty"`
	ConfigError      string                         `json:"config_error,omitempty"`
	Target           string                         `json:"target,omitempty"`
	ArgumentHint     string                         `json:"argument_hint,omitempty"`
	Metadata         map[string]string              `json:"metadata,omitempty"`
	InferenceEnabled bool                           `json:"infer"`
	Model            string                         `json:"model,omitempty"`
	Handoffs         []sweagentd.CustomAgentHandoff `json:"handoffs,omitempty"`

	// TODO: Return Permissions and Triggers once we are confident in structure
}

func makeCustomAgentDTO(agent sweagentd.CustomAgent, includePrompt bool) customAgentDTO {
	dto := customAgentDTO{
		Name:             agent.Name(),
		RepoOwnerID:      agent.RepoOwnerID(),
		RepoOwner:        agent.RepoOwner(),
		RepoID:           agent.RepoID(),
		RepoName:         agent.RepoName(),
		DisplayName:      agent.DisplayName(),
		Description:      agent.Description(),
		Tools:            agent.Tools(),
		Version:          agent.Version(),
		MCPServers:       agent.MCPConfig().Servers,
		ConfigError:      agent.ConfigError(),
		Target:           agent.Target(),
		ArgumentHint:     agent.ArgumentHint(),
		Metadata:         agent.Metadata(),
		InferenceEnabled: agent.InferenceEnabled(),
		Model:            agent.Model(),
		Handoffs:         agent.Handoffs(),
	}

	if includePrompt {
		dto.Prompt = agent.Prompt()
	}

	return dto
}

func (h *Handler) getAgent(userInfo *requestctx.UserInfo, baseTags stats.Tags) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "customagent.Handler.getAgent")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r).Named("customagent.Handler.getAgent")

		repoOwner, repoName, agentName := chi.URLParam(r, "repoOwner"), chi.URLParam(r, "repoName"), chi.URLParam(r, "agentName")
		if repoOwner == "" || repoName == "" || agentName == "" {
			h.recordError(ctx, baseTags, "missing_params")
			logger.WithContext(ctx).Info("repository owner, name, and agent name cannot be empty")
			http.Error(w, "repository owner, name, and agent name cannot be empty", http.StatusBadRequest)
			return
		}
		logger = logger.WithFields(
			kvp.String("repo_owner", repoOwner),
			kvp.String("repo_name", repoName),
			kvp.String("agent_name", agentName))

		// Version can be a SHA, tag, or branch name - if empty or "latest", uses the default branch
		version := r.URL.Query().Get("version")
		agent, err := h.svc.GetAgent(ctx, repoOwner, repoName, agentName, version, customagent.GetAgentOpts{UserID: userInfo.ID})
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
			h.obsv.LogAndReportError(ctx, err, "customagent.Handler failed to get agent")
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

			return
		}

		w.Header().Set("Content-Type", "application/json")

		err = json.NewEncoder(w).Encode(makeCustomAgentDTO(agent, true))
		if err != nil {
			logger.WithContext(ctx).WithError(err).Error("failed to encode response")
			h.recordError(ctx, baseTags, "encoding_failed")
			h.obsv.LogAndReportError(ctx, err, "customagent.Handler failed to encode getAgent response")
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

			return
		}

		h.obsv.Increment(ctx, "customagent.Handler.success", baseTags)
	}
}

// recordError is a helper function to consistently record error metrics
func (h *Handler) recordError(ctx context.Context, baseTags stats.Tags, errorReason string) {
	errorTags := baseTags.Merge(stats.Tags{
		"success":      "false",
		"error_reason": errorReason,
	})
	h.obsv.Increment(ctx, "customagent.Handler.errors", errorTags)
}
