package provider

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/code-scanning-ai-libraries/v2/utils"
	pkg_errors "github.com/pkg/errors"
)

// CachingModel wraps a model and caches its completions.
//
// This client is intended to be used to cache completions across restarts when running in a single
// process. It is not safe to use if multiple instances of autofix are running concurrently.
type CachingModel struct {
	model    models.Model
	llmCache utils.Cache[ResponseOrError, errors.LLMError]
}

var _ models.Model = &CachingModel{} //nolint:exhaustruct // just testing that the type works.

// NewCachingModelFromPath creates a new CachingModel with a cache at the specified path.
func NewCachingModelFromPath(model models.Model, cachePath string) *CachingModel {
	return NewCachingModel(model, utils.NewCacheFactory[ResponseOrError, errors.LLMError](cachePath))
}

// NewCachingModel wraps a model provider and provides caching of responses for that provider.
func NewCachingModel(model models.Model, cacheFactory *utils.CacheFactory[ResponseOrError, errors.LLMError]) *CachingModel {
	// Use a constant name so we can persist the cache across restarts.
	c := cacheFactory.GetCache("llm-cache", utils.TimeoutNever, "2025-08-19")
	return &CachingModel{
		model:    model,
		llmCache: c,
	}
}

// GetModelName returns the wrapped model's name with a "Caching<...>" prefix.
func (cm *CachingModel) GetModelName() string {
	return "Caching<" + cm.model.GetModelName() + ">"
}

// GetProviderName returns the wrapped model's provider name.
func (cm *CachingModel) GetProviderName() string {
	return cm.model.GetProviderName()
}

// Complete performs a completion with tools support, using caching to avoid redundant API calls.
func (cm *CachingModel) Complete(ctx context.Context, prompt []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	key := cm.model.GetProviderName() + ":" + cm.model.GetModelName()

	for _, tool := range tools {
		// Add the tool version and serialized tool to the cache key. (Version is not part of the serialized object).
		toolJSON, err := json.Marshal(tool)
		if err != nil {
			return "", nil, nil, errors.WrapError(err, errors.ErrorTypeLogic, "failed to marshal tool")
		}
		key += ":" + tool.Version + "-" + string(toolJSON)
	}

	// Add the prompt to the cache key.
	for _, msg := range prompt {
		hash, err := msg.Hash()
		if err != nil {
			return "", nil, nil, errors.WrapError(err, errors.ErrorTypeLogic, "failed to hash message")
		}
		key += ":" + hash
	}

	if options == nil {
		options = &models.CompletionOptions{}
	}

	// Add the options to the cache key.
	hash, err := options.Hash()
	if err != nil {
		return "", nil, nil, errors.WrapError(err, errors.ErrorTypeLogic, "failed to hash options")
	}
	key += ":" + hash

	// Retrieve or compute the completion.
	_, roe, cacheErr := cm.llmCache.Get(utils.HashableString(key), func() (ResponseOrError, errors.LLMError) {
		res, transcript, usage, err := cm.model.Complete(ctx, prompt, tools, options)
		if err != nil {
			// if it's an HTTPStatusError, and it's not retryable, we wrap it in a ResponseOrError such that it is cached.
			if httpErr, ok := err.(errors.HTTPStatusError); ok &&
				!httpErr.Retryable() &&
				// auth-related errors are not retryable, but we don't want to cache them either
				// in case the user fixes their credentials and tries again
				(httpErr.StatusCode != http.StatusBadRequest ||
					strings.Contains(httpErr.Err.Error(), "prompt token count") /* Status code 400 from CAPI can annoyingly also be prompt token limit exceeded errors, which we do want to cache. */) &&
				httpErr.StatusCode != http.StatusUnauthorized &&
				httpErr.StatusCode != http.StatusForbidden {
				return ResponseOrError{Error: &httpErr}, nil //nolint:exhaustruct // other field intentionally empty
			}

			// other error, return as is.
			return ResponseOrError{}, err
		}
		return ResponseOrError{Response: res, Transcript: transcript, Usage: usage}, nil //nolint:exhaustruct // other field intentionally empty
	}, enhancedctx.Logger(ctx))

	// propagate cache layer errors first
	if cacheErr != nil {
		return "", nil, nil, cacheErr
	}
	// propagate cached HTTPStatusError
	if roe.Error != nil {
		return "", nil, nil, roe.Error
	}
	return roe.Response, roe.Transcript, roe.Usage, nil
}

// ResponseOrError represents either a successful LLM response or an HTTPStatusError.
type ResponseOrError struct {
	Response   string                  // present when Kind == "response"
	Transcript []models.ChatMessage    // present when Kind == "response"
	Usage      *models.TokenUsage      // present when Kind == "response"
	Error      *errors.HTTPStatusError // present when Kind == "error"
}

// MarshalJSON encodes the struct as {kind:"response",response:"..."} or {kind:"error",error:{...}}
func (roe ResponseOrError) MarshalJSON() ([]byte, error) {
	if roe.Error != nil {
		return json.Marshal(struct {
			Kind  string                  `json:"kind"`
			Error *errors.HTTPStatusError `json:"error"`
		}{
			Kind:  "error",
			Error: roe.Error,
		})
	}

	return json.Marshal(struct {
		Kind       string               `json:"kind"`
		Transcript []models.ChatMessage `json:"transcript"`
		Response   string               `json:"response"`
		Usage      *models.TokenUsage   `json:"usage"`
	}{
		Kind:       "response",
		Transcript: roe.Transcript,
		Response:   roe.Response,
		Usage:      roe.Usage,
	})
}

// UnmarshalJSON decodes the previously marshaled representation.
func (roe *ResponseOrError) UnmarshalJSON(data []byte) error {
	var probe struct {
		Kind string `json:"kind"`
	}
	if err := json.Unmarshal(data, &probe); err != nil {
		return err
	}

	switch probe.Kind {
	case "response":
		var tmp struct {
			Response   string               `json:"response"`
			Transcript []models.ChatMessage `json:"transcript"`
			Usage      *models.TokenUsage   `json:"usage"`
		}
		if err := json.Unmarshal(data, &tmp); err != nil {
			return err
		}
		*roe = ResponseOrError{Response: tmp.Response, Transcript: tmp.Transcript, Usage: tmp.Usage} //nolint:exhaustruct // other field intentionally empty

	case "error":
		var tmp struct {
			Error errors.HTTPStatusError `json:"error"`
		}
		if err := json.Unmarshal(data, &tmp); err != nil {
			return err
		}
		*roe = ResponseOrError{Error: &tmp.Error} //nolint:exhaustruct // other field intentionally empty

	default:
		return pkg_errors.Errorf("unknown kind %q", probe.Kind)
	}
	return nil
}
