package models

import (
	"fmt"
	"strings"
)

type Response struct {
	Payload Payload     `json:"payload"`
	Usage   *TokenUsage `json:"usage"`
	Cached  bool        `json:"cached"`
	ID      string      `json:"id,omitempty"`
	Model   string      `json:"model,omitempty"`
	Headers Headers     `json:"headers"`
}

type Payload struct {
	Text         string `json:"text"`
	FinishReason string `json:"finish_reason,omitempty"`
}

type TokenUsage struct {
	PromptTokens     int `json:"prompt_tokens"`
	CompletionTokens int `json:"completion_tokens"`
	TotalTokens      int `json:"total_tokens"`
}

type Headers struct {
	RetryAfter string `json:"retry_after,omitempty"`
}

func NewHeaders(headers map[string]string) Headers {
	return Headers{
		RetryAfter: headers["retry-after"],
	}
}

type RawResponse struct {
	Choices []Choice     `json:"choices"`
	Usage   *TokenUsage  `json:"usage,omitempty"`
	Model   string       `json:"model,omitempty"`
	ID      string       `json:"id,omitempty"`
	Error   *ErrorDetail `json:"error,omitempty"`
}

type ErrorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Body    string `json:"body"`
}

type Choice struct {
	Message      *ChatMessage `json:"message,omitempty"`
	Delta        *ChatMessage `json:"delta,omitempty"`
	Text         string       `json:"text,omitempty"`
	FinishReason string       `json:"finish_reason,omitempty"`
}

type ErrorResponse struct {
	StatusCode int     `json:"status_code"`
	Message    string  `json:"message"`
	Body       string  `json:"body"`
	Headers    Headers `json:"headers"`
}

func (e *ErrorResponse) Error() string {
	return fmt.Sprintf("status %d: %s", e.StatusCode, e.Message)
}

func ConvertResponse(rawResp RawResponse, headers map[string]string) (*Response, error) {
	// Handle error responses
	if rawResp.Error != nil {
		return nil, &ErrorResponse{
			StatusCode: 400,
			Message:    rawResp.Error.Message,
			Body:       rawResp.Error.Body,
			Headers:    NewHeaders(headers),
		}
	}

	// Handle empty responses
	if len(rawResp.Choices) == 0 {
		return nil, fmt.Errorf("no choices in response")
	}

	choice := rawResp.Choices[0]
	var text string

	// Extract text from choice following TypeScript logic
	if choice.Delta != nil && choice.Delta.Content != "" {
		text = choice.Delta.Content
	} else if choice.Text != "" {
		text = choice.Text
	} else if choice.Message != nil {
		text = choice.Message.Content
	}

	// Check for content filter
	if choice.FinishReason == "content_filter" {
		return nil, &ErrorResponse{
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

func ConvertAllResponses(rawResponses []RawResponse, headers map[string]string) (*Response, error) {
	if len(rawResponses) == 0 {
		return nil, nil
	}

	var convertedText []string
	totalUsage := new(TokenUsage)
	var lastSuccessfulResponse *RawResponse

	for _, rawResp := range rawResponses {
		resp, err := ConvertResponse(rawResp, headers)
		if err != nil {
			if respErr, ok := err.(*ErrorResponse); ok {
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
		}
	}

	if len(convertedText) == 0 || lastSuccessfulResponse == nil {
		return nil, nil
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
