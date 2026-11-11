package provider

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/github/code-scanning-ai-libraries/v4/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v4/errors"
	"github.com/github/code-scanning-ai-libraries/v4/llm/models"
	"github.com/github/github-telemetry-go/kvp"
)

// VLLMClient is a client for vLLM deployments
type VLLMClient struct {
	modelName       string
	httpClient      HTTPClient
	baseURL         string // e.g. "https://example-deployment.microsoft.com/amt/v1"
	apiKey          string // optional API key
	useResponsesAPI bool   // if true, use /responses endpoint; if false, use /chat/completions
	defaultOpts     *models.CompletionOptions
	retry           bool
}

// VLLMClientOption defines configuration options for vLLM clients
type VLLMClientOption func(*VLLMClient)

// WithVLLMBaseURL allows setting the base URL for the vLLM deployment
func WithVLLMBaseURL(url string) VLLMClientOption {
	return func(c *VLLMClient) {
		c.baseURL = strings.TrimSuffix(url, "/")
	}
}

// WithVLLMAPIKey allows setting an optional API key
func WithVLLMAPIKey(key string) VLLMClientOption {
	return func(c *VLLMClient) {
		c.apiKey = key
	}
}

// WithVLLMModelName allows setting the model name
func WithVLLMModelName(modelName string) VLLMClientOption {
	return func(c *VLLMClient) {
		c.modelName = modelName
	}
}

// WithVLLMUseResponsesAPI allows setting whether to use the Responses API (true) or Chat Completions API (false)
func WithVLLMUseResponsesAPI(useResponses bool) VLLMClientOption {
	return func(c *VLLMClient) {
		c.useResponsesAPI = useResponses
	}
}

// WithVLLMHTTPClient allows injecting a custom HTTP client
func WithVLLMHTTPClient(client HTTPClient) VLLMClientOption {
	return func(c *VLLMClient) {
		c.httpClient = client
	}
}

// WithVLLMDefaultOptions allows setting default completion options
func WithVLLMDefaultOptions(opts *models.CompletionOptions) VLLMClientOption {
	return func(c *VLLMClient) {
		c.defaultOpts = opts
	}
}

// NewVLLMClient creates a new vLLM client with the specified configuration
func NewVLLMClient(retry bool, options ...VLLMClientOption) *VLLMClient {
	client := &VLLMClient{
		httpClient:      &http.Client{Timeout: 10 * time.Minute}, //nolint:exhaustruct // No need for all fields
		useResponsesAPI: false,                                   // Default to using the Chat Completions API
		retry:           retry,
	}

	// Apply options
	for _, option := range options {
		option(client)
	}

	// Ensure baseURL doesn't have a trailing slash (defensive, in case set directly)
	client.baseURL = strings.TrimSuffix(client.baseURL, "/")

	return client
}

// Complete performs a chat completion, using either the Responses API or Chat Completions API
// depending on the client configuration.
func (c *VLLMClient) Complete(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.VLLMClient.Complete")
	defer span.End()

	if c.useResponsesAPI {
		return c.completeWithResponsesAPI(ctx, messages, tools, options)
	}
	return c.completeWithChatCompletionsAPI(ctx, messages, tools, options)
}

// completeWithResponsesAPI handles requests using the /responses endpoint
func (c *VLLMClient) completeWithResponsesAPI(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	fullEndpoint := fmt.Sprintf("%s/responses", c.baseURL)

	enhancedctx.Logger(ctx).Info("Making vLLM responses request", []kvp.Field{
		kvp.String("model", c.modelName),
		kvp.String("endpoint", fullEndpoint),
		kvp.Int("message_count", len(messages)),
		kvp.Int("tools_count", len(tools)),
	}...)

	client := &ResponsesAPIClient{
		fullEndpoint: fullEndpoint,
		providerName: c.GetProviderName(),
		modelName:    c.modelName,
		retry:        c.retry,
		headersFn:    func(ctx context.Context) map[string]string { return c.headers(ctx) },
		httpClient:   c.httpClient,
	}
	return client.Complete(ctx, messages, tools, options)
}

// completeWithChatCompletionsAPI handles requests using the /chat/completions endpoint
func (c *VLLMClient) completeWithChatCompletionsAPI(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	fullEndpoint := fmt.Sprintf("%s/chat/completions", c.baseURL)

	logger := enhancedctx.Logger(ctx)
	logger.Info("Making vLLM chat completions request", []kvp.Field{
		kvp.String("model", c.modelName),
		kvp.String("endpoint", fullEndpoint),
		kvp.Int("message_count", len(messages)),
		kvp.Int("tools_count", len(tools)),
	}...)

	// Default to non-streaming for vLLM
	if options == nil {
		options = &models.CompletionOptions{}
	}
	options = options.Clone()
	if options.Stream == nil {
		stream := false
		options.Stream = &stream
	}

	client := NewChatCompletionsAPIClient(fullEndpoint, c.GetProviderName(), c.GetModelName(), c.retry, c.defaultOpts, WithHTTPClient(c.httpClient)).
		WithHeadersFn(func(ctx context.Context) map[string]string { return c.headers(ctx) })

	return client.Complete(ctx, messages, tools, options)
}

// headers returns the HTTP headers for vLLM requests
func (c *VLLMClient) headers(ctx context.Context) map[string]string {
	headers := map[string]string{
		"Content-Type": "application/json",
	}

	// Add API key if provided
	if c.apiKey != "" {
		headers["api-key"] = c.apiKey
	}

	return headers
}

// GetModelName returns the model name used by this client
func (c *VLLMClient) GetModelName() string {
	return c.modelName
}

// GetProviderName returns the provider name for vLLM
func (c *VLLMClient) GetProviderName() string {
	return "vLLM"
}
