package models

import (
	"context"

	"github.com/github/code-scanning-ai-libraries/v3/errors"
)

// Tool represents a function tool that can be called by the model
type Tool struct {
	Type           string                                        `json:"type"`
	Name           string                                        `json:"name"`
	Description    string                                        `json:"description"`
	Parameters     *ToolParameters                               `json:"parameters,omitempty"`
	Callback       func(context.Context, string) (string, error) `json:"-"` // Non-serialized callback function. Input is a JSON string, output is a string (optionally JSON formatted).
	Version        string                                        `json:"-"` // Non-serialized version of the tool, used to provide a unique cache key if the underlying implementation changes.
	HasSideEffects bool                                          `json:"-"` // When true, callbacks should be re-invoked when cached responses are replayed.
	Instructions   string                                        `json:"-"` // Instructions to put into the system prompt when using this tool. (Not serialized, so we don't forward it to the LLM provider.)
}

// ToChatCompletionsTool converts the Tool to a format suitable for Chat Completions API
func (t Tool) ToChatCompletionsTool() map[string]any {
	return map[string]any{
		"type": t.Type,
		"name": t.Name,
		"function": map[string]any{
			"description": t.Description,
			"name":        t.Name,
			"parameters":  t.Parameters,
		},
	}
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
