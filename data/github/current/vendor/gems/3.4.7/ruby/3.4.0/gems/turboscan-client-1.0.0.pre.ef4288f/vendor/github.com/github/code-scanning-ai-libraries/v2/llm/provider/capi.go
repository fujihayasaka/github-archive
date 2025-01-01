// Package provider provides a client for GitHub Copilot API (CAPI)
package provider

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"regexp"
	"slices"
	"strings"
	"time"

	pkg_errors "github.com/pkg/errors"

	"github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/code-scanning-ai-libraries/v2/llm/config"
	"github.com/github/code-scanning-ai-libraries/v2/llm/limiter"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/github-telemetry-go/kvp"
)

const (
	// DefaultCapiURL is the default base URL for the GitHub Copilot API
	DefaultCapiURL = "https://api.githubcopilot.com"
	// DefaultIntegrationID is the default integration ID for production environments
	DefaultIntegrationID = "ghas-code-scanning-autofix"
	// DefaultIntegrationIDDev is the default integration ID for development environments
	DefaultIntegrationIDDev = "code-scanning-ai-dev"
)

// ClientOption defines a function that configures a CAPIClient
type ClientOption func(*CAPIClient)

// WithRegistry allows injecting a model registry
func WithRegistry(registry ModelRegistry) ClientOption {
	return func(c *CAPIClient) {
		c.registry = registry
	}
}

// WithIntegrationID allows setting a custom integration ID
func WithIntegrationID(integrationID string) ClientOption {
	return func(c *CAPIClient) {
		c.integrationID = integrationID
	}
}

// WithURL allows injecting an API URL
func WithURL(url string) ClientOption {
	return func(c *CAPIClient) {
		c.baseURL = url
	}
}

// WithAPIKey allows setting a custom API key
func WithAPIKey(apiKey string) ClientOption {
	return func(c *CAPIClient) {
		c.apiKey = apiKey
	}
}

// WithModelName allows setting a custom model name
func WithModelName(modelName string) ClientOption {
	return func(c *CAPIClient) {
		c.modelName = modelName
	}
}

// CAPIClient implements CAPI-specific functionality
type CAPIClient struct {
	*ChatCompletionsClient
	registry        ModelRegistry
	integrationID   string
	modelName       string
	modelGeneration string
	baseURL         string
	apiKey          string
	modelEntry      *models.ModelEntry
	flavor          string
	retry           bool
	useResponsesAPI bool
}

// headers provides CAPI-specific HTTP headers
func (c *CAPIClient) headers() map[string]string {
	headers := map[string]string{
		"Content-Type":           "application/json",
		"Copilot-Integration-Id": c.integrationID,
	}

	if isAccessToken(c.apiKey) {
		// Use the API key as a Bearer token for access tokens
		headers["Authorization"] = "Bearer " + c.apiKey
	} else {
		headers["Request-Hmac"] = generateHMAC(c.apiKey)
	}

	return headers
}

