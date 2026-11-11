package models

import (
	"context"
	"encoding/json"
	"regexp"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v3/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v3/errors"
	"github.com/github/code-scanning-ai-libraries/v3/st"
	"github.com/github/github-telemetry-go/kvp"
)

var prettyModelNameRegex = regexp.MustCompile(`^.*<([^<>]+)>.*$`)

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
	if matches := prettyModelNameRegex.FindStringSubmatch(modelName); len(matches) == 2 {
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
	ReasoningText       string               `json:"reasoning_text,omitempty"`        // Optional reasoning text for Anthropic/Gemini reasoning models used through CAPI. See https://github.com/github/copilot-api/blob/main/docs/api/schema.md
	ReasoningOpaque     string               `json:"reasoning_opaque,omitempty"`      // Optional reasoning opaque for Anthropic/Gemini reasoning models used through CAPI

	// tool calling fields (Responses API)
	CallID    string `json:"call_id,omitempty"`   // Optional ID for tool calls
	Arguments string `json:"arguments,omitempty"` // Optional arguments for tool calls
	Input     string `json:"input,omitempty"`     // Same as above, but for custom tool calls.
	Output    string `json:"output,omitempty"`    // Optional output from tool calls
	Name      string `json:"name,omitempty"`      // Optional name for the tool call

	// Reasoning section fields
	Summary *[]SummaryItem `json:"summary,omitempty"` // Optional summary for reasoning sections. This field is a pointer so there is a difference between empty and nil.

	// Tool calling with the Chat Completions API
	ToolCallID string      `json:"tool_call_id,omitempty"` // Optional ID for the tool call
	ToolCalls  *[]ToolCall `json:"tool_calls,omitempty"`   // Optional tool calls made by the model
}

