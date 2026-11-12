// Package modelshttp provides HTTP handlers for models-related APIs.
package modelshttp

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/models"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
)

// vendorIntegrationIDs maps vendor names (case-insensitive) to the CAPI
// integration ID that should be used when fetching models for that vendor.
var vendorIntegrationIDs = map[string]string{
	"anthropic": agenticapp.ClaudeCAPIIntegrationID,
	"openai":    agenticapp.CodexCAPIIntegrationID,
}

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
// Any provided middlewares are applied to the routes.
func (h *Handler) RegisterRoutes(r chi.Router, middlewares ...func(http.Handler) http.Handler) {
	r.With(middlewares...).Get("/models", h.listModels)
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

	// When a vendor query param is provided and the feature flag is enabled,
	// set the agent-specific integration ID on the context so CAPI returns
	// the correct model catalog for that vendor's agent.
	vendor := r.URL.Query().Get("vendor")
	if vendor != "" &&
		h.ffs.IsEnabledForUser(ctx, featureflags.CodingAgentCAPI3pIntegrationID, int64(userInfo.ID)) {
		if integrationID, ok := vendorIntegrationIDs[strings.ToLower(vendor)]; ok {
			ctx = capi.ContextWithCAPIIntegrationID(ctx, integrationID)
		}
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
			if h.ffs.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentForwardCAPIStatusCodes, int64(userInfo.ID)) &&
				statusCode == http.StatusTooManyRequests {
				logger.WithContext(ctx).WithError(err).Warn("CAPI rate limited on models request")
				if retryAfter := capiErr.Response.Header.Get("Retry-After"); retryAfter != "" {
					w.Header().Set("Retry-After", retryAfter)
				}
				http.Error(w, http.StatusText(http.StatusTooManyRequests), http.StatusTooManyRequests)
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

	// Filter by vendor if query parameter is provided and feature flag is enabled
	if vendor := r.URL.Query().Get("vendor"); vendor != "" &&
		h.ffs.IsEnabledForUser(ctx, featureflags.CodingAgentThirdPartyModelVendorFilter, int64(userInfo.ID)) {
		filtered := make([]capi.Model, 0, len(modelsList))
		for _, model := range modelsList {
			// Always include the auto model regardless of vendor
			if model.Auto != nil && *model.Auto {
				filtered = append(filtered, model)
				continue
			}
			if model.Vendor != nil && strings.EqualFold(*model.Vendor, vendor) {
				filtered = append(filtered, model)
			}
		}
		modelsList = filtered
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
