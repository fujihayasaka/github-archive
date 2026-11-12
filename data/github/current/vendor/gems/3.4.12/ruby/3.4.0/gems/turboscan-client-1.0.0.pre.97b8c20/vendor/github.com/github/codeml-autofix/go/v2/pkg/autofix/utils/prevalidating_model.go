package utils

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/code-scanning-ai-libraries/v2/llm"
	"github.com/github/code-scanning-ai-libraries/v2/llm/config"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/code-scanning-ai-libraries/v2/st"
)

// PrevalidatingModel wraps a models.Model and enforces constraints on outgoing
// messages (e.g. maximum per-line length) before invoking the underlying model.
type PrevalidatingModel struct {
	model models.Model
}

const maxMessageLineLength = 4096

// validateMessages checks if the messages are valid
func (p *PrevalidatingModel) validateMessages(messages []models.ChatMessage) errors.LLMError {
	// verify the line length of the messages
	for _, msg := range messages {
		// split by newlines to check each line
		lines := strings.Split(msg.Content, "\n")
		for _, line := range lines {
			if len(line) > maxMessageLineLength {
				return errors.NewNotAutofixableError(
					fmt.Sprintf("message line exceeds max length (%d > %d)", len(line), maxMessageLineLength),
				)
			}
		}
	}
	return nil
}

// Complete implements the Model interface
func (p *PrevalidatingModel) Complete(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	if err := p.validateMessages(messages); err != nil {
		return "", nil, nil, err
	}
	return p.model.Complete(ctx, messages, tools, options)
}

// GetModelName returns the model name
func (p *PrevalidatingModel) GetModelName() string {
	return fmt.Sprintf("Prevalidating<%s>", p.model.GetModelName())
}

// GetProviderName returns the provider name
func (p *PrevalidatingModel) GetProviderName() string {
	return p.model.GetProviderName()
}

// CreatePrevalidatingModel creates a model with prevalidation
func CreatePrevalidatingModel(ctx context.Context, modelName string, cfg *config.ModelConfig) (models.Model, error) {
	model, err := llm.GetModel(ctx, modelName, cfg)
	if err != nil {
		return nil, st.EnsureStackTrace(err, "failed to create model client")
	}

	return &PrevalidatingModel{model}, nil
}
