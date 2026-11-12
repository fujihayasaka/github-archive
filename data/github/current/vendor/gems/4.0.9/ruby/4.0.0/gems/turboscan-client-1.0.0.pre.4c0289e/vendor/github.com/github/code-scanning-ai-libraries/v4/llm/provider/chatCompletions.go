package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/github/code-scanning-ai-libraries/v4/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v4/errors"
	"github.com/github/code-scanning-ai-libraries/v4/llm/interactionmeta"
	"github.com/github/code-scanning-ai-libraries/v4/llm/limiter"
	"github.com/github/code-scanning-ai-libraries/v4/llm/models"
	"github.com/github/github-telemetry-go/kvp"
)

// ChatCompletionsAPIClient is a shared, provider-agnostic client for the Chat Completions API.
// Support retry via limiter.WithRetry, streaming (including tool-call deltas), and tool calling with recursive tool execution.
type ChatCompletionsAPIClient struct {
	fullEndpoint string
	providerName string
	modelName    string

	retry bool

	useCacheControl bool

	headersFn  func(ctx context.Context) map[string]string
	httpClient HTTPClient

	sessionManager *SessionRecorderManager
	defaultOptions *models.CompletionOptions
}

// NewChatCompletionsAPIClient creates a new API client for the Chat Completions endpoint.
func NewChatCompletionsAPIClient(fullEndpoint, providerName, modelName string, retry bool, defaultOpts *models.CompletionOptions, options ...ChatCompletionsClientOption) *ChatCompletionsAPIClient {
	var clientOpts *models.CompletionOptions
	if defaultOpts != nil {
		clientOpts = defaultOpts.Clone()
	}
	client := &ChatCompletionsAPIClient{
		fullEndpoint:   fullEndpoint,
		providerName:   providerName,
		modelName:      modelName,
		retry:          retry,
		sessionManager: NewSessionRecorderManager(modelName),
		defaultOptions: clientOpts,
		httpClient:     &http.Client{Timeout: 10 * time.Minute}, //nolint:exhaustruct // No need for all fields
	}

	for _, option := range options {
		option(client)
	}
	return client
}

// WithHeadersFn sets the function used to generate HTTP headers for each request.
func (c *ChatCompletionsAPIClient) WithHeadersFn(headersFn func(ctx context.Context) map[string]string) *ChatCompletionsAPIClient {
	c.headersFn = headersFn
	return c
}

// WithCacheControl enables the copilot_cache_control request fields for providers that support it. (CAPI when calling Anthropic models.)
func (c *ChatCompletionsAPIClient) WithCacheControl() *ChatCompletionsAPIClient {
	c.useCacheControl = true
	return c
}

