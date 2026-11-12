// Package skillshttp provides HTTP handlers for the skills API.
package skillshttp

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/skills"
	"github.com/go-chi/chi/v5"
)

// Handler handles HTTP requests for skills.
type Handler struct {
	svc     *skills.Service
	obsv    observability.Exporters
	ghTwirp githubtwirp.ClientInterface
}

// NewHandler creates a new skills HTTP handler.
func NewHandler(svc *skills.Service, obsv observability.Exporters, ghTwirp githubtwirp.ClientInterface) *Handler {
	return &Handler{
		svc:     svc,
		obsv:    obsv,
		ghTwirp: ghTwirp,
	}
}

// RegisterRoutes registers the skill-related routes with the provided chi router.
func (h *Handler) RegisterRoutes(r chi.Router) {
	r.Route("/skills", func(r chi.Router) {
		r.Get("/{repoOwner}/{repoName}", h.middleware(h.listSkills, "http_list_skills"))
		r.Get("/{repoOwner}/{repoName}/{skillName}", h.middleware(h.getSkill, "http_get_skill"))
	})
}

// listSkillsResponse is the response structure for listing skills.
type listSkillsResponse struct {
	Skills []skills.SkillDTO `json:"skills"`
}

func (h *Handler) listSkills(userInfo *requestctx.UserInfo, baseTags stats.Tags) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "skills.Handler.listSkills")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r).Named("skills.Handler.listSkills")

		// Already validated in middleware
		repoOwner, repoName := chi.URLParam(r, "repoOwner"), chi.URLParam(r, "repoName")
		logger = logger.WithFields(
			kvp.String("repo_owner", repoOwner),
			kvp.String("repo_name", repoName),
		)

		// Parse include_sources parameter - defaults to all sources if not provided
		var includeSources []string
		includeSourcesParam := r.URL.Query().Get("include_sources")
		if includeSourcesParam != "" {
			includeSources = strings.Split(includeSourcesParam, ",")
			for i := range includeSources {
				includeSources[i] = strings.TrimSpace(includeSources[i])
				if includeSources[i] != skills.SourceTypeRepo &&
					includeSources[i] != skills.SourceTypeOrg &&
					includeSources[i] != skills.SourceTypeEnterprise {
					h.recordError(ctx, baseTags, "invalid_include_source")
					http.Error(w, "invalid source type: "+includeSources[i], http.StatusBadRequest)

					return
				}
			}
		}

		opts := skills.ListSkillsOpts{
			UserID:         userInfo.ID,
			DedupeNames:    r.URL.Query().Get("dedupe") != "false",
			IncludeSources: includeSources,
		}

		skillList, err := h.svc.ListSkills(ctx, repoOwner, repoName, opts)
		if err != nil {
			if errors.Is(err, skills.ErrRepoNotFound) {
				logger.WithContext(ctx).Info("repository not found")
				h.recordError(ctx, baseTags, "repo_not_found")
				http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

				return
			}
			if !errors.Is(err, skills.ErrNoSkillsFound) {
				logger.WithContext(ctx).WithError(err).Error("failed to list skills")
				h.recordError(ctx, baseTags, "list_skills_failed")
				http.Error(w, "failed to list skills", http.StatusInternalServerError)

				return
			}
			logger.WithContext(ctx).Info("no skills found for repository, returning empty list")
			skillList = make([]*skills.Skill, 0)
		}
		baseTags = baseTags.Merge(stats.Tags{
			"skill_count": strconv.Itoa(len(skillList)),
		})

		dtos := make([]skills.SkillDTO, 0, len(skillList))
		for _, skill := range skillList {
			dtos = append(dtos, skills.MakeSkillDTO(skill, false))
		}

		w.Header().Set("Content-Type", "application/json")

		err = json.NewEncoder(w).Encode(listSkillsResponse{Skills: dtos})
		if err != nil {
			logger.WithContext(ctx).WithError(err).Error("failed to encode response")
			h.recordError(ctx, baseTags, "encoding_failed")
			h.obsv.LogAndReportError(ctx, err, "skills.Handler failed to encode listSkills response")
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

			return
		}

		h.obsv.Increment(ctx, "skills.Handler.success", baseTags)
	}
}

func (h *Handler) getSkill(userInfo *requestctx.UserInfo, baseTags stats.Tags) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, span := h.obsv.Tracer.Start(r.Context(), "skills.Handler.getSkill")
		defer span.End()
		r = r.WithContext(ctx)

		logger := h.obsv.LoggerWithRequestTelemetry(ctx, r).Named("skills.Handler.getSkill")

		repoOwner := chi.URLParam(r, "repoOwner")
		repoName := chi.URLParam(r, "repoName")
		skillName := chi.URLParam(r, "skillName")

		// repoOwner and repoName already validated in middleware; only check skillName here
		if skillName == "" {
			h.recordError(ctx, baseTags, "missing_params")
			logger.WithContext(ctx).Info("skill name cannot be empty")
			http.Error(w, "skill name cannot be empty", http.StatusBadRequest)

			return
		}

		// Validate skill name to prevent path traversal attacks
		// Reject empty, traversal patterns (./..), and path separators
		if skillName == "." || skillName == ".." || strings.Contains(skillName, "/") || strings.Contains(skillName, "\\") {
			h.recordError(ctx, baseTags, "invalid_skill_name")
			logger.WithContext(ctx).Info("invalid skill name", kvp.String("skill_name", skillName))
			http.Error(w, "invalid skill name", http.StatusBadRequest)

			return
		}
		logger = logger.WithFields(
			kvp.String("repo_owner", repoOwner),
			kvp.String("repo_name", repoName),
			kvp.String("skill_name", skillName),
		)

		version := r.URL.Query().Get("version")

		opts := skills.GetSkillOpts{
			UserID: userInfo.ID,
		}

		skill, err := h.svc.GetSkill(ctx, repoOwner, repoName, skillName, version, opts)
		if err != nil {
			if errors.Is(err, skills.ErrRepoNotFound) {
				logger.WithContext(ctx).Info("repository not found")
				h.recordError(ctx, baseTags, "repo_not_found")
				http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

				return
			}
			if errors.Is(err, skills.ErrRequestedSkillNotFound) {
				logger.WithContext(ctx).Info("skill not found for repository")
				h.recordError(ctx, baseTags, "skill_not_found")
				http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)

				return
			}

			logger.WithContext(ctx).WithError(err).Error("failed to get skill")
			h.recordError(ctx, baseTags, "get_skill_failed")
			h.obsv.LogAndReportError(ctx, err, "skill.Handler failed to get skill")
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

			return
		}

		w.Header().Set("Content-Type", "application/json")
		err = json.NewEncoder(w).Encode(skills.MakeSkillDTO(skill, true))
		if err != nil {
			logger.WithContext(ctx).WithError(err).Error("failed to encode response")
			h.recordError(ctx, baseTags, "encoding_failed")
			h.obsv.LogAndReportError(ctx, err, "skills.Handler failed to encode getSkill response")
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

			return
		}

		h.obsv.Increment(ctx, "skills.Handler.success", baseTags)
	}
}

// recordError is a helper function to consistently record error metrics
func (h *Handler) recordError(ctx context.Context, tags stats.Tags, errorReason string) {
	errorTags := tags.Merge(stats.Tags{"error_reason": errorReason})
	h.obsv.Increment(ctx, "skills.error", errorTags)
}
