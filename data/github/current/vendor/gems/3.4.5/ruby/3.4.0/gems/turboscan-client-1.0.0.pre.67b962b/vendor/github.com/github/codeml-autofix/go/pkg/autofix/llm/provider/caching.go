// Logic for caching completions/answers.
package provider

import (
	"context"

	"github.com/github/codeml-autofix/go/pkg/autofix"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/models"
	"github.com/github/codeml-autofix/go/pkg/autofix/utils"
)

// CachingModel wraps a model and caches its completions.
//
// This client is intended to be used to cache completions across restarts when running in a single
// process. It is not safe to use if multiple instances of autofix are running concurrently.
type CachingModel struct {
	model    models.HashableModel
	llmCache utils.Cache[string, error]
}

var _ models.HashableModel = &CachingModel{} //nolint:exhaustruct

func NewCachingModelFromPath(model models.HashableModel, cachePath string) *CachingModel {
	return NewCachingModel(model, utils.NewCacheFactory[string, error](cachePath))
}

// NewCachingModel wraps a model provider and provides caching of responses for that provider.
func NewCachingModel(model models.HashableModel, cacheFactory *utils.CacheFactory[string, error]) *CachingModel {
	// Use a constant name so we can persist the cache across restarts.
	c := cacheFactory.GetCache("llm-cache", utils.TimeoutNever, "2024-09-03")
	return &CachingModel{
		model:    model,
		llmCache: c,
	}
}

func (cm *CachingModel) GetModelName() string {
	return "Caching<" + cm.model.GetModelName() + ">"
}

func (cm *CachingModel) GetModelGeneration() string {
	return cm.model.GetModelGeneration()
}

func (cm *CachingModel) GetContextSize() int {
	return cm.model.GetContextSize()
}

func (cm *CachingModel) GetEncodingName() string {
	return cm.model.GetEncodingName()
}

func (cm *CachingModel) GetMaxTokens() int {
	return cm.model.GetMaxTokens()
}

func (cm *CachingModel) GetDefaultCompletionOptions() models.CompletionOptions {
	return cm.model.GetDefaultCompletionOptions()
}

func (cm *CachingModel) Complete(ctx context.Context, prompt []models.ChatMessage) (string, autofix.AutofixError) {
	defaultOptions := cm.model.GetDefaultCompletionOptions()
	return cm.CompleteWithOptions(ctx, prompt, &defaultOptions)
}

func (cm *CachingModel) CompleteWithOptions(ctx context.Context, prompt []models.ChatMessage, options *models.CompletionOptions) (string, autofix.AutofixError) {
	key, err := cm.model.Hash()
	if err != nil {
		return "", autofix.NewLogicError("failed to hash model: " + err.Error())
	}

	// Add the prompt to the cache key.
	for _, msg := range prompt {
		hash, err := msg.Hash()
		if err != nil {
			return "", autofix.NewLogicError("failed to hash message: " + err.Error())
		}
		key += ":" + hash
	}

	// Add the options to the cache key.
	hash, err := options.Hash()
	if err != nil {
		return "", autofix.NewLogicError("failed to hash options: " + err.Error())
	}
	key += ":" + hash

	// Retrieve or compute the completion.
	_, result, err := cm.llmCache.Get(utils.HashableString(key), func() (string, error) {
		res, err := cm.model.CompleteWithOptions(ctx, prompt, options)
		// If the response is non-cacheable, wrap it in a DontPersistError.
		if err != nil {
			return "", &DontPersistError{err: err}
		}
		return res, err
	})

	if err != nil {
		// If it's a DontPersistError, return the contained response.
		if dpe, ok := err.(*DontPersistError); ok {
			return "", dpe.err
		}
		return "", autofix.BadModelOutputError{Err: err}
	}

	return result, nil
}

func (cm *CachingModel) Hash() (string, error) {
	return cm.model.Hash()
}

// DontPersistError wraps a Response that should not be cached.
type DontPersistError struct {
	err autofix.AutofixError
}

func (e *DontPersistError) Error() string {
	return "Don't persist this error"
}
