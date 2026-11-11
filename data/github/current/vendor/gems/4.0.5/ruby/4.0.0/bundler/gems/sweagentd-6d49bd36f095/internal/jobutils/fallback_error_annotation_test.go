package jobutils

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestParseFallbackErrorAnnotation(t *testing.T) {
	tests := []struct {
		name        string
		annotation  string
		wantService string
		wantCode    string
		wantMessage string
		wantNil     bool
	}{
		{
			name:        "valid annotation with message",
			annotation:  "Copilot has encountered an unexpected error: [capi:401] Token expired",
			wantService: "capi",
			wantCode:    "401",
			wantMessage: "Token expired",
			wantNil:     false,
		},
		{
			name:        "valid annotation with longer message",
			annotation:  "Copilot has encountered an unexpected error: [runtime:unclassified] An unknown error occurred during execution",
			wantService: "runtime",
			wantCode:    "unclassified",
			wantMessage: "An unknown error occurred during execution",
			wantNil:     false,
		},
		{
			name:        "valid annotation with git service",
			annotation:  "Copilot has encountered an unexpected error: [git:hook] Pre-commit hook failed",
			wantService: "git",
			wantCode:    "hook",
			wantMessage: "Pre-commit hook failed",
			wantNil:     false,
		},
		{
			name:        "valid annotation with empty message",
			annotation:  "Copilot has encountered an unexpected error: [capi:429]",
			wantService: "capi",
			wantCode:    "429",
			wantMessage: "",
			wantNil:     false,
		},
		{
			name:        "valid annotation with whitespace in message",
			annotation:  "Copilot has encountered an unexpected error: [capi:500]   Server error   ",
			wantService: "capi",
			wantCode:    "500",
			wantMessage: "Server error",
			wantNil:     false,
		},
		{
			name:       "missing prefix",
			annotation: "[capi:401] Token expired",
			wantNil:    true,
		},
		{
			name:       "different prefix",
			annotation: "Some other error: [capi:401] Token expired",
			wantNil:    true,
		},
		{
			name:       "missing brackets",
			annotation: "Copilot has encountered an unexpected error: capi:401 Token expired",
			wantNil:    true,
		},
		{
			name:       "missing colon in service:code",
			annotation: "Copilot has encountered an unexpected error: [capi401] Token expired",
			wantNil:    true,
		},
		{
			name:       "empty service",
			annotation: "Copilot has encountered an unexpected error: [:401] Token expired",
			wantNil:    true,
		},
		{
			name:       "empty code",
			annotation: "Copilot has encountered an unexpected error: [capi:] Token expired",
			wantNil:    true,
		},
		{
			name:       "empty annotation",
			annotation: "",
			wantNil:    true,
		},
		{
			name:       "only prefix",
			annotation: "Copilot has encountered an unexpected error:",
			wantNil:    true,
		},
		{
			name:        "annotation with extra text before prefix",
			annotation:  "Error occurred: Copilot has encountered an unexpected error: [capi:401] Token expired",
			wantService: "capi",
			wantCode:    "401",
			wantMessage: "Token expired",
			wantNil:     false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ParseFallbackErrorAnnotation(tt.annotation)
			if tt.wantNil {
				assert.Nil(t, result)
			} else {
				assert.NotNil(t, result)
				assert.Equal(t, tt.wantService, result.Service)
				assert.Equal(t, tt.wantCode, result.ResponseStatusCode)
				assert.Equal(t, tt.wantMessage, result.Message)
			}
		})
	}
}
