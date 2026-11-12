// Package modelshttp provides HTTP handlers for models-related APIs.
package modelshttp

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/models"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
)

type listModelsResponse struct {
	Data   []capi.Model `json:"data"`
	Object string       `json:"object"`
}

// Handler is responsible for handling models-related HTTP requests.
type Handler struct {
	obsv    observability.Exporters
	svc     *models.Service
	ghTwirp githubtwirp.ClientInterface
	ffs     featureflags.Client
}

// NewHandler creates a new Handler instance with the provided observability exporters
// and models service.
func NewHandler(obsv observability.Exporters, svc *models.Service, ghTwirp githubtwirp.ClientInterface, ffs featureflags.Client) *Handler {
	return &Handler{
		obsv:    obsv,
		svc:     svc,
		ghTwirp: ghTwirp,
		ffs:     ffs,
	}
}

// RegisterRoutes registers the models-related routes with the provided chi router.
func (h *Handler) RegisterRoutes(r chi.Router) {
	r.Get("/models", h.listModels)
}

func (h *Handler) listModels(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	ctx, span := h.obsv.Tracer.Start(ctx, "modelshttp.listModels")
	defer span.End()

	logger := h.obsv.Logger.Named("modelshttp.Handler.listModels")

	userInfo, ok := requestctx.User(ctx)
	if !ok {
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	modelsList, err := h.svc.ListPolicyEnabledModels(ctx, userInfo.ID)
	if err != nil {
		var capiErr *joberrors.CAPIError
		if errors.As(err, &capiErr) {
			statusCode := capiErr.StatusCode()
			if statusCode == http.StatusForbidden || statusCode == http.StatusUnauthorized {
				logger.WithContext(ctx).WithError(err).Info("CAPI denied access to models")
				http.Error(w, http.StatusText(statusCode), statusCode)
				return
			}
		}
		logger.WithContext(ctx).WithError(err).Error("failed to list models from CAPI")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}

	// Filter models based on user plan
	userDetails, err := h.ghTwirp.GetCopilotUserDetails(ctx, int64(userInfo.ID))
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to get user details")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}

	plan, err := githubtwirp.CopilotPlanFromUser(userDetails)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to determine user plan")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}

	// Return empty list for Business and Enterprise users unless the feature flag is enabled
	if plan == githubtwirp.CopilotForBusiness || plan == githubtwirp.CopilotForEnterprise {
		// Check if the feature flag to allow model selection for all SKUs is enabled
		if !h.ffs.IsEnabledForUser(ctx, "coding_agent_model_selection_all_skus", int64(userInfo.ID)) {
			modelsList = []capi.Model{}
		}
	}

	// Return a response that matches CAPI's /models endpoint
	modelsResp := listModelsResponse{
		Data:   modelsList,
		Object: "list",
	}

	// Return the response as JSON
	w.Header().Set("Content-Type", "application/json")
	err = json.NewEncoder(w).Encode(modelsResp)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to encode models response")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}
}
