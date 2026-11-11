package capi

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"slices"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/joberrors"
)

const (
	// AutoMode represents the automatic model selection mode. It is also used as the ID
	// for the "Auto" model in the model picker.
	AutoMode = "auto"

	// ClaudeOpus45 is the Anthropic Claude Opus 4.5 model.
	ClaudeOpus45 = "claude-opus-4.5"
	// ClaudeSonnet45 is the Anthropic Claude Sonnet 4.5 model.
	ClaudeSonnet45 = "claude-sonnet-4.5"

	// GPT51CodexMax is the OpenAI GPT 5.1 Codex Max model.
	GPT51CodexMax = "gpt-5.1-codex-max"

	// GPT52Codex is the OpenAI GPT 5.2 Codex model.
	GPT52Codex = "gpt-5.2-codex"

	// Gemini3ProPreview is the Google Gemini 3 Pro Preview model.
	Gemini3ProPreview = "gemini-3-pro-preview"

	// OsweMagpie is the OSWE Magpie model.
	OsweMagpie = "oswe-magpie"
)

// CodingAgentModelIDs is the list of model IDs that we allow to be selected for copilot coding agent.
// This is a subset of all models available to the user via CAPI.
var CodingAgentModelIDs = []string{
	ClaudeOpus45,
	ClaudeSonnet45,
	GPT51CodexMax,
	GPT52Codex,
	OsweMagpie,
}

// Model defines the type for a model. We're not importing CAPI's actual type here as it
// depends on deep dependencies we don't need (like azopenai). This is a simplified version
// of the model type defined in CAPI's schema package.
type Model struct {
	Auto         *bool              `json:"auto,omitempty"`
	Billing      *ModelBilling      `json:"billing,omitempty"`
	Capabilities *ModelCapabilities `json:"capabilities,omitempty"`

	// CustomModel Additional metadata for BYOK (Bring Your Own Key) custom models.
	CustomModel *ModelCustomModel `json:"custom_model,omitempty"`
	ID          string            `json:"id"`

	// InfoMessages Used for displaying temporary info messages to the user about the model. i.e. when the model is pending deprecation
	InfoMessages   *[]InfoMessage `json:"info_messages,omitempty"`
	IsChatDefault  *bool          `json:"is_chat_default,omitempty"`
	IsChatFallback *bool          `json:"is_chat_fallback,omitempty"`

	// ModelPickerCategory Optional category for the model, typically only populated for models where ModelPickerEnabled is true. Categories: 'lightweight' for fast and cost-efficient models, 'versatile' for balanced models, 'powerful' for most capable models. **Note:** Clients should be resilient to additional categories being added in the future.
	ModelPickerCategory *string      `json:"model_picker_category,omitempty"`
	ModelPickerEnabled  *bool        `json:"model_picker_enabled,omitempty"`
	Name                string       `json:"name"`
	Object              string       `json:"object"`
	Policy              *ModelPolicy `json:"policy,omitempty"`
	Preview             *bool        `json:"preview,omitempty"`
	SupportedEndpoints  *[]string    `json:"supported_endpoints,omitempty"`
	Vendor              *string      `json:"vendor,omitempty"`
	Version             string       `json:"version"`

	// WarningMessage Used for displaying a temporary warning message to the user about the model. i.e when model is in degraded state
	WarningMessage *string `json:"warning_message,omitempty"`

	// WarningMessages Used for displaying temporary warning messages to the user about the model. i.e when model is in degraded state or in high usage
	WarningMessages *[]WarningMessage `json:"warning_messages,omitempty"`
}

// ModelBilling defines billing configuration for a model
type ModelBilling struct {
	// IsPremium A value indicating whether or not this model is a premium model.
	IsPremium bool `json:"is_premium"`

	// Multiplier A multiplier for billing calculations, allowing for fractional values.
	Multiplier   float64  `json:"multiplier"`
	RestrictedTo []string `json:"restricted_to,omitempty"`
}

// ModelCapabilities defines the capabilities of a model
type ModelCapabilities struct {
	Family    string       `json:"family"`
	Limits    *ModelLimits `json:"limits,omitempty"`
	Object    string       `json:"object"`
	Supports  Supports     `json:"supports"`
	Tokenizer string       `json:"tokenizer"`
	Type      string       `json:"type"`
}

// ModelCustomModel Additional metadata for BYOK (Bring Your Own Key) custom models.
type ModelCustomModel struct {
	// KeyName The API key name for the custom model.
	KeyName *string `json:"key_name,omitempty"`

	// OwnerName The owner username for the custom model, such as the name of the organization or enterprise that owns the custom model.
	OwnerName *string `json:"owner_name,omitempty"`

	// Provider The type of provider for the custom model, such as `azureai`, `openai` or `anthropic`. This value may be used to find an appropriate icon.
	Provider *string `json:"provider,omitempty"`
}

