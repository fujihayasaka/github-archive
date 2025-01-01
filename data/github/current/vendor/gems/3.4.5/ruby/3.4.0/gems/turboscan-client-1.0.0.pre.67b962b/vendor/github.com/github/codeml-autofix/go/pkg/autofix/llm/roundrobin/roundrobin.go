package roundrobin

import (
	"context"
	"fmt"
	"math/rand"
	"strings"

	"github.com/github/codeml-autofix/go/pkg/autofix"
	"github.com/github/codeml-autofix/go/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/models"
)

type RoundRobinModel struct {
	modelList []models.HashableModel
	index     int
}

func NewRoundRobinModel(ms []models.HashableModel) (*RoundRobinModel, autofix.AutofixError) {
	if len(ms) == 0 {
		return nil, autofix.NewInvalidRequestError("no models provided")
	}

	// Shuffle the models to avoid always using the same one.
	shuffled := make([]models.HashableModel, len(ms))
	perm := rand.Perm(len(ms))
	for i, v := range perm {
		shuffled[v] = ms[i]
	}

	return &RoundRobinModel{ //nolint:exhaustruct
		modelList: shuffled,
		index:     0,
	}, nil
}

func (r *RoundRobinModel) Complete(ctx context.Context, messages []models.ChatMessage) (string, autofix.AutofixError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.RoundRobinModel.Complete")
	defer span.End()

	if len(r.modelList) == 0 {
		return "", autofix.NewLogicError("no models available")
	}

	opts := r.GetDefaultCompletionOptions()
	return r.CompleteWithOptions(ctx, messages, &opts)
}

func (r *RoundRobinModel) CompleteWithOptions(ctx context.Context, messages []models.ChatMessage, options *models.CompletionOptions) (string, autofix.AutofixError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.RoundRobinModel.CompleteWithOptions")
	defer span.End()

	if len(r.modelList) == 0 {
		return "", autofix.NewLogicError("no models available")
	}

	currentIndex := r.index
	r.index = (r.index + 1) % len(r.modelList)
	return r.modelList[currentIndex].CompleteWithOptions(ctx, messages, options)
}

func (r *RoundRobinModel) GetModelName() string {
	names := make([]string, len(r.modelList))
	for i, model := range r.modelList {
		names[i] = model.GetModelName()
	}
	return fmt.Sprintf("RoundRobin<%s>", strings.Join(names, ", "))
}

func (r *RoundRobinModel) GetModelGeneration() string {
	if len(r.modelList) > 0 {
		return r.modelList[0].GetModelGeneration()
	}
	return ""
}

func (r *RoundRobinModel) GetEncodingName() string {
	if len(r.modelList) > 0 {
		return r.modelList[0].GetEncodingName()
	}
	return "cl100k_base" // TODO: revisit to better handle defaults.
}

func (r *RoundRobinModel) GetContextSize() int {
	// Return the minimum context size among all models
	if len(r.modelList) == 0 {
		return 0
	}

	minSize := r.modelList[0].GetContextSize()
	for _, model := range r.modelList {
		if size := model.GetContextSize(); size < minSize {
			minSize = size
		}
	}
	return minSize
}

func (r *RoundRobinModel) GetMaxTokens() int {
	if len(r.modelList) > 0 {
		return r.modelList[0].GetMaxTokens()
	}
	return 0
}

func (r *RoundRobinModel) GetDefaultCompletionOptions() models.CompletionOptions {
	if len(r.modelList) > 0 {
		return r.modelList[0].GetDefaultCompletionOptions()
	}
	panic("no models available in round robin model, cannot get default options")
}

func (r *RoundRobinModel) Hash() (string, error) {
	hashes := make([]string, len(r.modelList))
	for i, model := range r.modelList {
		hash, err := model.Hash()
		if err != nil {
			return "", err
		}
		hashes[i] = hash
	}
	return strings.Join(hashes, ","), nil
}
