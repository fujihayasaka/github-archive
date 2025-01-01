package llm

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/codeml-autofix/go/pkg/autofix/config"
	"github.com/github/codeml-autofix/go/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/models"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/provider"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/roundrobin"
	"go.opentelemetry.io/otel/codes"
)

// CAPI model flavors.
const (
	CAPIProd4O       = "capi-prod-4o"
	CAPIProdO3       = "capi-prod-o3"
	CAPIDev4O        = "capi-dev-4o"
	CAPIDev41        = "capi-dev-4.1"
	CAPIDev4OMini    = "capi-dev-4o-mini"
	CAPIDevO1        = "capi-dev-o1"
	CAPIDevO3        = "capi-dev-o3"
	CAPIDevO4Mini    = "capi-dev-o4-mini"
	CAPIDevO1Mini    = "capi-dev-o1-mini"
	CAPIDevClaude    = "capi-dev-claude-3.5-sonnet"
	CAPIDevGeminiPro = "capi-dev-gemini-1.5-pro"
)

// ChatGPT model flavors.
const (
	ChatGPT4      = "chatgpt-4"
	ChatGPT432k   = "chatgpt-4-32k"
	ChatGPT4Turbo = "chatgpt-4-turbo"
)

// GetModel creates an LLM instance with the specified configuration
func GetModel(ctx context.Context, modelName string, cfg *config.Config) (models.HashableModel, error) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.GetModel")
	defer span.End()

	if modelName == "" {
		err := fmt.Errorf("model name not specified")
		span.SetStatus(codes.Error, err.Error())
		enhancedctx.RecordSpanError(ctx, err)
		return nil, err
	}

	// Handle multiple models (round-robin)
	modelNames := strings.Split(modelName, ",")
	modelInstances := make([]models.HashableModel, 0, len(modelNames))

	registry, err := models.GetRegistry()
	if err != nil {
		return nil, fmt.Errorf("failed to initialize model registry: %w", err)
	}

	for _, name := range modelNames {
		model, err := getModelInternal(ctx, strings.TrimSpace(name), cfg, registry)
		if err != nil {
			return nil, fmt.Errorf("creating model %s: %w", name, err)
		}
		modelInstances = append(modelInstances, model)
	}

	var model models.HashableModel
	if len(modelInstances) == 1 {
		model = modelInstances[0]
	} else {
		model, err = roundrobin.NewRoundRobinModel(modelInstances)
		if err != nil {
			return nil, fmt.Errorf("creating round-robin model: %w", err)
		}
	}

	return model, nil
}

func getModelInternal(ctx context.Context, name string, cfg *config.Config, registry *models.ModelRegistry) (models.HashableModel, error) {
	switch {
	case strings.HasPrefix(name, "capi-"):
		flavor := provider.ModelFlavor(strings.TrimPrefix(name, "capi-"))
		return provider.NewClient(flavor, cfg, provider.WithRegistry(registry))

	case strings.HasPrefix(name, "chatgpt-"):
		flavor := provider.ChatGPTFlavor(name)
		clients, err := provider.MakeAIPClients(ctx, flavor, cfg.DefaultCompletionOptions, cfg)
		if err != nil {
			return nil, err
		}
		// Convert to interfaces
		models := make([]models.HashableModel, len(clients))
		for i, c := range clients {
			models[i] = c
		}

		if len(models) == 1 {
			return models[0], nil
		}
		return roundrobin.NewRoundRobinModel(models)

	default:
		// Try to look up in registry
		if model, found := registry.GetModelByFlavor(name); found {
			// Create appropriate client based on vendor
			switch {
			case strings.Contains(strings.ToLower(model.Vendor), "openai"):
				return provider.NewClient(provider.Dev4O, cfg)
			case strings.Contains(strings.ToLower(model.Vendor), "anthropic"):
				return provider.NewClient(provider.DevClaudeSonnet, cfg)
			}
		}
		return nil, fmt.Errorf("unknown model: %s", name)
	}
}
