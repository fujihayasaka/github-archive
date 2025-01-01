package models

import (
	"context"
	"encoding/json"
	"regexp"

	"github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/code-scanning-ai-libraries/v2/st"
)

// Model interface represents a language model that can generate text completions.
type Model interface {
	Complete(ctx context.Context, messages []ChatMessage, tools []Tool, options *CompletionOptions) (string, []ChatMessage, *TokenUsage, errors.LLMError)
	GetModelName() string
	GetProviderName() string // Returns the provider name, e.g. "CAPI", "ChatGPT", "Azure OpenAI", etc. Is used to provide a unique cache-key for model requests.
}

// GetPrettyModelName returns a human-friendly model name by stripping any
// decorator wrappers (e.g. `Logging<Caching<Retry<o3>>>` → `o3`).
func GetPrettyModelName(m Model) string {
	modelName := m.GetModelName()

	// Use regex to capture the innermost model name.
	re := regexp.MustCompile(`^.*<([^<>]+)>.*$`)
	if matches := re.FindStringSubmatch(modelName); len(matches) == 2 {
		return matches[1]
	}
	return modelName
}

// ChatMessageRole represents the role of a message in a chat conversation.
type ChatMessageRole string

// Chat message roles
const (
	ChatMessageRoleUser      ChatMessageRole = "user"
	ChatMessageRoleAssistant ChatMessageRole = "assistant"
	ChatMessageRoleSystem    ChatMessageRole = "system"
)

// CopilotCacheControl defines model for copilot_cache_control.
// see https://github.com/github/copilot/blob/c525b4e44ce1f13018783d828633c65bc26da82a/docs/adrs/0050-prompt-caching-for-copilot-api.md
// for more details.
type CopilotCacheControl struct {
	Type CacheControlType `json:"type"`
}

// CacheControlType defines model for copilot_cache_control.type.
// At the time of writing, the only supported type is "ephemeral".
type CacheControlType string

// ChatMessage represents a message in a chat conversation.
type ChatMessage struct {
	ID                  string               `json:"id,omitempty"`                    // Optional ID for the message
	Role                ChatMessageRole      `json:"role,omitempty"`                  // Role of the message (user, assistant, system)
	Content             string               `json:"content,omitempty"`               // Content of the message
	Type                string               `json:"type,omitempty"`                  // Optional type for the message
	EncryptedContent    string               `json:"encrypted_content,omitempty"`     // Optional encrypted content for the message. See https://platform.openai.com/docs/guides/reasoning/how-reasoning-works?api-mode=responses#encrypted-reasoning-items
	CopilotCacheControl *CopilotCacheControl `json:"copilot_cache_control,omitempty"` // Copilot cache control

	// tool calling fields (Responses API)
	CallID    string `json:"call_id,omitempty"`   // Optional ID for tool calls
	Arguments string `json:"arguments,omitempty"` // Optional arguments for tool calls
	Output    string `json:"output,omitempty"`    // Optional output from tool calls
	Name      string `json:"name,omitempty"`      // Optional name for the tool call

	// Reasoning section fields
	Summary *[]SummaryItem `json:"summary,omitempty"` // Optional summary for reasoning sections. This field is a pointer so there is a difference between empty and nil.

	// Tool calling with the Chat Completions API
	ToolCallID string `json:"tool_call_id,omitempty"` // Optional ID for the tool call
	ToolCalls  *[]struct {
		ID       string `json:"id,omitempty"`   // Unique identifier for the tool call
		Type     string `json:"type,omitempty"` // Type of the tool call (e.g., "function")
		Function struct {
			Name      string `json:"name,omitempty"`      // Name of the function to call
			Arguments string `json:"arguments,omitempty"` // JSON-encoded arguments for the function
		} `json:"function,omitempty"` // Function details for the tool call
	} `json:"tool_calls,omitempty"` // Optional tool calls made by the model
}

// SummaryItem represents a summary of a chunk of reasoning from a reasoning model.
type SummaryItem struct {
	Text string `json:"text,omitempty"` // Text content of the summary
	Type string `json:"type,omitempty"` // Type of the summary (e.g., "summary_text")
}

