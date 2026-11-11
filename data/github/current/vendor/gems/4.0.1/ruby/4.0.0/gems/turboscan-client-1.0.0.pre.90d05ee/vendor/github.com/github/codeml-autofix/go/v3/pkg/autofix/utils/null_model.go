// Package utils provides utility types and functions for the autofix package.
package utils

import (
	"context"

	shared_errors "github.com/github/code-scanning-ai-libraries/v3/errors"
	"github.com/github/code-scanning-ai-libraries/v3/llm/models"
)

// NullModel is a placeholder model that panics if Complete is called.
// It is used when a model is required but not actually needed (e.g., dry-run mode).
type NullModel struct{}

// Complete panics because NullModel should not be used for actual completions.
func (n *NullModel) Complete(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, shared_errors.LLMError) {
	panic("NullModel.Complete should not be called")
}

// GetModelName returns the name of the null model.
func (n *NullModel) GetModelName() string {
	return "Null model"
}

// GetProviderName returns the provider name of the null model.
func (n *NullModel) GetProviderName() string {
	return "Null provider"
}
