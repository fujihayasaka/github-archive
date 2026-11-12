package models

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/code-scanning-ai-libraries/v4/errors"
)

// Tool represents a function tool that can be called by the model, or a native provider-hosted tool.
type Tool struct {
	Type           string                                        `json:"type"`
	Name           string                                        `json:"name"`
	Description    string                                        `json:"description"`
	Parameters     *ToolParameters                               `json:"parameters,omitempty"`
	Callback       func(context.Context, string) (string, error) `json:"-"` // Non-serialized callback function. Input is a JSON string, output is a string (optionally JSON formatted).
	Version        string                                        `json:"-"` // Non-serialized version of the tool, used to provide a unique cache key if the underlying implementation changes.
	HasSideEffects bool                                          `json:"-"` // When true, callbacks should be re-invoked when cached responses are replayed.
	Instructions   string                                        `json:"-"` // Instructions to put into the system prompt when using this tool. (Not serialized, so we don't forward it to the LLM provider.)

	// Native tool fields — used when Type is "native" (provider-hosted tools like web_search, code_interpreter).
	// NativeProperties holds the actual tool type (as "type") and any additional config, and is serialized
	// as a flat JSON object. These tools are executed server-side by the model provider, not locally via a Callback.
	NativeProperties map[string]any `json:"-"`
}

// IsNative returns true if this tool is a native provider-hosted tool (e.g., web_search, code_interpreter)
// rather than a locally-executed function or custom tool.
func (t Tool) IsNative() bool {
	return t.Type == "native"
}

// nativeTool is a serialization wrapper for native provider-hosted tools.
// It flattens NativeProperties into a single JSON object (e.g. {"type": "web_search", "external_web_access": false}).
type nativeTool Tool

// MarshalJSON flattens the native tool into a single JSON object with all NativeProperties at the top level.
func (nt nativeTool) MarshalJSON() ([]byte, error) {
	return json.Marshal(nt.NativeProperties)
}

// MarshalJSON serializes a Tool to JSON. Native tools delegate to nativeTool for flat serialization,
// while function/custom tools use the default struct serialization.
func (t Tool) MarshalJSON() ([]byte, error) {
	if t.IsNative() {
		return json.Marshal(nativeTool(t))
	}
	// Default serialization for function/custom tools.
	type toolAlias Tool // avoid infinite recursion
	return json.Marshal(toolAlias(t))
}

// ToChatCompletionsTool converts the Tool to a format suitable for Chat Completions API.
// Returns an error if the tool is a native tool, as native tools are not supported by Chat Completions.
func (t Tool) ToChatCompletionsTool() (map[string]any, error) {
	if t.IsNative() {
		return nil, fmt.Errorf("native tools are not supported by Chat Completions API")
	}
	return map[string]any{
		"type": t.Type,
		"name": t.Name,
		"function": map[string]any{
			"description": t.Description,
			"name":        t.Name,
			"parameters":  t.Parameters,
		},
	}, nil
}

// ToolParameters represents the parameters schema for a tool
type ToolParameters struct {
	Type                 string                  `json:"type"`
	Properties           map[string]ToolProperty `json:"properties"`
	Required             []string                `json:"required"`
	AdditionalProperties bool                    `json:"additionalProperties"`
}

// ToolProperty represents a single property (parameter) in the tool parameters
type ToolProperty struct {
	Type        string `json:"type"`
	Description string `json:"description"`
}

// ToolBuilder provides a fluent interface for building tools
type ToolBuilder struct {
	tool Tool
}

// NewToolBuilder creates a new tool builder
func NewToolBuilder(name, version, description string, callback func(context.Context, string) (string, error)) *ToolBuilder {
	return &ToolBuilder{
		tool: Tool{
			Type:        "function",
			Name:        name,
			Version:     version,
			Description: description,
			Parameters: &ToolParameters{
				Type:                 "object",
				Properties:           make(map[string]ToolProperty),
				Required:             []string{},
				AdditionalProperties: false,
			},
			Callback: callback,
		},
	}
}