// NewCapiClient creates a new CAPI client with the specified flavor and configuration
func NewCapiClient(
	flavor string, // capi-dev-<name> or capi-prod-<name>
	retry bool, // whether to enable retry logic
	cfg *config.ModelConfig,
	options ...ClientOption,
) (*CAPIClient, error) {
	// Create with defaults
	client := &CAPIClient{ //nolint:exhaustruct // not all fields are initialized here, set later
		baseURL: DefaultCapiURL,
		flavor:  flavor,
		retry:   retry,
	}

	// Apply options
	for _, option := range options {
		option(client)
	}

	// Set required fields from config if not provided via options
	if client.apiKey == "" {
		isProd := strings.HasPrefix(flavor, "prod")
		if isProd {
			client.apiKey = cfg.CAPIProdKey
		} else {
			client.apiKey = cfg.CAPIDevKey
		}
	}

	// If cfg.CAPIURL is provided, override the default baseURL.
	// This allows customization of the API endpoint, e.g., for Proxima stamps.
	if cfg.CAPIURL != "" {
		client.baseURL = cfg.CAPIURL
	}

	if client.apiKey == "" {
		return nil, pkg_errors.Errorf("no Copilot API key provided for %s", flavor)
	}

	// Initialize ChatCompletionsClient if not provided
	if client.ChatCompletionsClient == nil {
		client.ChatCompletionsClient = NewChatCompletionsClient(cfg.DefaultCompletionOptions)
	}

	// Get model entry - if not provided in options
	if client.modelEntry == nil {
		var registry ModelRegistry

		// Use injected registry if available, otherwise get default registry
		if client.registry != nil {
			registry = client.registry
		} else {
			var err errors.LLMError
			registry, err = models.GetRegistry()
			if err != nil {
				return nil, pkg_errors.Wrap(err, "failed to initialize model registry")
			}
		}

		if client.modelName == "" {
			// Get model name first
			client.modelName = getModelName(flavor)
		}

		// Try to find capabilities in the registry
		model, found := registry.GetModel(client.modelName)
		if !found {
			return nil, pkg_errors.Errorf("model %s not found in registry. Ensure models.json is up-to-date (see capiModelConstants.ts)", client.modelName)
		}
		client.modelEntry = model
	}
	// Always ensure limits are set
	ensureCapabilitiesLimits(client.modelEntry.Capabilities)

	// Check the magic environment variable, and guard Responses API usage behind it. Because the Responses API currently require a FF to be enabled for the user.
	// And only enable if the model supports the Responses API.
	if strings.TrimSpace(os.Getenv("USE_RESPONSES_API")) == "true" && client.modelEntry.SupportedEndpoints != nil && slices.Contains(*client.modelEntry.SupportedEndpoints, "/responses") {
		client.useResponsesAPI = true
	}

	// Set model generation
	client.modelGeneration = client.modelEntry.Capabilities.Family

	// Set integrationID if not provided
	if client.integrationID == "" {
		isProd := strings.HasPrefix(flavor, "prod")
		if isProd {
			client.integrationID = cfg.CAPIIntegrationID
			if client.integrationID == "" {
				client.integrationID = DefaultIntegrationID
			}
		} else {
			client.integrationID = cfg.CAPIIntegrationIDDev
			if client.integrationID == "" {
				client.integrationID = DefaultIntegrationIDDev
			}
		}
	}

	return client, nil
}

// ensureCapabilitiesLimits makes sure the capabilities has Limits initialized
func ensureCapabilitiesLimits(caps *models.ModelCapabilities) {
	if caps == nil {
		return
	}

	if caps.Limits == nil {
		caps.Limits = &models.ModelLimits{ //nolint:exhaustruct // only setting defaults, other fields are optional
			MaxContextWindowTokens: 128000,
			MaxOutputTokens:        4096,
			MaxPromptTokens:        64000,
		}
	}
}

// GetModelName returns the name of the model used by this client
func (c *CAPIClient) GetModelName() string {
	return c.modelName
}

// GetProviderName returns the integration name for this client
func (c *CAPIClient) GetProviderName() string {
	if c.useResponsesAPI {
		return "CAPI (Responses API)"
	}
	return "CAPI"
}

func getModelName(flavor string) string {
	// Strip the dev- or prod- prefix from the flavor
	re := regexp.MustCompile(`^(dev|prod)-`)
	modelName := re.ReplaceAllString(flavor, "")

	// for backwards compatibility, support some aliases we've used in the past.
	switch modelName {
	case "4o":
		modelName = "gpt-4o"
	case "4o-mini":
		modelName = "gpt-4o-mini"
	case "4.1":
		modelName = "gpt-4.1"
	}

	return modelName
}

// Complete sends an LLM completion request with tools support
// If the model responds with tool calls, this will:
// 1. Execute each requested tool
// 2. Add the tool responses to the messages
// 3. Recursively call the API with the updated messages until no more tool calls are requested
func (c *CAPIClient) Complete(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) { //nolint:maintidx // Yes, this function is complex.
	ctx, span := enhancedctx.StartSpan(ctx, "llm.CAPIClient.Complete")
	defer span.End()

	if ctx.Err() != nil {
		return "", nil, nil, errors.NewError("context cancelled", errors.ErrorTypeContextCanceled)
	}

	logger := enhancedctx.Logger(ctx)

	// Use the Responses API, but only if enabled and if supported by the model. (We only set the `useResponsesAPI` flag if the model supports it).
	if c.useResponsesAPI {
		logger.Info("Making CAPI responses request", []kvp.Field{
			kvp.String("model", c.modelName),
			kvp.Int("message_count", len(messages)),
			kvp.Int("tools_count", len(tools)),
			kvp.Any("options", options.ToResponsesMap()),
		}...)

		client := &ResponsesAPIClient{
			fullEndpoint: c.baseURL + "/responses",
			modelName:    c.GetModelName(),
			retry:        c.retry,
			headersFn:    func(ctx context.Context) map[string]string { return c.headers() },
			httpClient:   c.httpClient,
		}
		return client.Complete(ctx, messages, tools, options)
	}

	return c.doChatCompletionsCall(ctx, messages, tools, options)
}

