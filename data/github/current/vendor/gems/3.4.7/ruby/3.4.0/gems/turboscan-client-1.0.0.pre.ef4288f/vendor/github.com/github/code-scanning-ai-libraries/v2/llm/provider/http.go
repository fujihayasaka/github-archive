// Package provider provides various LLM providers and utilities for these.
package provider

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	go_errors "github.com/pkg/errors"

	"github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/github-telemetry-go/kvp"
)

func handleErrorResponse(ctx context.Context, resp *http.Response, requestJSON []byte) errors.LLMError {
	ctx = withResponseRequestID(ctx, resp)
	if ctx.Err() != nil {
		if go_errors.Is(ctx.Err(), context.Canceled) || go_errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return errors.WrapError(ctx.Err(), errors.ErrorTypeContextCanceled, "Error canceled by client")
		}
	}

	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		enhancedctx.Logger(ctx).WithError(err).Error(
			"Failed to read error response body",
			kvp.Int("http_status_code", resp.StatusCode),
		)

		// if any network issues
		var netErr net.Error
		if go_errors.As(err, &netErr) && netErr.Timeout() {
			return errors.WrapHTTPStatusError(
				err,
				0,
				"network timeout reading response",
				true,
				time.Second*2,
			)
		}

		return errors.NewRetryableError("reading error response", 0)
	}

	var apiError struct {
		Error struct {
			Message string `json:"message"`
			Type    string `json:"type"`
			Code    string `json:"code"`
		} `json:"error"`
	}
	errorMessage := string(body)
	if json.Unmarshal(body, &apiError) == nil && apiError.Error.Message != "" {
		errorMessage = apiError.Error.Message
	}

	// Log the entire body for debugging purposes. This is sensitive information, so we log it as a restricted message.
	restrictedErrorMessage := fmt.Sprintf("autofix API error: %s. full request: %s", errorMessage, string(requestJSON))
	enhancedctx.InteractionLogger(ctx).LogErrorInteraction(ctx, restrictedErrorMessage)

	reqID := resp.Header.Get("X-GitHub-Request-Id")

	// log error with extra context
	enhancedctx.Logger(ctx).Error(
		"HTTP request failed",
		kvp.Int("http_status_code", resp.StatusCode),
		kvp.String("method", "POST"),
		kvp.Int("request_size", len(requestJSON)),
		kvp.Int("response_size", len(body)),
		kvp.String("error_message", errorMessage),
		kvp.String("api_error_type", apiError.Error.Type),
		kvp.String("api_error_code", apiError.Error.Code),
	)

	withReqID := func(msg string) string {
		if reqID == "" {
			return msg
		}
		return fmt.Sprintf("%s (x-github-request-id: %s)", msg, reqID)
	}

	// handles specific status codes
	switch resp.StatusCode {
	case http.StatusBadRequest:
		return errors.NewHTTPStatusError(
			resp.StatusCode,
			withReqID(fmt.Sprintf("bad request: %s", errorMessage)),
			false, // Not retryable
			0,
		)
	case http.StatusUnauthorized, http.StatusForbidden:
		return errors.NewHTTPStatusError(
			resp.StatusCode,
			withReqID(fmt.Sprintf("authentication error: %s", errorMessage)),
			false, // Not retryable
			0,
		)
	case http.StatusTooManyRequests:
		// looks for retry delay from header
		retryAfter := resp.Header.Get("Retry-After")
		var retryDelay time.Duration
		if retryAfter != "" {
			if seconds, err := strconv.Atoi(retryAfter); err == nil {
				retryDelay = time.Duration(seconds) * time.Second
			}
		} else {
			// Look for a string like `Try again in 16 seconds` in the body, and extract retryDelay from that. That's how Azure OpenAI tends to return it.
			re := regexp.MustCompile(`(?i)try again in\s+(\d+)\s+seconds?`)
			if m := re.FindStringSubmatch(string(body)); len(m) == 2 {
				if seconds, err := strconv.Atoi(m[1]); err == nil {
					retryDelay = time.Duration(seconds) * time.Second
				}
			}
		}

		if retryDelay == 0 {
			retryDelay = 5 * time.Second
		}
		return errors.NewHTTPStatusError(
			resp.StatusCode,
			withReqID("rate limited"),
			true, // Retryable
			retryDelay,
		)
	default:
		if !errors.IsRetryableStatusCode(resp.StatusCode) {
			return errors.NewHTTPStatusError(
				resp.StatusCode,
				withReqID(errorMessage),
				false,
				0,
			)
		}
		return errors.NewHTTPStatusError(
			resp.StatusCode,
			withReqID(fmt.Sprintf("unexpected status: %d - %s", resp.StatusCode, errorMessage)),
			true, // Retryable
			time.Second*5,
		)
	}
}

