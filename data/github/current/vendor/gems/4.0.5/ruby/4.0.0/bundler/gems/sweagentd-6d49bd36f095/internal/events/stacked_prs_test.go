package events

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/openai/openai-go"
	"github.com/stretchr/testify/require"
)

func TestDetectStackedPRIntent(t *testing.T) {
	obsv := observability.NewNoopExporters()

	tests := []struct {
		name           string
		llmResponse    string
		expectedIntent bool
	}{
		{
			name:           "returns true when LLM responds with create_pull_request true",
			llmResponse:    `{"create_pull_request": true}`,
			expectedIntent: true,
		},
		{
			name:           "returns false when LLM responds with create_pull_request false",
			llmResponse:    `{"create_pull_request": false}`,
			expectedIntent: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			commentBody := "any comment"
			capiClient := &capi.NoopClient{}
			capiClient.MockChatCompletions = func(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
				require.Equal(t, "12345", userID)
				require.Equal(t, "test-job-id", interactionID)
				require.Equal(t, "gpt-4o-mini", body.Model)
				require.Len(t, body.Messages, 2)

				return &openai.ChatCompletion{
					Choices: []openai.ChatCompletionChoice{
						{
							Message: openai.ChatCompletionMessage{
								Content: tt.llmResponse,
							},
						},
					},
				}, nil
			}

			h := &Handler{
				obsv:       obsv,
				capiClient: capiClient,
			}

			job := &jobs.Job{
				ActorID: 12345,
				ID:      "test-job-id",
			}

			intent, err := h.detectStackedPRIntent(context.Background(), job, commentBody)
			require.NoError(t, err)
			require.Equal(t, tt.expectedIntent, intent)
		})
	}
}

func TestDetectStackedPRIntent_ErrorHandling(t *testing.T) {
	obsv := observability.NewNoopExporters()

	tests := []struct {
		name               string
		mockResponse       *openai.ChatCompletion
		expectedErrMessage string
	}{
		{
			name: "handles empty LLM response",
			mockResponse: &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{
					{
						Message: openai.ChatCompletionMessage{
							Content: "",
						},
					},
				},
			},
			expectedErrMessage: "empty response from LLM for stacked PR intent detection",
		},
		{
			name: "handles invalid JSON response",
			mockResponse: &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{
					{
						Message: openai.ChatCompletionMessage{
							Content: "not valid json",
						},
					},
				},
			},
			expectedErrMessage: "failed to parse JSON response for stacked PR intent detection",
		},
		{
			name: "handles no choices in response",
			mockResponse: &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{},
			},
			expectedErrMessage: "no choices in chat completions response for stacked PR intent detection",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			capiClient := &capi.NoopClient{}
			capiClient.MockChatCompletions = func(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
				return tt.mockResponse, nil
			}

			h := &Handler{
				obsv:       obsv,
				capiClient: capiClient,
			}

			job := &jobs.Job{
				ActorID: 12345,
				ID:      "test-job-id",
			}

			_, err := h.detectStackedPRIntent(context.Background(), job, "@copilot fix this")
			require.Error(t, err)
			require.Contains(t, err.Error(), tt.expectedErrMessage)
		})
	}
}
