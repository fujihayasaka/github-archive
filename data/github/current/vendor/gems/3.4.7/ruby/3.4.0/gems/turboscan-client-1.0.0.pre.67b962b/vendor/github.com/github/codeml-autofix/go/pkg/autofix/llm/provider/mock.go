package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/github/codeml-autofix/go/pkg/autofix"
	"github.com/github/codeml-autofix/go/pkg/autofix/config"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/models"
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

type ConversationLine struct {
	InteractionID string                `json:"interactionId"`
	FromModel     string                `json:"fromModel,omitempty"`
	ToModel       string                `json:"toModel,omitempty"`
	Error         *models.ErrorResponse `json:"error,omitempty"`
	Usage         models.TokenUsage     `json:"usage"`
}

func NewMockModel(logPath string, opts *models.CompletionOptions) (*MockModel, error) {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return nil, fmt.Errorf("reading conversation log from %s: %w", logPath, err)
	}

	var lines []ConversationLine

	for _, line := range bytes.Split(data, []byte("\n")) {
		if len(line) == 0 {
			continue
		}
		var conv ConversationLine
		if err := json.Unmarshal(line, &conv); err != nil {
			return nil, fmt.Errorf("parsing conversation line: %w", err)
		}

		// Add validation step
		if err := validateTemplateJSON(conv); err != nil {
			return nil, fmt.Errorf("invalid template line: %w", err)
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

func NewMockModelFromConfig(cfg *config.Config, opts *models.CompletionOptions) (*MockModel, error) {
	logPath := cfg.MockModelConversationLogPath
	if logPath == "" {
		return nil, fmt.Errorf("no conversation log provided for mock model! Set MOCK_MODEL_CONVERSATION_LOG_JSONL_PATH")
	}

	return NewMockModel(logPath, opts)
}

func (m *MockModel) GetModelName() string {
	return m.modelName
}

func (m *MockModel) GetModelGeneration() string {
	return m.modelGeneration
}

func (m *MockModel) GetContextSize() int {
	return m.contextWindowSize
}

func (m *MockModel) GetMaxTokens() int {
	return m.defaultOptions.MaxTokens
}

func (m *MockModel) GetDefaultCompletionOptions() models.CompletionOptions {
	return *m.defaultOptions.Clone()
}

func (m *MockModel) Complete(ctx context.Context, messages []models.ChatMessage) (string, autofix.AutofixError) {
	defaultOptions := m.GetDefaultCompletionOptions()
	return m.CompleteWithOptions(ctx, messages, &defaultOptions)
}

func (m *MockModel) CompleteWithOptions(ctx context.Context, messages []models.ChatMessage, options *models.CompletionOptions) (string, autofix.AutofixError) {
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
		interactionIds := make([]string, 0)
		seen := make(map[string]bool)
		for _, line := range m.conversationLog {
			if !seen[line.InteractionID] {
				interactionIds = append(interactionIds, line.InteractionID)
				seen[line.InteractionID] = true
			}
		}
		return "", autofix.NewLogicError(fmt.Sprintf("no matching message found in template. Looking for:\n%s\nCheck these interactionIds: %v",
			lastMsg.Content, interactionIds))
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
		return "", autofix.NewLogicError(fmt.Sprintf("no response found in conversation template for interactionId %s",
			match.InteractionID))
	}

	if resp.Error != nil {
		return "", autofix.NewRetryableError(resp.Error.Message, time.Second*5)
	}

	return resp.FromModel, nil
}

func (m *MockModel) EnableRegexMatching() {
	m.useRegexMatching = true
}

func (m *MockModel) GetEncodingName() string {
	// TODO: work out a more robust way to align this with TypeScript
	return "o200k_base"
}

func NewMockModelFromOptions(cfg *config.Config, opts *models.CompletionOptions) (*MockModel, error) {
	logPath := cfg.MockModelConversationLogPath
	if logPath == "" {
		return nil, fmt.Errorf("no conversation log provided for mock model! Set MOCK_MODEL_CONVERSATION_LOG_JSONL_PATH")
	}
	return NewMockModelFromConversationFile(logPath, "gpt-4o", opts)
}

func NewMockModelFromConversationFile(filePath string, modelGeneration string, opts *models.CompletionOptions) (*MockModel, autofix.AutofixError) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, autofix.RetryableError{Err: fmt.Errorf("reading conversation log from %s: %w", filePath, err)}
	}

	var lines []ConversationLine
	for _, line := range bytes.Split(data, []byte("\n")) {
		if len(line) == 0 {
			continue
		}
		var conv ConversationLine
		if err := json.Unmarshal(line, &conv); err != nil {
			return nil, autofix.InvalidRequestError{Err: fmt.Errorf("parsing conversation line: %w", err)}
		}
		if err := validateTemplateJSON(conv); err != nil {
			return nil, autofix.InvalidRequestError{Err: fmt.Errorf("invalid template line: %w", err)}
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
		return fmt.Errorf("invalid conversation line: missing interactionId")
	}
	if line.FromModel == "" && line.ToModel == "" && line.Error == nil {
		return fmt.Errorf("invalid conversation line: missing fromModel, toModel, or error")
	}
	return nil
}

type NoMatchFoundError struct {
	Content        string
	InteractionIds []string
}

var _ error = &NoMatchFoundError{}

func (e NoMatchFoundError) Error() string {
	return fmt.Sprintf("no matching message found in template. Looking for:\n%s\nCheck these interactionIds: %v",
		e.Content, e.InteractionIds)
}
