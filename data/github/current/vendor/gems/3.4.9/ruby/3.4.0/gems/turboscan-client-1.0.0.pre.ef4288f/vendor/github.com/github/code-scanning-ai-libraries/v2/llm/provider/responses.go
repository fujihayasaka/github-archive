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
	"github.com/github/code-scanning-ai-libraries/v2/llm/limiter"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/github-telemetry-go/kvp"
)

// ResponsesAPIClient holds configuration and HTTP client for the Responses API
// Note: This is purposely very close to the `Model` interface, but it doesn't implement it, because it's only mean as a utility for the actual model implementations.
type ResponsesAPIClient struct {
	fullEndpoint string
	modelName    string
	retry        bool
	headersFn    func(context.Context) map[string]string
	httpClient   HTTPClient
}

// doRequest executes the HTTP POST using the client's configuration
func (c *ResponsesAPIClient) doRequest(ctx context.Context, requestJSON []byte) (*http.Response, errors.LLMError) { //nolint:nonamedreturns // keeping style consistent
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.fullEndpoint, bytes.NewReader(requestJSON))
	if err != nil {
		return nil, errors.WrapError(err, errors.ErrorTypeLogic, "creating request")
	}

	for k, v := range c.headersFn(ctx) {
		req.Header.Set(k, v)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, errors.WrapRetryableError(err, "executing request", time.Second*5)
	}

	ctx = withResponseRequestID(ctx, resp)

	if !isResponseOK(resp) {
		defer resp.Body.Close()
		llmErr := handleErrorResponse(ctx, resp, requestJSON)
		enhancedctx.Logger(ctx).WithError(llmErr).Warn(
			"HTTP request failed",
			kvp.Int("http_status_code", resp.StatusCode),
			kvp.String("url", c.fullEndpoint),
		)
		return nil, llmErr
	}

	return resp, nil
}

// ResponsesAPIResponse represents the response structure of the JSON response from the Responses API
type ResponsesAPIResponse struct {
	ID     string               `json:"id"`
	Output []models.ChatMessage `json:"output"`
	Usage  struct {
		InputTokens       int `json:"input_tokens"`
		OutputTokens      int `json:"output_tokens"`
		TotalTokens       int `json:"total_tokens"`
		InputTokenDetails *struct {
			CachedTokens int `json:"cached_tokens"`
		} `json:"input_tokens_details"`
	} `json:"usage"`
}

