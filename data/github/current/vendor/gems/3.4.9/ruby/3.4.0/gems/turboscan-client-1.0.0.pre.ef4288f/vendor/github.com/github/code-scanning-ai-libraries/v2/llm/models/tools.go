package models

import (
	"github.com/github/code-scanning-ai-libraries/v2/errors"
)

// Tool represents a function tool that can be called by the model
type Tool struct {
	Type        string                       `json:"type"`
	Name        string                       `json:"name"`
	Description string                       `json:"description"`
	Parameters  ToolParameters               `json:"parameters"`
	Callback    func(string) (string, error) `json:"-"` // Non-serialized callback function. Input is a JSON string, output is a string (optionally JSON formatted).
	Version     string                       `json:"-"` // Non-serialized version of the tool, used to provide a unique cache key if the underlying implementation changes.
}

// ToChatCompletionsTool converts the Tool to a format suitable for Chat Completions API
func (t Tool) ToChatCompletionsTool() any {
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
func NewToolBuilder(name, version, description string, callback func(string) (string, error)) *ToolBuilder {
	return &ToolBuilder{
		tool: Tool{
			Type:        "function",
			Name:        name,
			Version:     version,
			Description: description,
			Parameters: ToolParameters{
				Type:                 "object",
				Properties:           make(map[string]ToolProperty),
				Required:             []string{},
				AdditionalProperties: false,
			},
			Callback: callback,
		},
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
func CallTool(msg ChatMessage, tools []Tool) (ChatMessage, errors.LLMError) {
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
		return ChatMessage{}, errors.NewErrorf(errors.ErrorTypeLogic, "tool %s not found", msg.CallID)
	}

	// Call the tool's callback function with the arguments
	output, err := tool.Callback(msg.Arguments)
	if err != nil {
		return ChatMessage{}, errors.WrapErrorf(err, errors.ErrorTypeLogic, "calling tool %s", tool.Name)
	}

	return ChatMessage{
		CallID: msg.CallID,
		Output: output,
		Type:   "function_call_output",
	}, nil
}