// ModelLimits defines limits for a model
type ModelLimits struct {
	// MaxContextWindowTokens The maximum context window this model is inherently capable of supporting.
	MaxContextWindowTokens int32 `json:"max_context_window_tokens,omitempty"`

	// MaxInputs The maximum number of inputs this embedding model supports per request.
	MaxInputs int32 `json:"max_inputs,omitempty"`

	// MaxOutputTokens The maximum number of response tokens this chat model is allowed to use in CAPI.
	MaxOutputTokens int32 `json:"max_output_tokens,omitempty"`

	// MaxPromptTokens The maximum number of tokens this chat model is allowed to use in CAPI.
	MaxPromptTokens int32 `json:"max_prompt_tokens,omitempty"`

	// Vision Limits around the use of vision capabilities in this model.
	Vision *ModelVisionLimits `json:"vision,omitempty"`
}

// ModelPolicy defines policy information for a model
type ModelPolicy struct {
	State ModelPolicyState `json:"state,omitempty"`
	Terms *string          `json:"terms,omitempty"`
}

// ModelPolicyState represents the state of a model policy.
type ModelPolicyState string

const (
	// ModelPolicyStateDisabled indicates that the model is disabled by policy.
	ModelPolicyStateDisabled ModelPolicyState = "disabled"
	// ModelPolicyStateEnabled indicates that the model is enabled by policy.
	ModelPolicyStateEnabled ModelPolicyState = "enabled"
	// ModelPolicyStateUnconfigured indicates that the model is unconfigured.
	ModelPolicyStateUnconfigured ModelPolicyState = "unconfigured"
)

// ModelVisionLimits Limits around the use of vision capabilities in this model.
type ModelVisionLimits struct {
	// MaxPromptImageSize The maximum size of an image this chat model is allowed to use in CAPI.
	MaxPromptImageSize int32 `json:"max_prompt_image_size,omitempty"`

	// MaxPromptImages The maximum number of images this chat model is allowed to use in CAPI.
	MaxPromptImages     int32     `json:"max_prompt_images,omitempty"`
	SupportedMediaTypes *[]string `json:"supported_media_types,omitempty"`
}

// Supports defines what features a model supports
type Supports struct {
	// Dimensions A value indicating whether or not this model supports configurable output dimensions.
	Dimensions bool `json:"dimensions,omitempty"`

	// MaxThinkingBudget The maximum allowable value to be used for the thinking_budget parameter.
	MaxThinkingBudget int32 `json:"max_thinking_budget,omitempty"`

	// MinThinkingBudget The minimum allowable value to be used for the thinking_budget parameter.
	MinThinkingBudget int32 `json:"min_thinking_budget,omitempty"`

	// ParallelToolCalls A value indicating whether or not this model supports parallel tool calls.
	ParallelToolCalls bool `json:"parallel_tool_calls,omitempty"`

	// Streaming A value indicating whether or not this model supports streaming.
	Streaming bool `json:"streaming,omitempty"`

	// StructuredOutputs A value indicating whether or not this model supports structured outputs.
	StructuredOutputs bool `json:"structured_outputs,omitempty"`

	// ToolCalls A value indicating whether or not this model supports tool calls.
	ToolCalls bool `json:"tool_calls,omitempty"`

	// Vision A value indicating whether or not this model supports vision capabilities.
	Vision bool `json:"vision,omitempty"`
}

// InfoMessage represents an informational message about a model
type InfoMessage struct {
	// Code A machine-readable code identifying the type of info message communicated.
	Code    *string `json:"code,omitempty"`
	Message *string `json:"message,omitempty"`
}

// WarningMessage represents a warning message about a model
type WarningMessage struct {
	// Code A machine-readable code identifying the type of warning message communicated.
	Code    *string `json:"code,omitempty"`
	Message *string `json:"message,omitempty"`
}

// ListCodingAgentModels retrieves the list of models available for Copilot Coding Agent - a subset of all models.
func (c *HmacClient) ListCodingAgentModels(ctx context.Context, userID uint64) ([]Model, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.ListCodingAgentModels")
	defer span.End()

	modelsResp, err := c.listModels(ctx, userID)
	if err != nil {
		return nil, goerrors.Errorf("failed to list models: %w", err)
	}

	// Filter models to only include coding agent models
	filteredModels := []Model{}
	for _, model := range modelsResp.Data {
		// Check if model.ID is in CodingAgentModelIDs.
		// We could use a fancy hash set here, but the list is small and this is simpler.
		if slices.Contains(CodingAgentModelIDs, model.ID) {
			filteredModels = append(filteredModels, model)
		}
	}

	return filteredModels, nil
}

type listModelsResponse struct {
	Data   []Model `json:"data"`
	Object string  `json:"object"`
}

// listModels retrieves the list of available models from the Copilot API. This calls CAPI's /models endpoint,
// which honors the user's access to models, including policy restrictions.
func (c *HmacClient) listModels(ctx context.Context, userID uint64) (*listModelsResponse, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "capi.listModels")
	defer span.End()

	u := c.baseURL
	u.Path = "/models"

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), http.NoBody)
	if err != nil {
		return nil, err
	}

	req.Header.Set(GitHubUserIDHeader, fmt.Sprintf("%d", userID))

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, goerrors.WithStack(joberrors.NewCAPIError(resp, "unexpected status code from /models endpoint"))
	}

	var modelsResp listModelsResponse
	err = json.NewDecoder(resp.Body).Decode(&modelsResp)
	if err != nil {
		return nil, goerrors.Errorf("failed to decode response: %w", err)
	}

	return &modelsResp, nil
}
