package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/github-telemetry-go/kvp"
)

// HTTPClient defines an interface for HTTP operations
type HTTPClient interface {
	Do(req *http.Request) (*http.Response, error)
}

// ModelRegistry defines the interface for model lookup operations
type ModelRegistry interface {
	GetModel(id string) (*models.ModelEntry, bool)
}

// ChatCompletionsClient provides shared functionality for LLM provider clients
type ChatCompletionsClient struct {
	httpClient     HTTPClient
	defaultOptions *models.CompletionOptions
}

// ChatCompletionsClientOption defines a function that configures a ChatCompletionsClient
type ChatCompletionsClientOption func(*ChatCompletionsClient)

// WithHTTPClient allows injecting a custom HTTP client
func WithHTTPClient(client HTTPClient) ChatCompletionsClientOption {
	return func(b *ChatCompletionsClient) {
		b.httpClient = client
	}
}

// WithDefaultOptions allows setting default completion options
func WithDefaultOptions(opts *models.CompletionOptions) ChatCompletionsClientOption {
	return func(b *ChatCompletionsClient) {
		b.defaultOptions = opts
	}
}

// NewChatCompletionsClient creates a new base client with default options
func NewChatCompletionsClient(defaultOpts *models.CompletionOptions, options ...ChatCompletionsClientOption) *ChatCompletionsClient {
	var clientOpts *models.CompletionOptions
	if defaultOpts != nil {
		clientOpts = defaultOpts.Clone()
	}
	client := &ChatCompletionsClient{
		defaultOptions: clientOpts,
		httpClient:     &http.Client{Timeout: 10 * time.Minute}, //nolint:exhaustruct // No need for all fields
	}

	for _, option := range options {
		option(client)
	}

	return client
}

// doRequest executes an HTTP POST request to the specified endpoint with the given body.
// It returns the response or an error if the request fails.
func (b *ChatCompletionsClient) doRequest(ctx context.Context, endpoint string, headers map[string]string, requestBody interface{}, stream bool) ([]models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	requestJSON, err := json.Marshal(requestBody)

	if err != nil {
		return nil, nil, errors.WrapError(err, errors.ErrorTypeLogic, "marshaling request body")
	}

	enhancedctx.Logger(ctx).WithFields(
		kvp.String("url", endpoint),
	).Debug("Sending HTTP request")

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(requestJSON))
	if err != nil {
		return nil, nil, errors.WrapError(err, errors.ErrorTypeLogic, "creating request")
	}

	for k, v := range headers {
		req.Header.Set(k, v)
	}

	resp, err := b.httpClient.Do(req)
	if err != nil {
		return nil, nil, errors.WrapRetryableError(
			err,
			fmt.Sprintf("executing request to %s", endpoint),
			0,
		)
	}
	defer resp.Body.Close()

	ctx = withResponseRequestID(ctx, resp)

	if !isResponseOK(resp) {
		err := handleErrorResponse(ctx, resp, requestJSON)

		enhancedctx.Logger(ctx).WithError(err).Warn(
			"HTTP request failed",
			kvp.Int("http_status_code", resp.StatusCode),
			kvp.String("url", endpoint),
		)
		return nil, nil, err
	}

	if stream {
		// TODO: No support for tool calling in streaming responses. And we probably should never do that here, because this code is specific to Chat Completions API.
		// It also only supports returning strictly a single message, which is sufficient when there are no tools.
		resp, usage, llmErr := handleStreamResponse(ctx, resp)
		if llmErr != nil {
			return nil, nil, llmErr
		}
		return []models.ChatMessage{
			{
				Role:    models.ChatMessageRoleAssistant,
				Content: resp,
			},
		}, usage, nil
	}

	return handleSingleResponse(ctx, resp)
}

// withResponseRequestID returns a context carrying the X-GitHub-Request-Id from resp.
func withResponseRequestID(ctx context.Context, resp *http.Response) context.Context {
	if resp == nil {
		return ctx
	}
	if rid := resp.Header.Get("X-GitHub-Request-Id"); rid != "" {
		return enhancedctx.WithRequestID(ctx, rid)
	}
	return ctx
}
