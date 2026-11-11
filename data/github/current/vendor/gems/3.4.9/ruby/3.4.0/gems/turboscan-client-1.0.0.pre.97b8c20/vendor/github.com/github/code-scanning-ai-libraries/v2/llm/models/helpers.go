// Package models provides utilities for working with LLM models, including token counting and response handling.
package models

import (
	"net/http"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/pkg/errors"
)

// IsContentFilteredResponse returns whether the response indicates a content filter.
func IsContentFilteredResponse(response *ResponseError) bool {
	return response.StatusCode == http.StatusUnprocessableEntity ||
		(response.StatusCode == http.StatusForbidden && strings.Contains(response.Body, "content_filter"))
}

// IsTruncatedResponse returns whether the response indicates a truncated output.
func IsTruncatedResponse(response *ResponseError) bool {
	return response.StatusCode == http.StatusRequestEntityTooLarge
}

// ModelList represents a list of available models returned by an API.
type ModelList struct {
	Data   []ModelEntry `json:"data"`
	Object string       `json:"object"`
}

// LoadModelCapabilities loads the capabilities for a given model from the registry.
func LoadModelCapabilities(modelName string) (*ModelCapabilities, error) {
	registry, err := GetRegistry()
	if err != nil {
		return nil, st.EnsureStackTrace(err, "getting model registry")
	}

	// Try looking up by ID first
	if model, found := registry.GetModel(modelName); found {
		return model.Capabilities, nil
	}

	return nil, errors.Errorf("model %s not found", modelName)
}
