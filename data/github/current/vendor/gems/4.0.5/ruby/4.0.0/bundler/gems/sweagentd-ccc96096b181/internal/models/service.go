// Package models provides business logic for model operations and API handlers.
package models

import (
	"context"

	gg "github.com/google/go-github/v75/github"

	"github.com/github/sweagentd/internal/capi"
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
}

// NewService creates a new models service
func NewService(capiClient capi.Client) *Service {
	return &Service{
		capi: capiClient,
	}
}

// ListPolicyEnabledModels returns a list of models that are enabled by policy for a user,
// with the auto model prepended.
func (s *Service) ListPolicyEnabledModels(ctx context.Context, userID uint64) ([]capi.Model, error) {
	models, err := s.capi.ListCodingAgentModels(ctx, userID)
	if err != nil {
		return nil, err
	}

	// Filter out any models that are policy-disabled - normally CAPI already does this,
	// except we set `IgnoreModelPolicies` so that we can use a fallback "auto" model if needed.
	enabledModels := []capi.Model{}
	for _, model := range models {
		if model.Policy != nil && model.Policy.State == capi.ModelPolicyStateDisabled {
			continue
		}
		enabledModels = append(enabledModels, model)
	}

	// Prepend the "auto" model to the list
	return append([]capi.Model{AutoModel}, enabledModels...), nil
}
