// Package llm provides functionality to initialize and call LLM models from CAPI and other providers.
package llm

import (
	"context"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/llm/config"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/code-scanning-ai-libraries/v2/llm/provider"
	"github.com/github/code-scanning-ai-libraries/v2/llm/roundrobin"
	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/codes"
)

// GetModel creates an LLM instance with the specified configuration
func GetModel(ctx context.Context, modelName string, cfg *config.ModelConfig) (models.Model, error) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.GetModel")
	defer span.End()

	if modelName == "" {
		err := errors.New("model name not specified")
		span.SetStatus(codes.Error, err.Error())
		enhancedctx.RecordSpanError(ctx, err)
		return nil, err
	}

	// Handle multiple models (round-robin)
	modelNames := strings.Split(modelName, ",")
	modelInstances := make([]models.Model, 0, len(modelNames))

	registry, err := models.GetRegistry()
	if err != nil {
		return nil, st.EnsureStackTrace(err, "failed to initialize model registry")
	}

	for _, name := range modelNames {
		model, err := getModelInternal(ctx, strings.TrimSpace(name), cfg, registry)
		if err != nil {
			return nil, st.EnsureStackTracef(err, "creating model %s", name)
		}
		modelInstances = append(modelInstances, model)
	}

	var model models.Model
	if len(modelInstances) == 1 {
		model = modelInstances[0]
	} else {
		model, err = roundrobin.NewRoundRobinModel(modelInstances)
		if err != nil {
			return nil, st.EnsureStackTrace(err, "creating round-robin model")
		}
	}

	return model, nil
}

func getModelInternal(ctx context.Context, name string, cfg *config.ModelConfig, registry *models.ModelRegistry) (models.Model, error) {
	retry := cfg.Retry

	switch {
	case strings.HasPrefix(name, "capi-"):
		flavor := strings.TrimPrefix(name, "capi-")
		return provider.NewCapiClient(flavor, retry, cfg, provider.WithRegistry(registry))

	case strings.HasPrefix(name, "azure-"):
		modelName := strings.TrimPrefix(name, "azure-")
		clients, err := provider.MakeAIPClients(ctx, modelName, retry, cfg.DefaultCompletionOptions, cfg)
		if err != nil {
			return nil, err
		}
		// Convert to interfaces
		resultModels := make([]models.Model, len(clients))
		for i, c := range clients {
			resultModels[i] = c
		}

		if len(resultModels) == 1 {
			return resultModels[0], nil
		}
		return roundrobin.NewRoundRobinModel(resultModels)

	default:
		return nil, errors.Errorf("unknown model: %s", name)
	}
}