func handleStreamResponse(ctx context.Context, resp *http.Response) (string, *models.TokenUsage, errors.LLMError) {
	ctx = withResponseRequestID(ctx, resp)
	ctx, span := enhancedctx.StartSpan(ctx, "provider.HandleStreamResponse")
	defer span.End()

	var rawResps []models.RawResponse
	reader := bufio.NewReader(resp.Body)

	for {
		line, err := reader.ReadString('\n')
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", nil, errors.WrapRetryableError(err, "reading stream", 0)
		}

		if line = strings.TrimSpace(line); line == "" || line == "data: [DONE]" {
			continue
		}

		line = strings.TrimPrefix(line, "data: ")

		var rawResp models.RawResponse
		if err := json.Unmarshal([]byte(line), &rawResp); err != nil {
			return "", nil, errors.WrapError(
				err,
				errors.ErrorTypeLogic,
				"parsing stream data",
			)
		}

		rawResps = append(rawResps, rawResp)
	}

	headers := extractHeaders(resp)
	response, err := models.ConvertAllResponses(rawResps, map[string]string{
		"retry-after":         headers.RetryAfter,
		"x-github-request-id": headers.RequestID,
	})
	if err != nil {
		var respErr *models.ResponseError
		var errorType = errors.ErrorTypeLogic
		if go_errors.As(err, &respErr) {
			msg := respErr.Message
			if headers.RequestID != "" {
				msg = fmt.Sprintf("%s (x-github-request-id: %s)", msg, headers.RequestID)
			}
			return "", nil, errors.NewHTTPStatusError(respErr.StatusCode, msg, errors.IsRetryableStatusCode(resp.StatusCode), 5)
		}
		return "", nil, errors.WrapError(
			err,
			errorType,
			"converting responses",
		)
	}
	// Note: For requests under 1024 tokens, cached_tokens will be zero.
	// https://platform.openai.com/docs/guides/prompt-caching#requirements
	var cachedTokens *int
	if response.Usage != nil && response.Usage.PromptTokensDetails != nil {
		cachedTokens = response.Usage.PromptTokensDetails.CachedTokens
	}

	enhancedctx.Logger(ctx).Info("read streaming response from model",
		kvp.Any("gh.autofix.finish_reason", response.Payload.FinishReason),
		kvp.Int("gh.autofix.prompt_tokens", response.Usage.PromptTokens),
		kvp.Int("gh.autofix.completion_tokens", response.Usage.CompletionTokens),
		kvp.Int("gh.autofix.total_tokens", response.Usage.TotalTokens),
		kvp.Intp("gh.autofix.prompt_tokens.cached_tokens", cachedTokens),
	)

	enhancedctx.InteractionLogger(ctx).LogFromModelInteraction(
		ctx,
		response.Payload.Text,
		response.Payload.FinishReason,
		response.Cached,
		enhancedctx.TokenUsage{
			PromptTokens:     response.Usage.PromptTokens,
			CompletionTokens: response.Usage.CompletionTokens,
			TotalTokens:      response.Usage.TotalTokens,
		},
		response.Model,
	)

	return response.Payload.Text, response.Usage, nil
}

