package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/code-scanning-ai-libraries/v2/llm/config"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/code-scanning-ai-libraries/v2/st"
	pkg_errors "github.com/pkg/errors"
)

// MockModel implements testing model using recorded conversations
type MockModel struct {
	modelName         string
	modelGeneration   string
	contextWindowSize int
	conversationLog   []ConversationLine
	defaultOptions    *models.CompletionOptions
	useRegexMatching  bool
}

// ConversationLine represents a single line in a conversation log file
type ConversationLine struct {
	InteractionID string                `json:"interactionId"`
	FromModel     string                `json:"fromModel,omitempty"`
	ToModel       string                `json:"toModel,omitempty"`
	Error         *models.ResponseError `json:"error,omitempty"`
	Usage         models.TokenUsage     `json:"usage"`
}

// NewMockModel creates a new MockModel from a conversation log file
func NewMockModel(logPath string, opts *models.CompletionOptions) (*MockModel, error) {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return nil, st.EnsureStackTracef(err, "reading conversation log from %s", logPath)
	}

	var lines []ConversationLine

	for _, line := range bytes.Split(data, []byte("\n")) {
		if len(line) == 0 {
			continue
		}
		var conv ConversationLine
		if err := json.Unmarshal(line, &conv); err != nil {
			return nil, st.EnsureStackTrace(err, "parsing conversation line")
		}

		// Add validation step
		if err := validateTemplateJSON(conv); err != nil {
			return nil, st.EnsureStackTrace(err, "invalid template line")
		}

		// There's a small chance that the conversation log contains \r characters, which can cause
		// problems when comparing the prompts.
		conv.ToModel = strings.ReplaceAll(conv.ToModel, "\r", "")
		conv.FromModel = strings.ReplaceAll(conv.FromModel, "\r", "")

		lines = append(lines, conv)
	}

	return &MockModel{
		modelName:         "MockModel",
		modelGeneration:   "gpt-4o",
		contextWindowSize: 128000,
		conversationLog:   lines,
		defaultOptions:    opts,
		useRegexMatching:  false,
	}, nil
}

// NewMockModelFromConfig creates a new MockModel from a model configuration
func NewMockModelFromConfig(cfg *config.ModelConfig, opts *models.CompletionOptions) (*MockModel, error) {
	logPath := cfg.MockModelConversationLogPath
	if logPath == "" {
		return nil, pkg_errors.New("no conversation log provided for mock model! Set MOCK_MODEL_CONVERSATION_LOG_JSONL_PATH")
	}

	return NewMockModel(logPath, opts)
}

// GetModelName returns the name of the mock model
func (m *MockModel) GetModelName() string {
	return m.modelName
}

// GetProviderName returns the provider name for the mock model
func (m *MockModel) GetProviderName() string {
	return "mock"
}

// GetContextSize returns the context window size of the mock model
func (m *MockModel) GetContextSize() int {
	return m.contextWindowSize
}

// Hash returns a hash string for the mock model
func (m *MockModel) Hash() (string, error) {
	// MockModel does not implement hashing, so we return a static string.
	// In a real implementation, this would hash the conversation log or similar.
	return "mock-model-hash", nil
}

// Complete performs text completion using the recorded conversations
func (m *MockModel) Complete(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	lastMsg := messages[len(messages)-1]

	// Find matching message in template
	var match *ConversationLine
	for _, line := range m.conversationLog {
		if m.useRegexMatching {
			if regexp.MustCompile(line.ToModel).MatchString(lastMsg.Content) {
				match = &line
				break
			}
		} else {
			if line.ToModel == lastMsg.Content {
				match = &line
				break
			}
		}
	}

	if match == nil {
		// Get unique interaction IDs like TS implementation
		interactionIDs := make([]string, 0)
		seen := make(map[string]bool)
		for _, line := range m.conversationLog {
			if !seen[line.InteractionID] {
				interactionIDs = append(interactionIDs, line.InteractionID)
				seen[line.InteractionID] = true
			}
		}
		return "", nil, nil, errors.NewError(fmt.Sprintf("no matching message found in template. Looking for:\n%s\nCheck these interactionIds: %v",
			lastMsg.Content, interactionIDs), errors.ErrorTypeLogic)
	}

	// Find corresponding response
	var resp *ConversationLine
	for _, line := range m.conversationLog {
		if line.InteractionID == match.InteractionID && (line.FromModel != "" || line.Error != nil) {
			resp = &line
			break
		}
	}

	if resp == nil {
		return "", nil, nil, errors.NewError(fmt.Sprintf("no response found in conversation template for interactionId %s",
			match.InteractionID), errors.ErrorTypeLogic)
	}

	if resp.Error != nil {
		return "", nil, nil, errors.NewRetryableError(resp.Error.Message, 0)
	}

	messages = append(messages, models.ChatMessage{
		Role:    models.ChatMessageRoleAssistant,
		Content: resp.FromModel,
	})

	// Return dummy token usage values.
	usage := models.TokenUsage{
		PromptTokens:     10,
		CompletionTokens: 20,
		TotalTokens:      30,
	}

	return resp.FromModel, messages, &usage, nil
}

