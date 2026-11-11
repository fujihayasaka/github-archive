// Package models provides business logic for model operations and API handlers.
package models

import (
	"context"

	gg "github.com/google/go-github/v75/github"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
)

// AutoModel represents the auto model configuration
var AutoModel = capi.Model{
	ID:                  capi.AutoMode,
	Name:                "Auto",
	Object:              "model",
	Auto:                gg.Ptr(true),
	IsChatDefault:       gg.Ptr(true),
	ModelPickerEnabled:  gg.Ptr(true),
	ModelPickerCategory: gg.Ptr("versatile"),
	Preview:             gg.Ptr(false),
	Vendor:              gg.Ptr("GitHub"),
	Version:             "auto-1",
	Capabilities: &capi.ModelCapabilities{
		// Model picker will use this to filter models
		Type: "chat",
	},
	Billing: &capi.ModelBilling{
		IsPremium:  true,
		Multiplier: 1,
	},
}

// Service provides business logic for model operations
type Service struct {
	capi capi.Client
	ffs  featureflags.Client
}

// NewService creates a new models service
func NewService(capiClient capi.Client, ffs featureflags.Client) *Service {
	return &Service{
		capi: capiClient,
		ffs:  ffs,
	}
}

// ListPolicyEnabledModels returns a list of models that are enabled by policy for a user,
// with the auto model prepended. Models are also filtered by per-model feature flags
// to control which models appear in the model picker.
func (s *Service) ListPolicyEnabledModels(ctx context.Context, userID uint64) ([]capi.Model, error) {
	// Empty actorType: CAPI only accepts "org" or empty. This endpoint is always user-scoped
	// (model picker UI), and CAPI defaults to user when the header is absent.
	models, err := s.capi.ListCodingAgentModels(ctx, userID, "")
	if err != nil {
		return nil, err
	}

	// Filter out any models that are policy-disabled. CAPI enforces model policies for our
	// integration, so this acts as a secondary safeguard and also filters by per-model
	// feature flags to control model picker visibility.
	enabledModels := []capi.Model{}
	for _, model := range models {
		if model.Policy != nil && model.Policy.State == capi.ModelPolicyStateDisabled {
			continue
		}
		if flag, ok := capi.CodingAgentModelPickerModelFlags[model.ID]; ok && !s.ffs.IsEnabledForUser(ctx, flag, int64(userID)) {
			continue
		}
		enabledModels = append(enabledModels, model)
	}

	autoModel := AutoModel
	autoModel.Billing = &capi.ModelBilling{
		IsPremium:  true,
		Multiplier: 0.9,
	}

	// Prepend the "auto" model to the list
	return append([]capi.Model{autoModel}, enabledModels...), nil
}