func (c *CAPIClient) doChatCompletionsCall(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) { //nolint:maintidx // Yes, this function is complex.
	logger := enhancedctx.Logger(ctx)

	if options == nil {
		options = &models.CompletionOptions{}
	}

	// Clone the options to avoid modifying the original
	// Based on the models capabilities, we may set for example, the stream option to false.
	options = options.Clone()

	// If the user did not specify a streaming preference, we default to true.
	var shouldStream bool
	if options.Stream != nil {
		// set to user preference
		shouldStream = *options.Stream
	} else {
		shouldStream = true
	}

	// Override streaming setting regardless of user preference for tools support
	// because tool calling with streaming isn't supported yet.
	if !c.modelEntry.Capabilities.Supports.Streaming || len(tools) > 0 {
		// Disable streaming if either:
		// 1. The model doesn't support it, or
		// 2. Tools are provided (tool calling with streaming isn't supported yet)
		shouldStream = false
	}

	options.Stream = &shouldStream

	reqBody := options.ToChatCompletionsMap(ctx)
	reqBody["model"] = c.modelName
	reqBody["stream"] = shouldStream

	if len(tools) > 0 {
		chatCompletionTools := make([]any, len(tools))
		for i, tool := range tools {
			chatCompletionTools[i] = tool.ToChatCompletionsTool()
		}
		reqBody["tools"] = chatCompletionTools
		reqBody["tool_choice"] = "auto"
		reqBody["parallel_tool_calls"] = true
		// Set the flag for CAPI to handle caching, because we expect the cache to be used when tools are enabled. For when CAPI supports the cache flag on user messages.
		messages[len(messages)-1].CopilotCacheControl = &models.CopilotCacheControl{
			Type: "ephemeral",
		}
	}

	reqBody["messages"] = messages

	if shouldStream {
		reqBody["stream_options"] = map[string]any{
			"include_usage": true,
		}
	}

	logger.Info("Making CAPI chat request", []kvp.Field{
		kvp.String("model", c.modelName),
		kvp.Bool("stream", shouldStream),
		kvp.Int("message_count", len(messages)),
		kvp.Any("options", options.ToChatCompletionsMap(ctx)),
	}...)
	enhancedctx.InteractionLogger(ctx).LogToModelInteraction(ctx, messages[len(messages)-1].Content)

	// Define a result type for the retry function
	type requestResult struct {
		messages []models.ChatMessage
		usage    *models.TokenUsage
	}

	var start time.Time
	result, llmErr := limiter.WithRetry(ctx, c.GetModelName(), c.retry, func() (requestResult, errors.LLMError) {
		start = time.Now() // Reset on retry.
		newMessages, usage, err := c.ChatCompletionsClient.doRequest(ctx, c.baseURL+"/chat/completions", c.headers(), reqBody, *options.Stream)
		return requestResult{messages: newMessages, usage: usage}, err
	})

	if llmErr != nil {
		logger.Error("API request failed", []kvp.Field{
			kvp.String("error_type", llmErr.Type()),
			kvp.String("error_message", llmErr.Error()),
			kvp.Bool("retryable", llmErr.Retryable()),
		}...)
		return "", nil, nil, llmErr
	}

	newMessages := result.messages
	usage := result.usage
	usage.TimeInMs = time.Since(start).Milliseconds()

	allMessages := make([]models.ChatMessage, 0, len(messages)+len(newMessages))
	// copies the original messages
	allMessages = append(allMessages, messages...)
	// adds the new messages
	allMessages = append(allMessages, newMessages...)

	if len(newMessages) == 0 {
		return "", nil, nil, errors.NewError("no messages in response", errors.ErrorTypeLogic)
	}

	lastMessage := newMessages[len(newMessages)-1]

	if lastMessage.ToolCalls != nil && len(*lastMessage.ToolCalls) == 0 {
		return "", nil, nil, errors.NewError("received tool calls in response, but no tools were provided to the LLM integration", errors.ErrorTypeLogic)
	}

	if lastMessage.ToolCalls != nil && len(*lastMessage.ToolCalls) > 0 { //nolint:nestif // Yes, there is a bunch of logic, that's OK for now.
		for _, toolCall := range *lastMessage.ToolCalls {
			// Convert the Chat Completions message we have here to the Responses API format, which is what the `models.CallTool` expects.
			toolCallMsg := models.ChatMessage{
				CallID:    toolCall.ID,
				Arguments: toolCall.Function.Arguments,
				Name:      toolCall.Function.Name,
			}

			toolOut, toolErr := models.CallTool(toolCallMsg, tools)
			if toolErr != nil {
				return "", nil, nil, errors.WrapErrorf(toolErr, errors.ErrorTypeLogic,
					"error while calling tool %s with arguments: %s",
					toolCall.ID, toolCall.Function.Arguments)
			}

			// Anthropic supports a max of 4 cache breakpoints: https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching#when-to-use-multiple-breakpoints
			// Therefore we first we check how many existing breakpoints we have, and remove breakpoints accordingly (starting from the beginning).
			numberOfBreakpoints := 0
			for _, message := range allMessages {
				if message.CopilotCacheControl != nil {
					numberOfBreakpoints++
				}
			}
			if numberOfBreakpoints > 3 {
				for i := range allMessages {
					if allMessages[i].CopilotCacheControl != nil && allMessages[i].Role != "system" {
						allMessages[i].CopilotCacheControl = nil // remove the cache control flag
						numberOfBreakpoints--
						if numberOfBreakpoints <= 3 {
							break // stop when we have 3 or fewer breakpoints. We're adding the fourth one below.
						}
					}
				}
			}

			logger.Info("Tool call completed", []kvp.Field{
				kvp.String("tool_call_id", toolCall.ID),
				kvp.Int("tool_output_size", len(toolOut.Output)),
				kvp.String("tool_name", toolCall.Function.Name),
			}...)
			// Convert back to a Chat Completions API response
			allMessages = append(allMessages, models.ChatMessage{
				Role:       "tool",
				ToolCallID: toolCall.ID,
				Content:    toolOut.Output,
				// Set the flag for CAPI to handle caching correctly
				CopilotCacheControl: &models.CopilotCacheControl{
					Type: "ephemeral",
				},
			})
		}

		// And recursively call the API with the updated messages
		logger.Info("Recursively calling CAPI with updated messages after tool calls", []kvp.Field{
			kvp.Int("message_count", len(allMessages)),
		}...)

		if ctx.Err() != nil {
			return "", nil, nil, errors.NewErrorFromContextErr(ctx, "context canceled before tool call processing completed")
		}

		newResp, newTranscript, newUsage, newLlmErr := c.doChatCompletionsCall(ctx, allMessages, tools, options)
		newUsage = models.AggregateTokenUsage(usage, newUsage)
		return newResp, newTranscript, newUsage, newLlmErr
	}
	logger.Info("API request succeeded", []kvp.Field{
		kvp.Int("new_messages", len(newMessages)),
		kvp.Int("prompt_tokens", usage.PromptTokens),
		kvp.Int("completion_tokens", usage.CompletionTokens),
		kvp.Int("total_tokens", usage.TotalTokens),
	}...)
	return lastMessage.Content, allMessages, usage, llmErr
}

func isAccessToken(key string) bool {
	re := regexp.MustCompile(`^(ghp_|github_pat_|gho_|ghu_)`)
	return re.MatchString(key)
}

func generateHMAC(apiKey string) string {
	current := time.Now().Unix()
	h := hmac.New(sha256.New, []byte(apiKey))
	_, _ = fmt.Fprintf(h, "%d", current)
	hmacValue := hex.EncodeToString(h.Sum(nil))
	return fmt.Sprintf("%d.%s", current, hmacValue)
}
