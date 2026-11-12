package agentcallback

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
)

// ErrorCode represents an error code that can be either a string or an integer.
type ErrorCode struct {
	StringValue string
	IntValue    int
	IsString    bool
}

// UnmarshalJSON implements custom unmarshaling to handle both string and integer
// error codes.
func (f *ErrorCode) UnmarshalJSON(data []byte) error {
	// Handle null values
	if string(data) == "null" {
		f.StringValue = ""
		f.IntValue = 0
		f.IsString = false
		return nil
	}

	// Try to unmarshal as string first
	var s string
	err := json.Unmarshal(data, &s)
	if err == nil {
		f.StringValue = s
		f.IsString = true
		return nil
	}

	// Try to unmarshal as number
	var n float64
	err = json.Unmarshal(data, &n)
	if err == nil {
		f.IntValue = int(n)
		f.StringValue = strconv.Itoa(int(n))
		f.IsString = false
		return nil
	}

	// If it's neither string nor number (e.g., boolean, array, object),
	// just set to zero values and succeed silently to allow overall deserialization
	f.StringValue = ""
	f.IntValue = 0
	f.IsString = false
	return nil
}

// AgentError represents an error reported by the agent runtime.
type AgentError struct {
	// Code is the error code, which can be a string or an integer.
	// Example codes include: quota_exceeded, invalid_request_body
	Code ErrorCode `json:"code"`
	// Name is typically the error's class name e.g. "CAPIError", "GitError" and
	// often just "Error".
	Name string `json:"name,omitempty"`
	// Text is the error text, which is a human-readable description of the error.
	// This is often the same as Message. Use [Description] to get a human-readable
	// description of the error.
	Text string `json:"text,omitempty"`
	// Message is a human-readable description of the error.
	// This is often the same as Text. Use [Description] to get a human-readable
	// description of the error.
	Message string `json:"message,omitempty"`
	// Stack is the stack trace at the point where the error was created.
	Stack string `json:"stack,omitempty"`
	// RequestID is an optional request ID associated with the error.
	RequestID string `json:"request_id,omitempty"`
	// GitHubRequestID is an optional GitHub request ID associated with the error.
	GitHubRequestID string `json:"ghRequestId,omitempty"`
	// Cmd is the command that was being executed when the error occurred.
	Cmd string `json:"cmd,omitempty"`
	// Signal is the signal that caused the error, if applicable.
	Signal string `json:"signal,omitempty"`
	// SkipReport indicates whether this error should be reported to Sentry.
	// This is typically set for known errors that do not require further
	// investigation. The error will be logged but not reported.
	SkipReport bool `json:"skipReport"`
	// IsVisionFlow indicates whether this error originated from the vision flow.
	IsVisionFlow bool `json:"isVisionFlow"`
}

// Replace time durations with <duration>
// Matches patterns like:
// - "6.171303629518614 seconds"
// - "1 second"
// - "2.5 minutes"
// - "1 minute"
// - "3.14 hours"
// - "1 hour"
var timeRegex = regexp.MustCompile(`\d+(?:\.\d+)?\s+(?:second|minute|hour)s?`)

// Replace "retried X times" with "retried n times"
var retriedRegex = regexp.MustCompile(`retried \d+ times`)

// normalizeRetryMessage replaces specific retry counts and time durations with placeholders
// to ensure consistent error messages regardless of the actual values.
// Example: "retried 5 times (total retry wait time: 6.171303629518614 seconds)"
// becomes: "retried n times (total retry wait time: <duration>)"
func normalizeRetryMessage(msg string) string {
	msg = retriedRegex.ReplaceAllString(msg, "retried n times")
	msg = timeRegex.ReplaceAllString(msg, "<duration>")
	return msg
}

// RollupInfo is used by the exceptions package to determine if errors are of
// the same class for rollup purposes.
func (e *AgentError) RollupInfo() string {
	class := e.Class()
	if class != "" {
		return class
	}
	return "AgentError"
}

// Class returns a string that represents the class of the error and will be used
// for the title in Sentry. It combines the Name, Code, and message fields if available.
func (e *AgentError) Class() string {
	prefix := "Error"
	if e.Name != "" {
		prefix = e.Name
	}
	if e.Code.IsString && e.Code.StringValue != "" {
		prefix = fmt.Sprintf("%s (%s)", prefix, e.Code.StringValue)
	}

	return fmt.Sprintf("AgentError: %s: %s", prefix, e.Description())
}

// Description returns a human-readable description of the error.
func (e *AgentError) Description() string {
	var desc string
	switch {
	case e.Text != "":
		desc = e.Text
	case e.Message != "":
		desc = e.Message
	default:
		desc = "An error occurred"
	}

	return normalizeRetryMessage(desc)
}

// Error implements the error interface.
func (e *AgentError) Error() string {
	prefix := "Error"
	if e.Name != "" {
		prefix = e.Name
	}
	if e.Code.IsString && e.Code.StringValue != "" {
		prefix = fmt.Sprintf("%s (%s)", prefix, e.Code.StringValue)
	}

	errorMsg := fmt.Sprintf("Agent error: %s: %s", prefix, e.Description())
	if e.Stack != "" {
		errorMsg = fmt.Sprintf("%s\n%s", errorMsg, e.Stack)
	}

	return errorMsg
}