// UnmarshalJSON implements json.Unmarshaler for ChatMessage.
// We need custom logic to handle the `content` JSON field being either a string, or an array of JSON objects.
func (c *ChatMessage) UnmarshalJSON(data []byte) error {
	// Define a type alias to avoid infinite recursion
	type Alias ChatMessage
	aux := &struct {
		Content json.RawMessage `json:"content,omitempty"`
		*Alias
	}{
		Alias: (*Alias)(c),
	}

	if err := json.Unmarshal(data, aux); err != nil {
		return err
	}

	// Handle the content field
	if len(aux.Content) > 0 {
		// First try to unmarshal as a simple string
		var stringContent string
		if err := json.Unmarshal(aux.Content, &stringContent); err == nil {
			c.Content = stringContent
			return nil
		}

		// If that fails, try to unmarshal as an array of content objects
		// This is sometimes returned by the API, but we don't want to store the transcript that way.
		// The object is expected to look like the `output_message` specification here: https://github.com/github/copilot-api/blob/main/docs/api/schema.md#output_message
		var contentArray []struct {
			Text string `json:"text"`
			Type string `json:"type"`
		}
		if err := json.Unmarshal(aux.Content, &contentArray); err == nil {
			// Extract text from the first output_text item
			for _, item := range contentArray {
				if item.Type == "output_text" && item.Text != "" {
					c.Content = item.Text
					break
				}
			}
		}
	}

	return nil
}

// Hash returns a hash string representation of the chat message.
func (c *ChatMessage) Hash() (string, error) {
	bytes, err := json.Marshal(c)
	if err != nil {
		return "", st.EnsureStackTrace(err, "failed to marshal chat message")
	}
	return string(bytes), nil
}

// CompletionOptions contains parameters for text completion requests.
// The `ToMap` method converts these options into a map suitable as headers in an API request.
// Every field is optional, and a default `CompletionOptions{}` can be used to represent no options (and `ToMap()` will return an empty map).
type CompletionOptions struct {
	Temperature        *float64 `json:"temperature,omitempty"`
	Stream             *bool    `json:"stream,omitempty"`
	Stop               []string `json:"stop,omitempty"`
	INTERNAL_CACHE_KEY string   `json:"INTERNAL_CACHE_KEY,omitempty"` //nolint:revive,stylecheck // Internal use only, not part of the API. Used to use different cache keys for multiple iterations of the same request.
	ReasoningEffort    string   `json:"reasoning_effort,omitempty"`   // Optional reasoning effort level, e.g. "high", "medium", "low". "minimal" is also supported, but only on GPT-5.
	Verbosity          string   `json:"verbosity,omitempty"`          // Optional verbosity level, e.g. "low", "medium", "high". Only supported for newer Responses API models.
}

// Clone creates a deep copy of the completion options.
func (c *CompletionOptions) Clone() *CompletionOptions {
	var temperature *float64
	if c.Temperature != nil {
		tempCopy := *c.Temperature
		temperature = &tempCopy
	}
	var stream *bool
	if c.Stream != nil {
		streamCopy := *c.Stream
		stream = &streamCopy
	}

	return &CompletionOptions{
		Temperature:        temperature,
		Stream:             stream,
		Stop:               append([]string{}, c.Stop...),
		INTERNAL_CACHE_KEY: c.INTERNAL_CACHE_KEY,
		ReasoningEffort:    c.ReasoningEffort,
		Verbosity:          c.Verbosity,
	}
}

// Hash returns a hash string representation of the completion options.
func (c *CompletionOptions) Hash() (string, error) {
	bytes, err := json.Marshal(c)
	if err != nil {
		return "", st.EnsureStackTrace(err, "failed to marshal completion options")
	}
	return string(bytes), nil
}

// MkDefaultCompletionOptions provides zero values for completion requests, allowing the API to use its own defaults.
func MkDefaultCompletionOptions() *CompletionOptions {
	return &CompletionOptions{}
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

// addSharedOptions adds options that are common across endpoints.
func (c *CompletionOptions) addSharedOptions(m map[string]any) {
	if c.Stream != nil {
		m["stream"] = *c.Stream
	}
	if c.Temperature != nil {
		m["temperature"] = *c.Temperature
	}
	if len(c.Stop) > 0 {
		m["stop"] = c.Stop
	}
}

// ToChatCompletionsMap converts completion options to a map for API requests.
func (c *CompletionOptions) ToChatCompletionsMap(ctx context.Context) map[string]any {
	// purposely not copying the `INTERNAL_CACHE_KEY` field as it is not part of the API request. But `INTERNAL_CACHE_KEY` is used in the hash.
	m := map[string]any{}
	c.addSharedOptions(m)
	if c.ReasoningEffort != "" {
		m["reasoning_effort"] = c.ReasoningEffort // Note: This is silently ignored on most integrations in CAPI!
	}
	if c.Verbosity != "" {
		logger := enhancedctx.Logger(ctx)
		logger.Warn("verbosity is not currently supported when using Chat Completions")
	}

	return m
}

// ToResponsesMap converts completion options to a map for the Responses API.
func (c *CompletionOptions) ToResponsesMap() map[string]any {
	m := map[string]any{}
	c.addSharedOptions(m)

	// "stop" is not supported with the Responses API

	if c.ReasoningEffort != "" {
		m["reasoning"] = map[string]any{
			"effort": c.ReasoningEffort,
		}
	}

	if c.Verbosity != "" {
		m["text"] = map[string]any{
			"verbosity": c.Verbosity,
		}
	}
	return m
}