// NewCustomTool creates a new custom tool (no parameters, plain text input). Note: As of writing this (2025-09), custom tools are only supported with GPT-5.
// See e.g. https://cookbook.openai.com/examples/gpt-5/gpt-5_new_params_and_tools#2-freeform-function-calling for more details.
func NewCustomTool(name, version, description string, callback func(context.Context, string) (string, error)) Tool {
	return Tool{
		Type:        "custom",
		Name:        name,
		Version:     version,
		Description: description,
		Parameters:  nil,
		Callback:    callback,
	}
}

// AddParameter adds a parameter to the tool
func (tb *ToolBuilder) AddParameter(name, paramType, description string, required bool) *ToolBuilder {
	tb.tool.Parameters.Properties[name] = ToolProperty{
		Type:        paramType,
		Description: description,
	}
	if required {
		tb.tool.Parameters.Required = append(tb.tool.Parameters.Required, name)
	}
	return tb
}

// WithInstructions adds instructions to the tool that will be included in the system prompt
func (tb *ToolBuilder) WithInstructions(instructions string) *ToolBuilder {
	tb.tool.Instructions = instructions
	return tb
}

// WithSideEffects enables that the callback is re-invoked when a cached response is replayed.
func (tb *ToolBuilder) WithSideEffects() *ToolBuilder {
	tb.tool.HasSideEffects = true
	return tb
}

// Build returns the constructed tool
func (tb *ToolBuilder) Build() Tool {
	return tb.tool
}

// ToolsBuilder provides a fluent interface for building a list of tools
type ToolsBuilder struct {
	tools []Tool
}

// NewToolsBuilder creates a new tools builder
func NewToolsBuilder() *ToolsBuilder {
	return &ToolsBuilder{
		tools: []Tool{},
	}
}

// AddTool adds a tool to the list
func (tb *ToolsBuilder) AddTool(tool Tool) *ToolsBuilder {
	tb.tools = append(tb.tools, tool)
	return tb
}

// Build returns the list of tools
func (tb *ToolsBuilder) Build() []Tool {
	return tb.tools
}

// CallTool executes a tool callback based on the provided ChatMessage, and returns a message to append to the conversation.
func CallTool(ctx context.Context, msg ChatMessage, tools []Tool) (ChatMessage, errors.LLMError) {
	// If the message is a function call, we need to execute the tool callback
	if msg.CallID == "" {
		return ChatMessage{}, errors.NewError("function call message missing call_id", errors.ErrorTypeLogic)
	}

	// Find the tool by name
	var tool Tool
	for _, t := range tools {
		if t.Name == msg.Name {
			tool = t
			break
		}
	}
	if tool.Name == "" {
		return ChatMessage{}, errors.NewErrorf(errors.ErrorTypeLogic, "tool %s not found", msg.Name)
	}

	// Call the tool's callback function with the arguments
	input := msg.Arguments
	if input == "" {
		input = msg.Input // custom tool calls have the "Input" field instead.
	}
	output, err := tool.Callback(ctx, input)
	if err != nil {
		return ChatMessage{}, errors.WrapErrorf(err, errors.ErrorTypeLogic, "calling tool %s", tool.Name)
	}

	result := ChatMessage{
		CallID: msg.CallID,
		Output: output,
		Type:   "function_call_output",
	}
	return result, nil
}

// NewNativeTool creates a provider-hosted tool with optional configuration properties.
// Native tools are executed server-side by the model provider (e.g., web_search, code_interpreter),
// as opposed to function tools which are executed locally via a callback.
//
// Example usage:
//
//	webSearch := NewNativeTool("web_search", map[string]any{"external_web_access": false})
//	codeInterpreter := NewNativeTool("code_interpreter", nil)
func NewNativeTool(toolType string, properties map[string]any) Tool {
	if properties == nil {
		properties = make(map[string]any)
	}
	properties["type"] = toolType
	return Tool{
		Type:             "native",
		NativeProperties: properties,
	}
}

// HasNativeTools returns true if the tools slice contains at least one native tool.
func HasNativeTools(tools []Tool) bool {
	for _, t := range tools {
		if t.IsNative() {
			return true
		}
	}
	return false
}

// FilterNativeTools returns a new slice containing only non-native tools.
func FilterNativeTools(tools []Tool) []Tool {
	filtered := make([]Tool, 0, len(tools))
	for _, t := range tools {
		if !t.IsNative() {
			filtered = append(filtered, t)
		}
	}
	return filtered
}