// EnableRegexMatching enables regex matching for message comparison
func (m *MockModel) EnableRegexMatching() {
	m.useRegexMatching = true
}

// NewMockModelFromOptions creates a new MockModel from configuration options
func NewMockModelFromOptions(cfg *config.ModelConfig, opts *models.CompletionOptions) (*MockModel, error) {
	logPath := cfg.MockModelConversationLogPath
	if logPath == "" {
		return nil, pkg_errors.New("no conversation log provided for mock model! Set MOCK_MODEL_CONVERSATION_LOG_JSONL_PATH")
	}
	return NewMockModelFromConversationFile(logPath, "gpt-4o", opts)
}

// NewMockModelFromConversationFile creates a new MockModel from a conversation file with specified model generation
func NewMockModelFromConversationFile(filePath, modelGeneration string, opts *models.CompletionOptions) (*MockModel, errors.LLMError) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, errors.RetryableError{Err: st.EnsureStackTracef(err, "reading conversation log from %s", filePath)}
	}

	var lines []ConversationLine
	for _, line := range bytes.Split(data, []byte("\n")) {
		if len(line) == 0 {
			continue
		}
		var conv ConversationLine
		if err := json.Unmarshal(line, &conv); err != nil {
			return nil, errors.EnsureStackTrace(err, errors.ErrorTypeLogic, "parsing conversation line")
		}
		if err := validateTemplateJSON(conv); err != nil {
			return nil, errors.EnsureStackTrace(err, errors.ErrorTypeLogic, "invalid template line")
		}
		// There's a small chance that the conversation log contains \r characters, which can cause
		// problems when comparing the prompts.
		conv.ToModel = strings.ReplaceAll(conv.ToModel, "\r", "")
		conv.FromModel = strings.ReplaceAll(conv.FromModel, "\r", "")
		lines = append(lines, conv)
	}

	return &MockModel{
		modelName:         "MockModel",
		modelGeneration:   modelGeneration,
		contextWindowSize: 128000,
		conversationLog:   lines,
		defaultOptions:    opts,
		useRegexMatching:  false,
	}, nil
}

func validateTemplateJSON(line ConversationLine) error {
	if line.InteractionID == "" {
		return pkg_errors.New("invalid conversation line: missing interactionId")
	}
	if line.FromModel == "" && line.ToModel == "" && line.Error == nil {
		return pkg_errors.New("invalid conversation line: missing fromModel, toModel, or error")
	}
	return nil
}

// NoMatchFoundError represents an error when no matching message is found in the conversation template
type NoMatchFoundError struct {
	Content        string
	InteractionIDs []string
}

var _ error = &NoMatchFoundError{}

func (e NoMatchFoundError) Error() string {
	return fmt.Sprintf("no matching message found in template. Looking for:\n%s\nCheck these interactionIds: %v",
		e.Content, e.InteractionIDs)
}

// Test utilities and mocks

// MockHTTPClient is a mock implementation of HTTPClient for testing
type MockHTTPClient struct {
	Requests []*http.Request
	Response *http.Response
	Err      error
}

// Do simulates an HTTP request and returns a predefined response or error
func (m *MockHTTPClient) Do(req *http.Request) (*http.Response, error) {
	m.Requests = append(m.Requests, req)
	return m.Response, m.Err
}

// MockModelRegistry is a mock implementation of ModelRegistry for testing
type MockModelRegistry struct {
	Models map[string]*models.ModelEntry
}

// GetModel retrieves a model by ID from the mock registry
func (m *MockModelRegistry) GetModel(id string) (*models.ModelEntry, bool) {
	model, exists := m.Models[id]
	return model, exists
}

// CreateTestModelEntry creates a test model entry with sensible defaults
func CreateTestModelEntry(modelName string) *models.ModelEntry {
	capabilities := &models.ModelCapabilities{
		Family: "gpt-4",
		Limits: &models.ModelLimits{
			MaxContextWindowTokens: 128000,
			MaxOutputTokens:        4096,
			MaxPromptTokens:        64000,
		},
		Supports: &models.ModelSupports{
			Streaming:         true,
			ToolCalls:         true,
			ParallelToolCalls: false,
			StructuredOutputs: false,
			Vision:            false,
		},
		Tokenizer: "cl100k_base",
		Type:      "chat",
	}

	return &models.ModelEntry{
		ID:           modelName,
		Name:         modelName,
		Capabilities: capabilities,
		Vendor:       "openai",
	}
}

// CreateMockResponse creates a mock HTTP response for testing
func CreateMockResponse(statusCode int, body string) *http.Response {
	return &http.Response{
		StatusCode: statusCode,
		Body:       io.NopCloser(strings.NewReader(body)),
		Header:     make(http.Header),
	}
}
