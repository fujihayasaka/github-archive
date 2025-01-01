package provider

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/github/codeml-autofix/go/pkg/autofix"
	"github.com/github/codeml-autofix/go/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/models"
	"github.com/github/github-telemetry-go/kvp"
)

var retryableStatusCodes = map[int]bool{
	-1: true, 0: true, 408: true, 429: true,
	500: true, 502: true, 503: true, 504: true, 520: true,
}

func isRetryableStatusCode(code int) bool {
	return retryableStatusCodes[code]
}

func handleErrorResponse(ctx context.Context, resp *http.Response, requestJSON []byte) autofix.AutofixError {
	if ctx.Err() != nil {
		if errors.Is(ctx.Err(), context.Canceled) || errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return autofix.NewContextCanceledError("request canceled by client", ctx.Err())
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
		if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
			return autofix.NewHTTPStatusError(
				0,
				fmt.Sprintf("network timeout reading response: %v", err),
				true,
				time.Second*2,
			)
		}

		return autofix.NewRetryableError("reading error response", time.Second)
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

	// looks for retry delay from header
	retryAfter := resp.Header.Get("Retry-After")
	var retryDelay time.Duration
	if retryAfter != "" {
		if seconds, err := strconv.Atoi(retryAfter); err == nil {
			retryDelay = time.Duration(seconds) * time.Second
		}
	}

	// handles specific status codes
	switch resp.StatusCode {
	case http.StatusBadRequest:
		return autofix.NewHTTPStatusError(
			resp.StatusCode,
			fmt.Sprintf("bad request: %s", errorMessage),
			false, // Not retryable
			0,
		)
	case http.StatusUnauthorized, http.StatusForbidden:
		return autofix.NewHTTPStatusError(
			resp.StatusCode,
			fmt.Sprintf("authentication error: %s", errorMessage),
			false, // Not retryable
			0,
		)
	case http.StatusTooManyRequests:
		if retryDelay == 0 {
			retryDelay = 30 * time.Second
		}
		return autofix.NewHTTPStatusError(
			resp.StatusCode,
			"rate limited",
			true, // Retryable
			retryDelay,
		)
	default:
		if !isRetryableStatusCode(resp.StatusCode) {
			return autofix.NewHTTPStatusError(
				resp.StatusCode,
				errorMessage,
				false,
				0,
			)
		}
		return autofix.NewHTTPStatusError(
			resp.StatusCode,
			fmt.Sprintf("unexpected status: %d - %s", resp.StatusCode, errorMessage),
			true, // Retryable
			time.Second*5,
		)
	}
}

func handleStreamResponse(ctx context.Context, resp *http.Response) (string, autofix.AutofixError) {
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
			return "", autofix.NewRetryableError(
				fmt.Sprintf("reading stream: %v", err),
				time.Second*5,
			)
		}

		if line = strings.TrimSpace(line); line == "" || line == "data: [DONE]" {
			continue
		}

		line = strings.TrimPrefix(line, "data: ")

		var rawResp models.RawResponse
		if err := json.Unmarshal([]byte(line), &rawResp); err != nil {
			return "", autofix.NewLogicError(
				fmt.Sprintf("parsing stream data: %v", err),
			)
		}

		rawResps = append(rawResps, rawResp)
	}

	headers := extractHeaders(resp)
	response, err := models.ConvertAllResponses(rawResps, map[string]string{
		"retry-after": headers.RetryAfter,
	})
	if err != nil {
		return "", autofix.NewLogicError(
			fmt.Sprintf("converting responses: %v", err),
		)
	}

	enhancedctx.Logger(ctx).Info("read streaming response from model",
		kvp.Any("gh.autofix.finish_reason", response.Payload.FinishReason),
		kvp.Int("gh.autofix.prompt_tokens", response.Usage.PromptTokens),
		kvp.Int("gh.autofix.completion_tokens", response.Usage.CompletionTokens),
		kvp.Int("gh.autofix.total_tokens", response.Usage.TotalTokens))

	return response.Payload.Text, nil
}

func handleSingleResponse(ctx context.Context, resp *http.Response) (string, autofix.AutofixError) {
	var rawResp models.RawResponse
	if err := json.NewDecoder(resp.Body).Decode(&rawResp); err != nil {
		return "", autofix.NewLogicError(
			fmt.Sprintf("decoding response: %v", err),
		)
	}

	headers := extractHeaders(resp)
	response, err := models.ConvertResponse(rawResp, map[string]string{
		"retry-after": headers.RetryAfter,
	})
	if err != nil {
		return "", autofix.NewLogicError(
			fmt.Sprintf("converting response: %v", err),
		)
	}

	enhancedctx.Logger(ctx).Info("read non-streaming response from model",
		kvp.Any("gh.autofix.finish_reason", response.Payload.FinishReason),
		kvp.Int("gh.autofix.prompt_tokens", response.Usage.PromptTokens),
		kvp.Int("gh.autofix.completion_tokens", response.Usage.CompletionTokens),
		kvp.Int("gh.autofix.total_tokens", response.Usage.TotalTokens))

	return response.Payload.Text, nil
}

func extractHeaders(resp *http.Response) models.Headers {
	return models.NewHeaders(map[string]string{
		"retry-after": resp.Header.Get("Retry-After"),
	})
}

// isResponseOK checks if the HTTP response status code indicates success.
func isResponseOK(resp *http.Response) bool {
	return resp.StatusCode >= 200 && resp.StatusCode < 300
}
