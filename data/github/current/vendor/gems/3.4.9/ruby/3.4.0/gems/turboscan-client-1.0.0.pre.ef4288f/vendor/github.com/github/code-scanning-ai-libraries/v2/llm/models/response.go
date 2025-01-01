package models

import (
	"errors"
	"fmt"
	"strings"
)

// Response represents a processed LLM response with payload, usage statistics, and metadata.
type Response struct {
	Payload Payload     `json:"payload"`
	Usage   *TokenUsage `json:"usage"`
	Cached  bool        `json:"cached"`
	ID      string      `json:"id,omitempty"`
	Model   string      `json:"model,omitempty"`
	Headers Headers     `json:"headers"`
}

// Payload contains the actual text content and finish reason from an LLM response.
type Payload struct {
	Text         string `json:"text"`
	FinishReason string `json:"finish_reason,omitempty"`
}

// TokenUsage represents token consumption statistics for an LLM request.
type TokenUsage struct {
	PromptTokens        int                  `json:"prompt_tokens"`
	CompletionTokens    int                  `json:"completion_tokens"`
	TotalTokens         int                  `json:"total_tokens"`
	PromptTokensDetails *PromptTokensDetails `json:"prompt_tokens_details,omitempty"`
	TimeInMs            int64                `json:"time_in_ms"`
}

// PromptTokensDetails contains details about tokens retrieved through cache hits
type PromptTokensDetails struct {
	CachedTokens *int `json:"cached_tokens,omitempty"`
}

// Headers contains HTTP response headers from the LLM provider.
type Headers struct {
	RetryAfter string `json:"retry_after,omitempty"`
	RequestID  string `json:"x_github_request_id,omitempty"`
}

// NewHeaders creates a Headers struct from a map of header values.
func NewHeaders(headers map[string]string) Headers {
	return Headers{
		RetryAfter: headers["retry-after"],
		RequestID:  headers["x-github-request-id"],
	}
}

// RawResponse represents the raw response structure from LLM providers.
type RawResponse struct {
	Choices []Choice     `json:"choices"`
	Usage   *TokenUsage  `json:"usage,omitempty"`
	Model   string       `json:"model,omitempty"`
	ID      string       `json:"id,omitempty"`
	Error   *ErrorDetail `json:"error,omitempty"`
}

// ErrorDetail contains error information from LLM provider responses.
type ErrorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Body    string `json:"body"`
}

// Choice represents a single choice/completion from an LLM response.
type Choice struct {
	Message      *ChatMessage `json:"message,omitempty"`
	Delta        *ChatMessage `json:"delta,omitempty"`
	Text         string       `json:"text,omitempty"`
	FinishReason string       `json:"finish_reason,omitempty"`
}

// ResponseError represents an error response from the LLM service.
type ResponseError struct {
	StatusCode int     `json:"status_code"`
	Message    string  `json:"message"`
	Body       string  `json:"body"`
	Headers    Headers `json:"headers"`
}

func (e *ResponseError) Error() string {
	return fmt.Sprintf("status %d: %s", e.StatusCode, e.Message)
}

// ConvertResponse converts a raw LLM response to the standardized Response format.
func ConvertResponse(rawResp RawResponse, headers map[string]string) (*Response, error) {
	// Handle error responses
	if rawResp.Error != nil {
		return nil, &ResponseError{
			StatusCode: 400,
			Message:    rawResp.Error.Message,
			Body:       rawResp.Error.Body,
			Headers:    NewHeaders(headers),
		}
	}

	// Handle empty responses
	if len(rawResp.Choices) == 0 {
		return nil, errors.New("no choices in response")
	}

	choice := rawResp.Choices[0]
	var text string

	// Extract text from choice using same logic as the TS code.
	switch {
	case choice.Delta != nil && choice.Delta.Content != "":
		text = choice.Delta.Content
	case choice.Text != "":
		text = choice.Text
	case choice.Message != nil:
		text = choice.Message.Content
	}

	// Check for content filter
	if choice.FinishReason == "content_filter" {
		return nil, &ResponseError{
			StatusCode: 422,
			Message:    "Response filtered",
			Body:       "The response was filtered due to content safety",
			Headers:    NewHeaders(headers),
		}
	}

	return &Response{
		Payload: Payload{
			Text:         text,
			FinishReason: choice.FinishReason,
		},
		Usage:   rawResp.Usage,
		Cached:  false,
		ID:      rawResp.ID,
		Model:   rawResp.Model,
		Headers: NewHeaders(headers),
	}, nil
}

