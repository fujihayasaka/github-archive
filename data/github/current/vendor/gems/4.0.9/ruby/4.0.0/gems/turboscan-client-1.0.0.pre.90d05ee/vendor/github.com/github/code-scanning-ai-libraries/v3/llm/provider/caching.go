package provider

import (
	"context"
	"encoding/json"
	"net/http"
	"regexp"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v3/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v3/errors"
	"github.com/github/code-scanning-ai-libraries/v3/llm/models"
	"github.com/github/code-scanning-ai-libraries/v3/utils"
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
	c := cacheFactory.GetCache("llm-cache", utils.TimeoutNever, "2025-10-02")
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

// NormalizeDates replaces dates in the input string with a placeholder, in order to ensure we get a cache-hit when the same prompt is run on different days.
func NormalizeDates(s string) string {
	// Match dates like "October 2023", "January 2024", etc.
	// Also match full datetime like "November 19, 2025 at 03:15:44 UTC"
	datePattern := `\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2},\s+)?20\d{2}(\s+at\s+\d{2}:\d{2}:\d{2}\s+\w+)?\b`
	re := regexp.MustCompile(datePattern)
	return re.ReplaceAllString(s, "<some date>")
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

	// normalize all dates in the tool descriptions / prompts
	key = NormalizeDates(key)

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
	hit, roe, cacheErr := cm.llmCache.Get(utils.HashableString(key), func() (ResponseOrError, errors.LLMError) {
		recordedInvocations := make([]ToolInvocationRecord, 0)
		wrappedTools := wrapToolsForRecording(tools, &recordedInvocations)
		res, transcript, usage, err := cm.model.Complete(ctx, prompt, wrappedTools, options)
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
		return ResponseOrError{Response: res, Transcript: transcript, Usage: usage, ToolInvocations: recordedInvocations}, nil //nolint:exhaustruct // other field intentionally empty
	}, enhancedctx.Logger(ctx))

	// propagate cache layer errors first
	if cacheErr != nil {
		return "", nil, nil, cacheErr
	}

	// propagate cached HTTPStatusError
	if roe.Error != nil {
		return "", nil, nil, roe.Error
	}

	// Replay tool calls, if we got a cache-hit.
	if hit {
		if replayErr := replayToolInvocations(ctx, tools, roe.ToolInvocations); replayErr != nil {
			return "", nil, nil, replayErr
		}
	}

	return roe.Response, roe.Transcript, roe.Usage, nil
}

// ToolInvocationRecord tracks a single tool execution so it can be replayed on cache hits.
type ToolInvocationRecord struct {
	Name  string `json:"name"`
	Input string `json:"input"`
}

func wrapToolsForRecording(tools []models.Tool, recorded *[]ToolInvocationRecord) []models.Tool {
	if len(tools) == 0 {
		return tools
	}

	wrapped := make([]models.Tool, len(tools))
	copy(wrapped, tools)

	for i := range wrapped {
		tool := wrapped[i]
		if !tool.HasSideEffects || tool.Callback == nil {
			continue
		}

		originalCallback := tool.Callback
		name := tool.Name
		wrapped[i].Callback = func(ctx context.Context, input string) (string, error) {
			output, err := originalCallback(ctx, input)
			if err != nil {
				return output, err
			}
			*recorded = append(*recorded, ToolInvocationRecord{Name: name, Input: input})
			return output, nil
		}
	}

	return wrapped
}

func replayToolInvocations(ctx context.Context, tools []models.Tool, invocations []ToolInvocationRecord) errors.LLMError {
	if len(invocations) == 0 {
		return nil
	}

	toolMap := make(map[string]models.Tool, len(tools))
	for _, tool := range tools {
		if tool.Callback == nil || !tool.HasSideEffects {
			continue
		}
		toolMap[tool.Name] = tool
	}

	for _, invocation := range invocations {
		tool, ok := toolMap[invocation.Name]
		if !ok {
			return errors.NewErrorf(errors.ErrorTypeLogic, "cached tool %s no longer available for replay", invocation.Name)
		}
		if _, err := tool.Callback(ctx, invocation.Input); err != nil {
			return errors.WrapErrorf(err, errors.ErrorTypeLogic, "replaying cached invocation for tool %s", invocation.Name)
		}
	}

	return nil
}

// ResponseOrError represents either a successful LLM response or an HTTPStatusError.
type ResponseOrError struct {
	Response        string                  // present when Kind == "response"
	Transcript      []models.ChatMessage    // present when Kind == "response"
	Usage           *models.TokenUsage      // present when Kind == "response"
	Error           *errors.HTTPStatusError // present when Kind == "error"
	ToolInvocations []ToolInvocationRecord  // replayable tool invocations captured during the initial request
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
		Kind            string                 `json:"kind"`
		Transcript      []models.ChatMessage   `json:"transcript"`
		Response        string                 `json:"response"`
		Usage           *models.TokenUsage     `json:"usage"`
		ToolInvocations []ToolInvocationRecord `json:"tool_invocations,omitempty"`
	}{
		Kind:            "response",
		Transcript:      roe.Transcript,
		Response:        roe.Response,
		Usage:           roe.Usage,
		ToolInvocations: roe.ToolInvocations,
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
			Response        string                 `json:"response"`
			Transcript      []models.ChatMessage   `json:"transcript"`
			Usage           *models.TokenUsage     `json:"usage"`
			ToolInvocations []ToolInvocationRecord `json:"tool_invocations"`
		}
		if err := json.Unmarshal(data, &tmp); err != nil {
			return err
		}
		*roe = ResponseOrError{Response: tmp.Response, Transcript: tmp.Transcript, Usage: tmp.Usage, ToolInvocations: tmp.ToolInvocations} //nolint:exhaustruct // other field intentionally empty

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