// Complete sends a chat completion request and handles tool calls recursively.
func (c *ChatCompletionsAPIClient) Complete(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	ctx, span := enhancedctx.StartSpan(ctx, "provider.ChatCompletionsAPIClient.Complete")
	defer span.End()

	if ctx.Err() != nil {
		return "", nil, nil, errors.NewErrorFromContextErr(ctx, "context canceled before request started")
	}

	if c.headersFn == nil {
		return "", nil, nil, errors.NewError("headersFn is required", errors.ErrorTypeLogic)
	}

	if options == nil {
		options = &models.CompletionOptions{}
	}
	options = options.Clone()

	ctx, _, turnErr := enforceMaxTurns(ctx, options)
	if turnErr != nil {
		return "", nil, nil, turnErr
	}

	enhancedctx.InteractionLogger(ctx).LogToModelInteraction(ctx, messages[len(messages)-1].Content)

	// Session recording: Logging of initial user messages (once per request lifecycle, which is handled inside the `RecordUserMessages` method).
	ctx = c.sessionManager.RecordUserMessages(ctx, messages)

	shouldStream := false
	if options.Stream != nil {
		shouldStream = *options.Stream
	}
	options.Stream = &shouldStream

	if c.useCacheControl && len(tools) > 0 {
		last := messages[len(messages)-1]
		last.CopilotCacheControl = &models.CopilotCacheControl{Type: "ephemeral"}
		messages[len(messages)-1] = last
	}

	reqBody := options.ToChatCompletionsMap(ctx)
	reqBody["model"] = c.modelName
	reqBody["stream"] = shouldStream

	if shouldStream {
		reqBody["stream_options"] = map[string]any{
			"include_usage": true,
		}
	}

	if len(tools) > 0 {
		chatCompletionsTools := make([]any, len(tools))
		for i, tool := range tools {
			chatTool, err := tool.ToChatCompletionsTool()
			if err != nil {
				return "", nil, nil, errors.WrapError(err, errors.ErrorTypeLogic, "converting tool to chat completions format")
			}
			if c.useCacheControl && i == len(tools)-1 {
				chatTool["copilot_cache_control"] = &models.CopilotCacheControl{Type: "ephemeral"}
			}
			chatCompletionsTools[i] = chatTool
		}
		reqBody["tools"] = chatCompletionsTools
		reqBody["tool_choice"] = "auto"
		reqBody["parallel_tool_calls"] = true
	}

	reqBody["messages"] = messages

	enhancedctx.Logger(ctx).Info("Making chat completions request", []kvp.Field{
		kvp.String("provider", c.providerName),
		kvp.String("model", c.modelName),
		kvp.Bool("stream", shouldStream),
		kvp.Int("message_count", len(messages)),
		kvp.Int("tools_count", len(tools)),
	}...)

	// Define a result type for limiter.WithRetry
	type requestResult struct {
		messages []models.ChatMessage
		usage    *models.TokenUsage
	}

	var start time.Time
	result, llmErr := limiter.WithRetry(ctx, c.providerName+":"+c.modelName, c.retry, func() (requestResult, errors.LLMError) {
		start = time.Now() // reset on retry
		newMessages, usage, err := c.doRequest(ctx, c.fullEndpoint, c.headersFn(ctx), reqBody, shouldStream)
		return requestResult{messages: newMessages, usage: usage}, err
	})
	if llmErr != nil {
		c.sessionManager.RecordError(ctx, llmErr, &models.TokenUsage{})
		return "", nil, nil, llmErr
	}

	// Update context for subsequent recursive calls (used by CAPI for the initiator header).
	ctx = interactionmeta.MarkCallMade(ctx)

	newMessages := result.messages
	usage := result.usage
	if usage != nil {
		usage.TimeInMs = time.Since(start).Milliseconds()
	}

	if len(newMessages) == 0 {
		return "", nil, nil, errors.NewError("no messages in response", errors.ErrorTypeLogic)
	}

	allMessages := make([]models.ChatMessage, 0, len(messages)+len(newMessages)+len(tools))
	allMessages = append(allMessages, messages...)

	hadToolCalls := false
	for _, msg := range newMessages {
		allMessages = append(allMessages, msg)
		if c.sessionManager != nil &&
			c.sessionManager.HasRecorder(ctx) &&
			(msg.ToolCalls == nil || len(*msg.ToolCalls) == 0) {
			// Record assistant chunks for session recording.
			// Tool results are recorded via RecordToolCallWithResult in executeToolCall.
			c.sessionManager.RecordAssistantChunk(ctx, msg.Content, nil, FinishReasonStop, usage)
		}
		if msg.ToolCalls == nil || len(*msg.ToolCalls) == 0 {
			continue
		}

		hadToolCalls = true
		if len(tools) == 0 {
			return "", nil, nil, errors.NewError("received tool calls in response, but no tools were provided", errors.ErrorTypeLogic)
		}

		for _, toolCall := range *msg.ToolCalls {
			toolResultMsg, err := c.executeToolCall(ctx, toolCall, tools, allMessages)
			if err != nil {
				return "", nil, nil, err
			}
			allMessages = append(allMessages, toolResultMsg)
		}
	}

	if hadToolCalls {
		if options != nil && options.JITInstructions != nil {
			tokenCount := 0
			if usage != nil {
				tokenCount = usage.TotalTokens
			}
			allMessages = options.JITInstructions.InjectInstructionsAfterToolCalls(ctx, allMessages, tokenCount)
		}

		if ctx.Err() != nil {
			return "", nil, nil, errors.NewErrorFromContextErr(ctx, "context canceled before tool call processing completed")
		}

		newResp, newTranscript, newUsage, newErr := c.Complete(ctx, allMessages, tools, options)
		newUsage = models.AggregateTokenUsage(usage, newUsage)
		return newResp, newTranscript, newUsage, newErr
	}

	lastMessage := newMessages[len(newMessages)-1]
	return lastMessage.Content, allMessages, usage, nil
}

