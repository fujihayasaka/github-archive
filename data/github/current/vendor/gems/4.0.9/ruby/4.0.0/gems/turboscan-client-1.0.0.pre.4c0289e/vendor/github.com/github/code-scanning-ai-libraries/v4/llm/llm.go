// Package llm provides functionality to initialize and call LLM models from CAPI and other providers.
package llm

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"
	"sync"

	"github.com/github/code-scanning-ai-libraries/v4/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v4/llm/config"
	"github.com/github/code-scanning-ai-libraries/v4/llm/models"
	"github.com/github/code-scanning-ai-libraries/v4/llm/provider"
	"github.com/github/code-scanning-ai-libraries/v4/llm/roundrobin"
	"github.com/github/code-scanning-ai-libraries/v4/st"
	lru "github.com/hashicorp/golang-lru/v2"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/codes"
)

// modelCacheCapacity is the maximum number of model entries to cache. We cache in an LRU to avoid a potential memory leak in the future, in case a big number of configurations are used over time.
const modelCacheCapacity = 100

var (
	// modelCache uses a combined key of model name and config hash to store model instances.
	modelCache, _ = lru.New[string, models.Model](modelCacheCapacity)
	cacheMu       sync.Mutex
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

	cacheKey, err := getModelCacheKey(modelName, cfg)
	if err != nil {
		return nil, err
	}

	cacheMu.Lock()
	defer cacheMu.Unlock()

	if model, ok := modelCache.Get(cacheKey); ok {
		return model, nil
	}

	// Handle multiple models with load balancing
	modelNames := strings.Split(modelName, ",")
	modelInstances := make([]models.Model, 0, len(modelNames))

	for _, name := range modelNames {
		model, err := getModelInternal(ctx, strings.TrimSpace(name), cfg)
		if err != nil {
			return nil, st.EnsureStackTracef(err, "creating model %s", name)
		}
		modelInstances = append(modelInstances, model)
	}

	var model models.Model
	if len(modelInstances) == 1 {
		model = modelInstances[0]
	} else {
		var err error
		model, err = roundrobin.NewRoundRobinModel(modelInstances)
		if err != nil {
			return nil, st.EnsureStackTrace(err, "creating round-robin model")
		}
	}

	// Update cache
	modelCache.Add(cacheKey, model)

	return model, nil
}

func getModelInternal(ctx context.Context, name string, cfg *config.ModelConfig) (models.Model, error) {
	retry := cfg.Retry

	switch {
	case strings.HasPrefix(name, "capi-"):
		flavor := strings.TrimPrefix(name, "capi-")
		return provider.NewCapiClient(ctx, flavor, retry, cfg, getCAPIClientOptions(ctx)...)

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

	case strings.HasPrefix(name, "vllm-"):
		modelName := strings.TrimPrefix(name, "vllm-")
		return createVLLMClient(modelName, retry, cfg)

	default:
		return nil, errors.Errorf("unknown model: %s", name)
	}
}

type capiClientOptionsKey struct{}

// WithCAPIClientOptions stores provider.ClientOptions in the supplied context so they are used when creating
// CAPI clients via GetModel. This is primarily useful for tests to inject mock registries.
func WithCAPIClientOptions(ctx context.Context, opts ...provider.ClientOption) context.Context {
	if len(opts) == 0 {
		return ctx
	}

	existing := getCAPIClientOptions(ctx)
	combined := make([]provider.ClientOption, 0, len(existing)+len(opts))
	combined = append(combined, existing...)
	combined = append(combined, opts...)

	return context.WithValue(ctx, capiClientOptionsKey{}, combined)
}

func getCAPIClientOptions(ctx context.Context) []provider.ClientOption {
	if ctx == nil {
		return nil
	}

	if opts, ok := ctx.Value(capiClientOptionsKey{}).([]provider.ClientOption); ok {
		// Return a copy to avoid accidental mutation by callers.
		return append([]provider.ClientOption(nil), opts...)
	}

	return nil
}

// ClearModelCache clears the model cache. This is intended for testing only.
func ClearModelCache() {
	cacheMu.Lock()
	defer cacheMu.Unlock()
	modelCache.Purge()
}

// ModelCacheLen returns the number of entries in the model cache. This is intended for testing only.
func ModelCacheLen() int {
	cacheMu.Lock()
	defer cacheMu.Unlock()
	return modelCache.Len()
}

func getModelCacheKey(modelName string, cfg *config.ModelConfig) (string, error) {
	payload := struct {
		ModelName string              `json:"model_name"`
		Config    *config.ModelConfig `json:"config"`
	}{
		ModelName: modelName,
		Config:    cfg,
	}

	bytes, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	sum := sha256.Sum256(bytes)
	return hex.EncodeToString(sum[:]), nil
}

// createVLLMClient creates a vLLM client with the specified model name and configuration
func createVLLMClient(modelName string, retry bool, cfg *config.ModelConfig) (models.Model, error) {
	if cfg.VLLMBaseURL == "" {
		return nil, errors.New("vLLM base URL not configured (set VLLM_BASE_URL)")
	}

	opts := []provider.VLLMClientOption{
		provider.WithVLLMBaseURL(cfg.VLLMBaseURL),
		provider.WithVLLMModelName(modelName),
	}

	if cfg.VLLMAPIKey != "" {
		opts = append(opts, provider.WithVLLMAPIKey(cfg.VLLMAPIKey))
	}

	// Default to using /chat/completions API if not explicitly set
	useResponsesAPI := false
	if cfg.VLLMUseResponsesAPI != nil {
		useResponsesAPI = *cfg.VLLMUseResponsesAPI
	}
	opts = append(opts, provider.WithVLLMUseResponsesAPI(useResponsesAPI))

	if cfg.DefaultCompletionOptions != nil {
		opts = append(opts, provider.WithVLLMDefaultOptions(cfg.DefaultCompletionOptions))
	}

	return provider.NewVLLMClient(retry, opts...), nil
}