// ConvertAllResponses converts multiple raw responses into a single consolidated Response.
func ConvertAllResponses(rawResponses []RawResponse, headers map[string]string) (*Response, error) {
	if len(rawResponses) == 0 {
		return nil, errors.New("response is empty")
	}

	var convertedText []string
	totalUsage := new(TokenUsage)
	var lastSuccessfulResponse *RawResponse

	for _, rawResp := range rawResponses {
		resp, err := ConvertResponse(rawResp, headers)
		if err != nil {
			var respErr *ResponseError
			if errors.As(err, &respErr) {
				return nil, respErr
			}
			continue
		}

		if resp.Payload.Text != "" {
			convertedText = append(convertedText, resp.Payload.Text)
			lastSuccessfulResponse = &rawResp
		}

		// Accumulate usage statistics
		if rawResp.Usage != nil {
			totalUsage.PromptTokens += rawResp.Usage.PromptTokens
			totalUsage.CompletionTokens += rawResp.Usage.CompletionTokens
			totalUsage.TotalTokens += rawResp.Usage.TotalTokens

			if rawResp.Usage.PromptTokensDetails != nil && rawResp.Usage.PromptTokensDetails.CachedTokens != nil {
				if totalUsage.PromptTokensDetails == nil {
					totalUsage.PromptTokensDetails = &PromptTokensDetails{}
				}

				if totalUsage.PromptTokensDetails.CachedTokens == nil {
					cachedTokens := *rawResp.Usage.PromptTokensDetails.CachedTokens
					totalUsage.PromptTokensDetails.CachedTokens = &cachedTokens
				} else {
					cachedTokens := *totalUsage.PromptTokensDetails.CachedTokens + *rawResp.Usage.PromptTokensDetails.CachedTokens
					totalUsage.PromptTokensDetails.CachedTokens = &cachedTokens
				}
			}
		}
	}

	if len(convertedText) == 0 || lastSuccessfulResponse == nil {
		return nil, errors.New("no successful responses")
	}

	return &Response{
		Payload: Payload{
			Text:         strings.Join(convertedText, ""),
			FinishReason: lastSuccessfulResponse.Choices[0].FinishReason,
		},
		Usage:   totalUsage,
		Cached:  false,
		ID:      lastSuccessfulResponse.ID,
		Model:   lastSuccessfulResponse.Model,
		Headers: NewHeaders(headers),
	}, nil
}

// AggregateTokenUsage sums up multiple TokenUsage instances into a single one.
// If all inputs are nil, returns nil. Otherwise returns a new TokenUsage with the sum.
//
// Example:
//
//	usage1 := &TokenUsage{
//		PromptTokens: 10,
//		CompletionTokens: 5,
//		TotalTokens: 15,
//		PromptTokensDetails: &PromptTokensDetails{CachedTokens: 3}
//	}
//	usage2 := &TokenUsage{
//		PromptTokens: 20,
//		CompletionTokens: 8,
//		TotalTokens: 28,
//		PromptTokensDetails: &PromptTokensDetails{CachedTokens: 7}
//	}
//	result := AggregateTokenUsage(usage1, usage2)
//	result = &TokenUsage{
//		PromptTokens: 30,
//		CompletionTokens: 13,
//		TotalTokens: 43,
//		PromptTokensDetails: &PromptTokensDetails{CachedTokens: 10}
//	}
func AggregateTokenUsage(usages ...*TokenUsage) *TokenUsage {
	var total *TokenUsage
	var totalCachedTokens *int

	for _, usage := range usages {
		if usage == nil {
			continue
		}
		if total == nil {
			total = &TokenUsage{}
		}
		total.PromptTokens += usage.PromptTokens
		total.CompletionTokens += usage.CompletionTokens
		total.TotalTokens += usage.TotalTokens
		total.TimeInMs += usage.TimeInMs

		// Aggregate PromptTokensDetails if present
		if usage.PromptTokensDetails != nil && usage.PromptTokensDetails.CachedTokens != nil {
			if totalCachedTokens == nil {
				cached := 0
				totalCachedTokens = &cached
			}
			*totalCachedTokens += *usage.PromptTokensDetails.CachedTokens
		}
	}

	// Set the aggregated PromptTokensDetails if we found any cached tokens
	if total != nil && totalCachedTokens != nil {
		total.PromptTokensDetails = &PromptTokensDetails{
			CachedTokens: totalCachedTokens,
		}
	}

	return total
}
