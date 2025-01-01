package models

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/codeml-autofix/go/pkg/autofix"
)

// Model interface represents a language model that can generate text completions.
type Model interface {
	Complete(ctx context.Context, messages []ChatMessage) (string, autofix.AutofixError)
	CompleteWithOptions(ctx context.Context, messages []ChatMessage, options *CompletionOptions) (string, autofix.AutofixError)
	GetModelName() string
	GetModelGeneration() string
	GetContextSize() int
	GetMaxTokens() int
	GetEncodingName() string
	GetDefaultCompletionOptions() CompletionOptions
}

type HashableModel interface {
	Model
	Hash() (string, error)
}

type ChatMessageRole string

const (
	ChatMessageRoleUser      ChatMessageRole = "user"
	ChatMessageRoleAssistant ChatMessageRole = "assistant"
	ChatMessageRoleSystem    ChatMessageRole = "system"
)

type ChatMessage struct {
	Role    ChatMessageRole `json:"role"`
	Content string          `json:"content"`
}

func (c *ChatMessage) Hash() (string, error) {
	bytes, err := json.Marshal(c)
	if err != nil {
		return "", fmt.Errorf("failed to marshal chat message: %w", err)
	}
	return string(bytes), nil
}

type CompletionOptions struct {
	MaxTokens   int      `json:"max_tokens"`
	Temperature float64  `json:"temperature"`
	Stream      bool     `json:"stream"`
	Stop        []string `json:"stop,omitempty"`
}

func (c *CompletionOptions) Clone() *CompletionOptions {
	return &CompletionOptions{
		MaxTokens:   c.MaxTokens,
		Temperature: c.Temperature,
		Stream:      c.Stream,
		Stop:        append([]string{}, c.Stop...),
	}
}

func (c *CompletionOptions) Hash() (string, error) {
	bytes, err := json.Marshal(c)
	if err != nil {
		return "", fmt.Errorf("failed to marshal completion options: %w", err)
	}
	return string(bytes), nil
}

var DefaultCompletionOptions = CompletionOptions{
	MaxTokens:   1024,
	Temperature: 0.7,
	Stream:      false,
	Stop:        nil,
}

type ModelEntry struct {
	Capabilities       *ModelCapabilities `json:"capabilities"`
	ID                 string             `json:"id"`
	ModelPickerEnabled bool               `json:"model_picker_enabled"`
	Name               string             `json:"name"`
	Preview            bool               `json:"preview"`
	Vendor             string             `json:"vendor"`
	Version            string             `json:"version"`
}

type ModelCapabilities struct {
	Family    string         `json:"family"`
	Limits    *ModelLimits   `json:"limits"`
	Supports  *ModelSupports `json:"supports"`
	Tokenizer string         `json:"tokenizer"`
	Type      string         `json:"type"`
}

func (m *ModelCapabilities) Hash() (string, error) {
	bytes, err := json.Marshal(m)
	if err != nil {
		return "", fmt.Errorf("failed to marshal model capabilities: %w", err)
	}
	return string(bytes), nil
}

type ModelLimits struct {
	MaxContextWindowTokens int           `json:"max_context_window_tokens"`
	MaxOutputTokens        int           `json:"max_output_tokens"`
	MaxPromptTokens        int           `json:"max_prompt_tokens"`
	Vision                 *VisionLimits `json:"vision,omitempty"`
}

type VisionLimits struct {
	MaxPromptImages    int32 `json:"max_prompt_images"`
	MaxPromptImageSize int32 `json:"max_prompt_image_size"`
}

type ModelSupports struct {
	Streaming         bool `json:"streaming"`
	ToolCalls         bool `json:"tool_calls"`
	ParallelToolCalls bool `json:"parallel_tool_calls"`
	StructuredOutputs bool `json:"structured_outputs"`
	Vision            bool `json:"vision"`
}

type Options struct {
	ModelName                string
	DefaultCompletionOptions *CompletionOptions
	RetryOptions             struct {
		Enabled bool
	}
	CacheDir     string
	CacheVersion string
	Logger       interface{} // TODO: Define logger interface
}

func (o *CompletionOptions) ToMap() map[string]interface{} {
	m := map[string]interface{}{
		"max_tokens":  o.MaxTokens,
		"temperature": o.Temperature,
		"stream":      o.Stream,
	}
	if len(o.Stop) > 0 {
		m["stop"] = o.Stop
	}
	return m
}
