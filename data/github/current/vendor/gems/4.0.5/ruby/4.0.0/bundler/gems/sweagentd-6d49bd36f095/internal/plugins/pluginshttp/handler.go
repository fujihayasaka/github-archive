package pluginshttp

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
)

// Handler handles HTTP requests for plugins.
type Handler struct {
	svc     *plugins.Service
	obsv    observability.Exporters
	ghTwirp githubtwirp.ClientInterface
	ffs     featureflags.Client
}

// NewHandler creates a new plugins HTTP handler.
func NewHandler(svc *plugins.Service, obsv observability.Exporters, ghTwirp githubtwirp.ClientInterface, ffs featureflags.Client) *Handler {
	return &Handler{
		svc:     svc,
		obsv:    obsv,
		ghTwirp: ghTwirp,
		ffs:     ffs,
	}
}

// RegisterRoutes registers the plugin-related routes with the provided chi router.
func (h *Handler) RegisterRoutes(r chi.Router) {
	r.Route("/plugins", func(r chi.Router) {
		r.Get("/{repoOwner}/{repoName}", h.middleware(h.listPlugins))
	})
}

type listPluginsResponse struct {
	Settings *plugins.SettingsJSON `json:"settings"`
	// TODO(@belaltaher8): remove the plugin dto from this response or put it behind a URL param
	PluginRepos []plugins.PluginDTO `json:"plugins"`
}

func (h *Handler) listPlugins(userInfo *requestctx.UserInfo, baseTags stats.Tags) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "plugins.Handler.listPlugins")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r).Named("plugins.Handler.listPlugins")

		// Already validated in middleware
		repoOwner, repoName := chi.URLParam(r, "repoOwner"), chi.URLParam(r, "repoName")
		logger = logger.WithFields(
			kvp.String("repo_owner", repoOwner),
			kvp.String("repo_name", repoName),
		)

		// Parse include_sources URL parameter (defaults to all sources)
		includeSources := []string{plugins.SourceTypeRepo, plugins.SourceTypeOrg, plugins.SourceTypeEnterprise}
		includeSourcesParam := r.URL.Query().Get("include_sources")
		if includeSourcesParam != "" {
			includeSources = strings.Split(includeSourcesParam, ",")
			for i := range includeSources {
				includeSources[i] = strings.TrimSpace(includeSources[i])
				if includeSources[i] != plugins.SourceTypeRepo &&
					includeSources[i] != plugins.SourceTypeOrg &&
					includeSources[i] != plugins.SourceTypeEnterprise {
					http.Error(w, "invalid source type: "+includeSources[i], http.StatusBadRequest)
					return
				}
			}
		}

		// TODO(@belaltaher8): We should probably follow redirects to avoid issues with renamed repos
		repo, err := h.ghTwirp.GetRepoByName(ctx, repoOwner, repoName)
		if err != nil || repo == nil {
			logger.WithContext(ctx).WithError(err).Error("failed to get repo")
			http.Error(w, "repository not found", http.StatusNotFound)
			return
		}

		repoID := uint64(repo.GetId())
		ownerID := uint64(repo.GetOwnerId())

		// Load settings (merged from repo/org/enterprise based on include_sources)
		settings, err := h.svc.LoadMergedSettings(ctx, repoID, ownerID, repoOwner, includeSources)
		if err != nil {
			logger.WithContext(ctx).WithError(err).Error("failed to load plugin settings")
			http.Error(w, "failed to load plugin settings", http.StatusInternalServerError)
			return
		}

		// Resolve the plugin repos
		pluginMetadata, err := h.svc.ResolvePluginRepos(ctx, settings)
		if err != nil {
			logger.WithContext(ctx).WithError(err).Warn("partial failure resolving plugin repos")
		}
		pluginRepos := make([]plugins.PluginDTO, 0, len(pluginMetadata))
		for _, meta := range pluginMetadata {
			pluginRepos = append(pluginRepos, plugins.PluginDTO{
				CloneURL:          meta.CloneURL,
				Path:              meta.Path,
				MarketplaceName:   meta.MarketplaceName,
				Spec:              meta.Spec,
				ResolutionFailure: meta.ResolutionFailure,
				SHA:               meta.SHA,
			})
		}

		w.Header().Set("Content-Type", "application/json")
		err = json.NewEncoder(w).Encode(listPluginsResponse{
			Settings:    settings,
			PluginRepos: pluginRepos,
		})

		if err != nil {
			logger.WithContext(ctx).WithError(err).Error("failed to encode response")
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			return
		}
	}
}
