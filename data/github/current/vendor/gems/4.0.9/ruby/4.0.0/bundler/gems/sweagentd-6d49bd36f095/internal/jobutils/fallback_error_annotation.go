package jobutils

import (
	"regexp"
	"strings"

	"github.com/github/sweagentd/internal/jobs"
	gg "github.com/google/go-github/v75/github"
)

// fallbackErrorAnnotationPrefix is the prefix used to identify fallback error annotations
// emitted by the runtime when it cannot report errors via the normal callback mechanism.
const fallbackErrorAnnotationPrefix = "Copilot has encountered an unexpected error:"

// fallbackErrorPattern matches the [service:code] pattern in fallback error annotations.
// Example: "[capi:401] Token expired" captures "capi", "401", and "Token expired"
var fallbackErrorPattern = regexp.MustCompile(`\[([^:\]]+):([^\]]+)\]\s*(.*)`)

// ParseFallbackErrorAnnotation parses a fallback error annotation message
// and extracts the service, code, and message.
// Returns nil if the annotation is not a valid fallback error annotation.
//
// Expected format: "Copilot has encountered an unexpected error: [service:code] message"
func ParseFallbackErrorAnnotation(annotation string) *jobs.JobError {
	// Extract the part after the prefix using CutPrefix for a single-pass operation
	_, remainder, found := strings.Cut(annotation, fallbackErrorAnnotationPrefix)
	if !found {
		return nil
	}
	remainder = strings.TrimSpace(remainder)

	// Match the [service:code] pattern
	// Expected 4 matches: full match, service, code, message
	matches := fallbackErrorPattern.FindStringSubmatch(remainder)
	if len(matches) < 4 {
		return nil
	}

	service := strings.TrimSpace(matches[1])
	code := strings.TrimSpace(matches[2])
	message := strings.TrimSpace(matches[3])

	if service == "" || code == "" {
		return nil
	}

	return &jobs.JobError{
		Service:            service,
		ResponseStatusCode: code,
		Message:            message,
	}
}

// findFallbackErrorAnnotation searches through workflow job annotations for a fallback
// error annotation emitted by the runtime, and returns the parsed error if found.
func findFallbackErrorAnnotation(annotations []*gg.CheckRunAnnotation) *jobs.JobError {
	if annotations == nil {
		return nil
	}

	for _, annotation := range annotations {
		if annotation == nil || annotation.Message == nil {
			continue
		}

		// ParseFallbackErrorAnnotation returns nil for non-matching annotations
		if jobErr := ParseFallbackErrorAnnotation(*annotation.Message); jobErr != nil {
			return jobErr
		}
	}

	return nil
}
