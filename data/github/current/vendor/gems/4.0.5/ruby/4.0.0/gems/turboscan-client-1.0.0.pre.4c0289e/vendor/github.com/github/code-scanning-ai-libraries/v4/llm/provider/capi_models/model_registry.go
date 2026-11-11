// Package capimodels provides utilities for reading LLM model capabilities and metadata.
package capimodels

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	ai_errors "github.com/github/code-scanning-ai-libraries/v4/errors"
	"github.com/github/code-scanning-ai-libraries/v4/st"
)

const (
	// DefaultCapiURL is the default base URL for the GitHub Copilot API
	DefaultCapiURL = "https://api.githubcopilot.com"
)

// ModelRegistry provides access to model capabilities by different identifiers
type ModelRegistry struct {
	models map[string]*ModelEntry
}

var (
	modelsHTTPClient = &http.Client{Timeout: 30 * time.Second}
)

// GetRegistry returns the global model registry, initializing if needed
func GetRegistry(ctx context.Context, baseURL string, headers map[string]string) (*ModelRegistry, ai_errors.LLMError) {
	endpoint := fmt.Sprintf("%s/models", strings.TrimRight(baseURL, "/"))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, http.NoBody)
	if err != nil {
		return nil, ai_errors.GenericFatalError{Err: st.EnsureStackTrace(err, "creating models request")}
	}

	for k, v := range headers {
		req.Header.Set(k, v)
	}

	resp, err := modelsHTTPClient.Do(req)
	if err != nil {
		return nil, ai_errors.WrapRetryableError(st.EnsureStackTrace(err, "calling models endpoint"), "fetching model registry", 5*time.Second)
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		message := fmt.Sprintf("unexpected status %d fetching model registry", resp.StatusCode)
		if len(body) > 0 {
			message = fmt.Sprintf("%s: %s", message, strings.TrimSpace(string(body)))
		}
		return nil, ai_errors.NewHTTPStatusError(resp.StatusCode, message, ai_errors.IsRetryableStatusCode(resp.StatusCode), 5*time.Second)
	}

	var list ModelList
	if err := json.NewDecoder(resp.Body).Decode(&list); err != nil {
		return nil, ai_errors.GenericFatalError{Err: st.EnsureStackTrace(err, "decoding model registry response")}
	}

	registry := &ModelRegistry{
		models: make(map[string]*ModelEntry, len(list.Data)),
	}
	for i := range list.Data {
		model := &list.Data[i]
		registry.models[model.ID] = model
	}

	return registry, nil
}

// GetModel finds the model capabilities by any supported identifier
func (r *ModelRegistry) GetModel(modelName string) (*ModelEntry, bool) {
	// Check if this is an exact model ID
	model, found := r.models[modelName]
	if found {
		return model, true
	}

	// No match found
	return nil, false
}

// ModelEntry represents a model configuration entry.
type ModelEntry struct {
	Capabilities       *ModelCapabilities `json:"capabilities"`
	ID                 string             `json:"id"`
	ModelPickerEnabled bool               `json:"model_picker_enabled"`
	Name               string             `json:"name"`
	Preview            bool               `json:"preview"`
	Vendor             string             `json:"vendor"`
	Version            string             `json:"version"`
	SupportedEndpoints *[]string          `json:"supported_endpoints,omitempty"`
}

// ModelCapabilities defines the capabilities and limitations of a model.
type ModelCapabilities struct {
	Family    string         `json:"family"`
	Limits    *ModelLimits   `json:"limits"`
	Supports  *ModelSupports `json:"supports"`
	Tokenizer string         `json:"tokenizer"`
	Type      string         `json:"type"`
}

// ModelLimits defines the token and context limits for a model.
type ModelLimits struct {
	MaxContextWindowTokens int           `json:"max_context_window_tokens"`
	MaxOutputTokens        int           `json:"max_output_tokens"`
	MaxPromptTokens        int           `json:"max_prompt_tokens"`
	Vision                 *VisionLimits `json:"vision,omitempty"`
}

// VisionLimits defines the limits for vision-related model capabilities.
type VisionLimits struct {
	MaxPromptImages    int32 `json:"max_prompt_images"`
	MaxPromptImageSize int32 `json:"max_prompt_image_size"`
}

// ModelSupports defines which features a model supports.
type ModelSupports struct {
	Streaming         bool `json:"streaming"`
	ToolCalls         bool `json:"tool_calls"`
	ParallelToolCalls bool `json:"parallel_tool_calls"`
	StructuredOutputs bool `json:"structured_outputs"`
	Vision            bool `json:"vision"`
}

// ModelList represents a list of available models returned by the `/models` endpoint.
type ModelList struct {
	Data   []ModelEntry `json:"data"`
	Object string       `json:"object"`
}