// Complete sends a request to the Responses API and handles tool calls recursively until completion.
func (c *ResponsesAPIClient) Complete(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) { //nolint:nonamedreturns // keeping style consistent
	ctx, span := enhancedctx.StartSpan(ctx, "llm.AzureHostedAzureGPT.Complete")
	defer span.End()

	if options == nil {
		options = &models.CompletionOptions{}
	}

	for i := range messages {
		messages[i].CopilotCacheControl = nil // Clear Copilot cache control, that is a CAPI specific feature.
	}

	reqBody := options.ToResponsesMap()
	reqBody["input"] = messages
	reqBody["model"] = c.modelName
	reqBody["tools"] = tools

	// https://platform.openai.com/docs/guides/reasoning?api-mode=responses#get_started_with_reasoning
	reasoning, _ := reqBody["reasoning"].(map[string]any) // might already have a "reasoning" object from the opts.
	if reasoning == nil {
		reasoning = map[string]any{}
	}
	reasoning["summary"] = "detailed" // just set a default summary, not effort.
	reqBody["reasoning"] = reasoning

	reqBody["include"] = []string{"reasoning.encrypted_content"} // This way we don't require the backend to preserve any state. Which could be a security concern. See https://platform.openai.com/docs/guides/reasoning/how-reasoning-works?api-mode=responses#encrypted-reasoning-items

	requestJSON, err := json.Marshal(reqBody)
	if err != nil {
		return "", nil, nil, errors.WrapError(err, errors.ErrorTypeLogic, "marshaling request body")
	}

	enhancedctx.Logger(ctx).WithFields(
		kvp.String("url", c.fullEndpoint),
	).Debug("Sending HTTP request")

	var start time.Time
	resp, llmErr := limiter.WithRetry(ctx, c.modelName, c.retry, func() (*http.Response, errors.LLMError) {
		start = time.Now() // Reset on retry.
		return c.doRequest(ctx, requestJSON)
	})

	if llmErr != nil {
		// If we exit the loop with an error, return it
		return "", nil, nil, llmErr
	}

	defer resp.Body.Close()

	ctx = withResponseRequestID(ctx, resp)

	enhancedctx.Logger(ctx).Info("CAPI responses request succeeded",
		kvp.String("url", c.fullEndpoint),
		kvp.String("model", c.modelName),
	)

	// Read the full response body to a string, and then unmarshal it
	var responseBody bytes.Buffer
	if _, err := responseBody.ReadFrom(resp.Body); err != nil {
		return "", nil, nil, errors.WrapError(err, errors.ErrorTypeLogic, "reading response body")
	}

	var response ResponsesAPIResponse
	if err := json.Unmarshal(responseBody.Bytes(), &response); err != nil {
		return "", nil, nil, errors.WrapError(err, errors.ErrorTypeLogic, "unmarshaling response body")
	}

	responseMessages := response.Output
	usage := &models.TokenUsage{
		PromptTokens:     response.Usage.InputTokens,
		CompletionTokens: response.Usage.OutputTokens,
		TotalTokens:      response.Usage.TotalTokens,
		TimeInMs:         time.Since(start).Milliseconds(),
	}

	if response.Usage.InputTokenDetails != nil && response.Usage.InputTokenDetails.CachedTokens != 0 {
		usage.PromptTokensDetails = &models.PromptTokensDetails{
			CachedTokens: &response.Usage.InputTokenDetails.CachedTokens,
		}
	}

	toolOutputs := make([]models.ChatMessage, 0)
	for _, msg := range responseMessages {
		if msg.Type != "function_call" {
			continue
		}

		toolOutput, err := models.CallTool(msg, tools)
		if err != nil {
			return "", nil, nil, err
		}

		toolOutputs = append(toolOutputs, toolOutput)
	}
	responseMessages = append(responseMessages, toolOutputs...)

	// the entire transcript, the original messages, the response, and any tool outputs
	transcript := make([]models.ChatMessage, 0, len(messages)+len(responseMessages))
	transcript = append(transcript, messages...)
	transcript = append(transcript, responseMessages...)

	if len(toolOutputs) > 0 {
		// If there are tool outputs, we need to recursively ask the model to complete the request.

		// There is an argument here for not recursing, and letting the client handle that. Because recursing means we cannot cache/retry the individual requests.
		// However! The transcript cannot be replayed later, because the "reasoning" sections do not contain the raw reasoning, they only contain an ID/summary, which is not stored forever on the backend.
		// If allow for caching we can therefore end up with a situation where the model is asked to complete a request, but the reasoning sections are not available anymore.
		// Therefore! We run the request to completion before returning to the client.
		// However, we can consider allowing for some light-weight retrying within this LLM integration.
		newResp, newTranscript, newUsage, newLlmErr := c.Complete(ctx, transcript, tools, options)
		newUsage = models.AggregateTokenUsage(usage, newUsage)
		return newResp, newTranscript, newUsage, newLlmErr
	}

	// Return the content of the last message in the response
	if len(responseMessages) == 0 {
		return "", nil, nil, errors.NewError("no messages in response", errors.ErrorTypeLogic)
	}

	lastMessage := responseMessages[len(responseMessages)-1]
	if lastMessage.Type != "message" {
		return "", nil, nil, errors.NewError(fmt.Sprintf("last message is not a \"message\", got: %s", lastMessage.Type), errors.ErrorTypeLogic)
	}

	return lastMessage.Content, transcript, usage, nil
}