// ToolCall represents a single tool/function call made by the model
type ToolCall struct {
	Index    *int   `json:"index,omitempty"` // Optional index for streaming tool call deltas
	ID       string `json:"id,omitempty"`    // Unique identifier for the tool call
	Type     string `json:"type,omitempty"`  // Type of the tool call (e.g., "function")
	Function struct {
		Name      string `json:"name,omitempty"`      // Name of the function to call
		Arguments string `json:"arguments,omitempty"` // JSON-encoded arguments for the function
	} `json:"function,omitempty"` // Function details for the tool call
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

// JITInstructionRule defines a single threshold-instruction mapping
type JITInstructionRule struct {
	ID               string   `json:"id"`                            // Unique identifier for this rule
	TokenThreshold   int      `json:"token_threshold"`               // Threshold to trigger these instructions
	Instructions     []string `json:"instructions"`                  // Instructions to inject when threshold is met
	Description      string   `json:"description,omitempty"`         // Optional description for logging/debugging
	InjectInToolCall bool     `json:"inject_in_tool_call,omitempty"` // When true, inject into last tool output instead of new user message
}

// JITInstructionConfig defines multiple threshold-based instruction sets
type JITInstructionConfig struct {
	Rules []JITInstructionRule `json:"rules,omitempty"` // List of threshold-based rules
	// Internal tracking (not serialized)
	injectedRuleIDs map[string]bool // Track which rules have been injected
}

// HasBeenInjected checks if a rule has already been injected
func (config *JITInstructionConfig) HasBeenInjected(ruleID string) bool {
	if config.injectedRuleIDs == nil {
		return false
	}
	return config.injectedRuleIDs[ruleID]
}

// MarkAsInjected marks a rule as having been injected
func (config *JITInstructionConfig) MarkAsInjected(ruleID string) {
	if config.injectedRuleIDs == nil {
		config.injectedRuleIDs = make(map[string]bool)
	}
	config.injectedRuleIDs[ruleID] = true
}

// GetHighestApplicableRule returns the rule with the highest token threshold that should be injected.
// It marks the highest applicable rule as injected and also marks all other applicable rules
// with lower token thresholds as injected to prevent them from being injected in the future.
func (config *JITInstructionConfig) GetHighestApplicableRule(totalTokens int) *JITInstructionRule {
	if config == nil {
		return nil
	}

	var highest *JITInstructionRule
	var applicableRules []JITInstructionRule

	// Find all applicable rules
	for _, rule := range config.Rules {
		if totalTokens >= rule.TokenThreshold && !config.HasBeenInjected(rule.ID) {
			applicableRules = append(applicableRules, rule)
			if highest == nil || rule.TokenThreshold > highest.TokenThreshold {
				// Make a copy to avoid pointer issues
				ruleCopy := rule
				highest = &ruleCopy
			}
		}
	}

	// If we found a highest rule, mark it and all lower threshold applicable rules as injected
	if highest != nil {
		for _, rule := range applicableRules {
			if rule.TokenThreshold <= highest.TokenThreshold {
				config.MarkAsInjected(rule.ID)
			}
		}
	}

	return highest
}

// GetInjectedRuleIDs returns the list of rule IDs that have been injected
func (config *JITInstructionConfig) GetInjectedRuleIDs() []string {
	if config.injectedRuleIDs == nil {
		return nil
	}

	var injected []string
	for ruleID, wasInjected := range config.injectedRuleIDs {
		if wasInjected {
			injected = append(injected, ruleID)
		}
	}
	return injected
}

// NewJITInstructionConfig creates a new JIT instruction config with common patterns
func NewJITInstructionConfig(rules []JITInstructionRule) *JITInstructionConfig {
	return &JITInstructionConfig{
		Rules:           rules,
		injectedRuleIDs: make(map[string]bool),
	}
}

// InjectInstructionsAfterToolCalls applies JIT instructions to a conversation transcript after tool calls.
// It returns a modified copy of the messages with instructions injected according to the highest applicable rule.
// The tokenCount is used to determine which rule(s) to apply based on their thresholds.
// The logger is used to record which rule was applied - pass nil to skip logging.
func (config *JITInstructionConfig) InjectInstructionsAfterToolCalls(
	ctx context.Context,
	messages []ChatMessage,
	tokenCount int,
) []ChatMessage {
	if config == nil {
		return messages
	}

	highestRule := config.GetHighestApplicableRule(tokenCount)
	if highestRule == nil {
		return messages
	}

	instructionText := strings.Join(highestRule.Instructions, "\n")

	if highestRule.InjectInToolCall {
		// Inject into the last message (which should be a tool-related message after tool calls)
		if len(messages) > 0 {
			lastIndex := len(messages) - 1
			lastMsg := messages[lastIndex]
			// Check for Responses API format (Type field) or Chat Completions format (Role field)
			if (lastMsg.Type == "function_call_output") ||
				(lastMsg.Role == "tool") {
				if lastMsg.Type == "function_call_output" {
					// Responses API format - inject into Output field
					lastMsg.Output += "\n\n" + instructionText
				} else {
					// Chat Completions format - inject into Content field
					lastMsg.Content += "\n\n" + instructionText
				}
				// Update the slice with the modified copy
				messages[lastIndex] = lastMsg
			}
		}
	} else {
		// Original behavior: inject as a new user message
		jitMessage := ChatMessage{
			Role:    ChatMessageRoleUser,
			Content: instructionText,
			Type:    "message",
		}
		messages = append(messages, jitMessage)
	}

	enhancedctx.Logger(ctx).Info("Injected JIT instructions", []kvp.Field{
		kvp.String("rule_id", highestRule.ID),
		kvp.String("rule_description", highestRule.Description),
		kvp.Int("token_usage", tokenCount),
		kvp.Int("threshold", highestRule.TokenThreshold),
		kvp.Int("num_instructions", len(highestRule.Instructions)),
		kvp.Bool("inject_in_tool_call", highestRule.InjectInToolCall),
	}...)

	return messages
}

// CompletionOptions contains parameters for text completion requests.
// The `ToMap` method converts these options into a map suitable as headers in an API request.
// Every field is optional, and a default `CompletionOptions{}` can be used to represent no options (and `ToMap()` will return an empty map).
type CompletionOptions struct {
	Temperature        *float64              `json:"temperature,omitempty"`
	Stream             *bool                 `json:"stream,omitempty"`
	Stop               []string              `json:"stop,omitempty"`
	MaxTurns           *int                  `json:"max_turns,omitempty"`          // Optional maximum number of model calls (turns) allowed in a single Complete lifecycle (including tool-call recursion)
	INTERNAL_CACHE_KEY string                `json:"INTERNAL_CACHE_KEY,omitempty"` //nolint:revive,stylecheck // Internal use only, not part of the API. Used to use different cache keys for multiple iterations of the same request.
	ReasoningEffort    string                `json:"reasoning_effort,omitempty"`   // Optional reasoning effort level, e.g. "high", "medium", "low". "minimal" is also supported, but only on GPT-5.
	Verbosity          string                `json:"verbosity,omitempty"`          // Optional verbosity level, e.g. "low", "medium", "high". Only supported for newer Responses API models.
	JITInstructions    *JITInstructionConfig `json:"jit_instructions,omitempty"`   //  Optional JIT instruction fields
	ThinkingBudget     int                   `json:"thinking_budget,omitempty"`    // Optional thinking budget in tokens. Only supported with Anthropic/Gemini models.
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
	var maxTurns *int
	if c.MaxTurns != nil {
		maxTurnsCopy := *c.MaxTurns
		maxTurns = &maxTurnsCopy
	}

	var jitInstructions *JITInstructionConfig
	if c.JITInstructions != nil {
		// Clone the rules
		rules := make([]JITInstructionRule, len(c.JITInstructions.Rules))
		for i, rule := range c.JITInstructions.Rules {
			rules[i] = JITInstructionRule{
				ID:               rule.ID,
				TokenThreshold:   rule.TokenThreshold,
				Instructions:     append([]string{}, rule.Instructions...),
				Description:      rule.Description,
				InjectInToolCall: rule.InjectInToolCall,
			}
		}

		// Clone the injection tracking map
		var injectedRuleIDs map[string]bool
		if c.JITInstructions.injectedRuleIDs != nil {
			injectedRuleIDs = make(map[string]bool)
			for k, v := range c.JITInstructions.injectedRuleIDs {
				injectedRuleIDs[k] = v
			}
		}

		jitInstructions = &JITInstructionConfig{
			Rules:           rules,
			injectedRuleIDs: injectedRuleIDs,
		}
	}

	return &CompletionOptions{
		Temperature:        temperature,
		Stream:             stream,
		Stop:               append([]string{}, c.Stop...),
		MaxTurns:           maxTurns,
		INTERNAL_CACHE_KEY: c.INTERNAL_CACHE_KEY,
		ReasoningEffort:    c.ReasoningEffort,
		Verbosity:          c.Verbosity,
		JITInstructions:    jitInstructions,
		ThinkingBudget:     c.ThinkingBudget,
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
	if c.ThinkingBudget > 0 {
		m["thinking_budget"] = c.ThinkingBudget // Note: This is only supported on Anthropic/Gemini models!
	}
	if c.Verbosity != "" {
		logger := enhancedctx.Logger(ctx)
		logger.Warn("verbosity is not currently supported when using Chat Completions")
	}

	return m
}

// ToResponsesMap converts completion options to a map for the Responses API.
func (c *CompletionOptions) ToResponsesMap(ctx context.Context) map[string]any {
	m := map[string]any{}
	c.addSharedOptions(m)

	// "stop" is not supported with the Responses API
	// "thinking_budget" is only supported on Anthropic/Gemini models

	if c.ThinkingBudget > 0 {
		logger := enhancedctx.Logger(ctx)
		logger.Warn("thinking_budget is not supported when using the Responses API")
	}

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
