// Package models provides utilities for working with LLM models, including token counting and response handling.
package models

import (
	"net/http"
	"strings"
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