func (c *ChatCompletionsAPIClient) executeToolCall(ctx context.Context, toolCall models.ToolCall, tools []models.Tool, allMessages []models.ChatMessage) (models.ChatMessage, errors.LLMError) {
	toolCallMsg := models.ChatMessage{
		CallID:    toolCall.ID,
		Arguments: toolCall.Function.Arguments,
		Name:      toolCall.Function.Name,
	}

	toolOut, toolErr := models.CallTool(ctx, toolCallMsg, tools)
	if toolErr != nil {
		enhancedctx.Logger(ctx).WithError(toolErr).Error("tool execution failed", []kvp.Field{
			kvp.String("tool_name", toolCall.Function.Name),
			kvp.String("tool_call_id", toolCall.ID),
		}...)
		if c.sessionManager != nil {
			c.sessionManager.RecordToolCallWithResult(ctx, toolCall, formatError(toolErr), models.ChatMessage{})
		}
		return models.ChatMessage{}, errors.WrapErrorf(toolErr, errors.ErrorTypeLogic,
			"error while calling tool %s with arguments: %s",
			toolCall.Function.Name, toolCall.Function.Arguments)
	}

	if c.useCacheControl {
		// Anthropic supports a max of 4 cache breakpoints: https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching#when-to-use-multiple-breakpoints
		// Therefore we first we check how many existing breakpoints we have, and remove breakpoints accordingly (starting from the beginning).
		numberOfBreakpoints := 0
		for _, message := range allMessages {
			if message.CopilotCacheControl != nil {
				numberOfBreakpoints++
			}
		}
		if numberOfBreakpoints > 2 {
			for i := range allMessages {
				if allMessages[i].CopilotCacheControl != nil && allMessages[i].Role != models.ChatMessageRoleSystem {
					allMessages[i].CopilotCacheControl = nil // remove the cache control flag
					numberOfBreakpoints--
					if numberOfBreakpoints <= 2 {
						break // stop when we have 2 or fewer breakpoints. We always have a break-point in the tools, and the next `Complete` will add another one. Which gives us the max of 4.
					}
				}
			}
		}
	}

	enhancedctx.Logger(ctx).Info("Tool call completed", []kvp.Field{
		kvp.String("tool_call_id", toolCall.ID),
		kvp.Int("tool_output_size", len(toolOut.Output)),
		kvp.String("tool_name", toolCall.Function.Name),
	}...)
	if c.sessionManager != nil {
		c.sessionManager.RecordToolCallWithResult(ctx, toolCall, toolOut.Output, models.ChatMessage{})
	}

	return models.ChatMessage{
		Role:       "tool",
		ToolCallID: toolCall.ID,
		Content:    toolOut.Output,
	}, nil
}

// HTTPClient defines an interface for HTTP operations
type HTTPClient interface {
	Do(req *http.Request) (*http.Response, error)
}

// ChatCompletionsClientOption defines a function that configures a ChatCompletionsAPIClient.
type ChatCompletionsClientOption func(*ChatCompletionsAPIClient)

// WithHTTPClient allows injecting a custom HTTP client
func WithHTTPClient(client HTTPClient) ChatCompletionsClientOption {
	return func(c *ChatCompletionsAPIClient) {
		c.httpClient = client
	}
}

// WithDefaultOptions allows setting default completion options
func WithDefaultOptions(opts *models.CompletionOptions) ChatCompletionsClientOption {
	return func(c *ChatCompletionsAPIClient) {
		c.defaultOptions = opts
	}
}

// doRequest executes an HTTP POST request to the specified endpoint with the given body.
// It returns the response or an error if the request fails.
func (c *ChatCompletionsAPIClient) doRequest(ctx context.Context, endpoint string, headers map[string]string, requestBody interface{}, stream bool) ([]models.ChatMessage, *models.TokenUsage, errors.LLMError) {
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

	resp, err := c.httpClient.Do(req)
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
		// TODO: No support for tool calling in streaming responses yet.
		content, usage, llmErr := handleStreamResponse(ctx, resp)
		if llmErr != nil {
			return nil, nil, llmErr
		}
		return []models.ChatMessage{
			{
				Role:    models.ChatMessageRoleAssistant,
				Content: content,
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
