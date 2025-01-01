package models

import (
	"fmt"
	"strings"

	"github.com/github/codeml-autofix/go/pkg/autofix"
	"github.com/pkoukk/tiktoken-go"
)

// IsContentFilteredResponse returns whether the response indicates a content filter.
func IsContentFilteredResponse(response *ErrorResponse) bool {
	return response.StatusCode == 422 ||
		(response.StatusCode == 403 && strings.Contains(response.Body, "content_filter"))
}

// IsTruncatedResponse returns whether the response indicates a truncated output.
func IsTruncatedResponse(response *ErrorResponse) bool {
	return response.StatusCode == 413
}

func NumTokensInChat(prompt []ChatMessage, model Model) int {
	encodingName := model.GetEncodingName()
	encoder, err := tiktoken.GetEncoding(encodingName)
	if err != nil {
		// Fallback to a rough estimate if encoding is unavailable.
		var totalTokens int
		for _, msg := range prompt {
			content := strings.ReplaceAll(msg.Content, "<|", "<\\|")
			totalTokens += len(strings.Split(content, " "))
			totalTokens += 4 // add tokens for message format
		}
		totalTokens += 2
		return totalTokens
	}

	totalTokens := 0
	for _, msg := range prompt {
		tokens := encoder.Encode(msg.Content, nil, nil)
		if tokens == nil {
			words := strings.Split(msg.Content, " ")
			tokens = make([]int, len(words))
			for i := range words {
				tokens[i] = len(words[i])
			}
		}
		totalTokens += len(tokens)
		totalTokens += 4 // add tokens for message formatting overhead
	}
	totalTokens += 2 // add tokens for conversation formatting
	return totalTokens
}

func ComputeMaxTokens(prompt []ChatMessage, model Model) (int, error) {
	defaultMaxTokens := model.GetMaxTokens()
	numTokens := NumTokensInChat(prompt, model)
	contextWindowLength := model.GetContextSize()
	tokensLeft := contextWindowLength - numTokens

	if tokensLeft <= 100 {
		modelErr := &autofix.ModelError{
			Title:    "Prompt too long",
			Message:  fmt.Sprintf("The prompt has %d tokens, max: %d", numTokens, contextWindowLength),
			Severity: autofix.High,
			Fatal:    true,
			Source:   "",
			Target:   "",
		}
		return 0, fmt.Errorf("compute max tokens failed: %w", modelErr)
	}

	if defaultMaxTokens != 0 && tokensLeft <= defaultMaxTokens {
		return tokensLeft, nil
	}
	return defaultMaxTokens, nil
}

type ModelList struct {
	Data   []ModelEntry `json:"data"`
	Object string       `json:"object"`
}

func LoadModelCapabilities(modelName string) (*ModelCapabilities, error) {
	registry, err := GetRegistry()
	if err != nil {
		return nil, fmt.Errorf("getting model registry: %w", err)
	}

	// Try looking up by ID first
	if model, found := registry.GetModelByID(modelName); found {
		return model.Capabilities, nil
	}

	// Try looking up by flavor
	if model, found := registry.GetModelByFlavor(modelName); found {
		return model.Capabilities, nil
	}

	return nil, fmt.Errorf("model %s not found", modelName)
}
