// Package roundrobin implements a round-robin load balancing strategy for multiple LLM models.
package roundrobin

import (
	"context"
	"fmt"
	"math/rand"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
)

// Model implements a round-robin load balancing strategy across multiple LLM models.
type Model struct {
	modelList []models.Model
	index     int
}

// NewRoundRobinModel creates a new RoundRobinModel with the provided models.
// The models are shuffled to avoid always using the same one first.
func NewRoundRobinModel(ms []models.Model) (*Model, errors.LLMError) {
	if len(ms) == 0 {
		return nil, errors.NewError("no models provided", errors.ErrorTypeLogic)
	}

	// Shuffle the models to avoid always using the same one.
	shuffled := make([]models.Model, len(ms))
	perm := rand.Perm(len(ms))
	for i, v := range perm {
		shuffled[v] = ms[i]
	}

	return &Model{
		modelList: shuffled,
		index:     0,
	}, nil
}

// Complete performs a completion with tools support using the next model in the round-robin sequence.
func (r *Model) Complete(ctx context.Context, prompt []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.RoundRobinModel.Complete")
	defer span.End()

	if len(r.modelList) == 0 {
		return "", nil, nil, errors.NewError("no models available", errors.ErrorTypeLogic)
	}

	currentIndex := r.index
	r.index = (r.index + 1) % len(r.modelList)
	return r.modelList[currentIndex].Complete(ctx, prompt, tools, options)
}

// GetModelName returns a descriptive name that includes all underlying model names.
func (r *Model) GetModelName() string {
	names := make([]string, len(r.modelList))
	for i, model := range r.modelList {
		names[i] = model.GetModelName()
	}
	return fmt.Sprintf("RoundRobin<%s>", strings.Join(names, ", "))
}

// GetProviderName returns a descriptive provider name that includes all underlying model provider names.
func (r *Model) GetProviderName() string {
	providerNames := make([]string, len(r.modelList))
	for i, model := range r.modelList {
		providerNames[i] = model.GetProviderName()
	}
	return fmt.Sprintf("RoundRobin<%s>", strings.Join(providerNames, ", "))
}