// handleSingleResponse processes a non-streaming HTTP response from the LLM provider.
// It returns all messages from the response choices array.
//
// While OpenAI's choices field was originally designed to return multiple different
// completions/responses, CAPI (when adapting Anthropic's API to OpenAI's format)
// uses the choices array to represent consecutive messages from a single response.
// For example, Anthropic models may return two messages: an "assistant" message
// (similar to reasoning sections in OpenAI models) followed by the actual tool calls.
//
// This is why we return all messages from choices as a single array - they represent
// a single conversation flow, not alternative responses.
func handleSingleResponse(ctx context.Context, resp *http.Response) ([]models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	ctx = withResponseRequestID(ctx, resp)
	var rawResp models.RawResponse
	if err := json.NewDecoder(resp.Body).Decode(&rawResp); err != nil {
		return nil, nil, errors.WrapError(
			err,
			errors.ErrorTypeLogic,
			"decoding response",
		)
	}

	headers := extractHeaders(resp)
	// Note: With the hacky support for Tools, the result of `models.ConvertResponse` is only used for telemetry, it's not returned.
	// Maybe properly support tool calls, and multiple messages, inside the `models.Response` type, and update `ConvertResponse` accordingly. This is also a good step towards supporting tool calling with streaming responses.
	response, err := models.ConvertResponse(rawResp, map[string]string{
		"retry-after":         headers.RetryAfter,
		"x-github-request-id": headers.RequestID,
	})
	if err != nil {
		var respErr *models.ResponseError
		var errorType = errors.ErrorTypeLogic
		if go_errors.As(err, &respErr) {
			msg := respErr.Message
			if headers.RequestID != "" {
				msg = fmt.Sprintf("%s (x-github-request-id: %s)", msg, headers.RequestID)
			}
			return nil, nil, errors.NewHTTPStatusError(respErr.StatusCode, msg, errors.IsRetryableStatusCode(resp.StatusCode), 5)
		}
		return nil, nil, errors.WrapError(
			err,
			errorType,
			"converting responses",
		)
	}

	// Note: For requests under 1024 tokens, cached_tokens will be zero.
	// https://platform.openai.com/docs/guides/prompt-caching#requirements
	var cachedTokens *int
	if response.Usage.PromptTokensDetails != nil {
		cachedTokens = response.Usage.PromptTokensDetails.CachedTokens
	}
	enhancedctx.Logger(ctx).Info("read non-streaming response from model",
		kvp.Any("gh.autofix.finish_reason", response.Payload.FinishReason),
		kvp.Int("gh.autofix.prompt_tokens", response.Usage.PromptTokens),
		kvp.Int("gh.autofix.completion_tokens", response.Usage.CompletionTokens),
		kvp.Int("gh.autofix.total_tokens", response.Usage.TotalTokens),
		kvp.Intp("gh.autofix.prompt_tokens.cached_tokens", cachedTokens),
	)

	enhancedctx.InteractionLogger(ctx).LogFromModelInteraction(
		ctx,
		response.Payload.Text,
		response.Payload.FinishReason,
		response.Cached,
		enhancedctx.TokenUsage{
			PromptTokens:     response.Usage.PromptTokens,
			CompletionTokens: response.Usage.CompletionTokens,
			TotalTokens:      response.Usage.TotalTokens,
		},
		response.Model,
	)

	res := []models.ChatMessage{}
	for _, choice := range rawResp.Choices {
		res = append(res, *choice.Message)
	}

	return res, response.Usage, nil
}

func extractHeaders(resp *http.Response) models.Headers {
	return models.NewHeaders(map[string]string{
		"retry-after":         resp.Header.Get("Retry-After"),
		"x-github-request-id": resp.Header.Get("X-GitHub-Request-Id"),
	})
}

// isResponseOK checks if the HTTP response status code indicates success.
func isResponseOK(resp *http.Response) bool {
	return resp.StatusCode >= 200 && resp.StatusCode < 300
}
