package agentcallback

import (
	"encoding/json"
	"fmt"
	"iter"
	"regexp"
	"strconv"
	"strings"

	"github.com/github/sweagentd/internal/goerrors"
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
	// Service is the service that originated the error (e.g., "capi", "git", "runtime").
	Service string `json:"service,omitempty"`
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
	// ParsedStack is a semantic parsing of the error stack, used to present the stacktrace to sentry.
	// This is empty if no stack trace was presented from the runtime, or the stacktrace could not be parsed
	ParsedStack []*goerrors.Frame
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

// UnmarshalJSON implements the Unmarshaller interface for AgentError
func (e *AgentError) UnmarshalJSON(b []byte) error {
	// Use default unmarshalling first
	type agentErrorAlias *AgentError
	alias := agentErrorAlias(e)

	err := json.Unmarshal(b, &alias)
	if err != nil {
		return goerrors.Errorf("error unmarshalling agent error: %w", err)
	}

	e.ParsedStack = parseStack(e.Stack)

	return nil
}

func parseStack(stack string) []*goerrors.Frame {
	frames := []*goerrors.Frame{}
	for line := range strings.Lines(stack) {
		// Look for lines that begin with any number of whitespace characters and the word "at"
		if !regexp.MustCompile(`^\s*at`).MatchString(line) {
			continue
		}

		// Grab the bit following "at " up until the first parenthesis, this is our function name
		functionMatches := regexp.MustCompile(`^\s*at (.*?) \(`).FindStringSubmatch(line)
		if len(functionMatches) < 2 {
			// No match found, we don't understand the format of this stack trace
			return nil
		}
		function := functionMatches[1]

		// Now grab the bit in the parenthesis, up until the second to last colon.  This is our file.
		// First extract the parenthesis bit
		// Regex explainer:  Grab everything between two parenthesis, except for the closing parenthesis character
		lineMatches := regexp.MustCompile(`\(([^)]*)\)`).FindStringSubmatch(line)
		if len(lineMatches) < 2 {
			// No match found, we don't understand the format of this stack trace
			return nil
		}

		parts := strings.Split(lineMatches[1], ":")
		if len(parts) < 3 {
			// We expect filename:line:pos, if we don't have at least three parts, we don't understand this format
			return nil
		}

		// Filenames may have colons in them, so grab up to the second to last part
		fileName := strings.Join(parts[:len(parts)-2], ":")
		lineNumber, err := strconv.Atoi(parts[len(parts)-2])
		if err != nil {
			return nil
		}

		frames = append(frames, &goerrors.Frame{
			Function:   function,
			FileName:   fileName,
			LineNumber: lineNumber,
		})
	}

	return frames
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
// for the title in Sentry. It combines the Name and Code fields if available.
func (e *AgentError) Class() string {
	prefix := "Error"
	if e.Name != "" {
		prefix = e.Name
	}
	if e.Code.IsString && e.Code.StringValue != "" {
		prefix = fmt.Sprintf("%s (%s)", prefix, e.Code.StringValue)
	}

	return fmt.Sprintf("AgentError: %s", prefix)
}

// Description returns a human-readable description of the error, without
// normalization. This is the text suitable for display to users.
func (e *AgentError) Description() string {
	return e.rawDescription()
}

// ErrorCode returns the error code as a string.
func (e *AgentError) ErrorCode() string {
	if e.Code.IsString {
		return e.Code.StringValue
	}

	return strconv.Itoa(e.Code.IntValue)
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

	errorMsg := fmt.Sprintf("Agent error: %s: %s", prefix, normalizeRetryMessage(e.rawDescription()))
	// If we have a stack trace, but were unable to parse it, include it in the error message as a fallback
	if e.Stack != "" && len(e.ParsedStack) == 0 {
		errorMsg = fmt.Sprintf("%s\n%s", errorMsg, e.Stack)
	}

	return errorMsg
}

// Frames implements the goerrors.StacktraceError interface
func (e *AgentError) Frames() iter.Seq[*goerrors.Frame] {
	return func(yield func(*goerrors.Frame) bool) {
		for _, frame := range e.ParsedStack {
			if !yield(frame) {
				return
			}
		}
	}
}

// rawDescription returns the raw text of the error without any normalization.
func (e *AgentError) rawDescription() string {
	switch {
	case e.Text != "":
		return e.Text
	case e.Message != "":
		return e.Message
	default:
		return "An error occurred"
	}
}
