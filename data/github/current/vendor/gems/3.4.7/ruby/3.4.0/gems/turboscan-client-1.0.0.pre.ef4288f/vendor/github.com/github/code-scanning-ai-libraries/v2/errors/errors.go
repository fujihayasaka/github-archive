// Package errors provides error types and utilities for the LLM libraries.
package errors

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/github/code-scanning-ai-libraries/v2/st"
	pkg_errors "github.com/pkg/errors"
)

// ErrorSeverity levels
type ErrorSeverity int

const (
	// Ignore severity error: are not errors, but rather situations
	// where we needed to skip processing. Eg- when we
	// cancel a request due to other changes.
	Ignore ErrorSeverity = iota
	// Low severity error: we were unable to propose a fix, but overall the
	// system is probably working fine.
	//
	// For example, the model sends us a response that we are unable to process,
	// or the content filter suppresses a response.
	//
	// Low severity errors should be logged; if they happen frequently they could
	// indicate a problem.
	Low
	// High severity error: something is not working as expected, but the system
	// can probably continue to function.
	//
	// For example, an internal invariant is violated.
	//
	// High severity errors should be logged and reported to the maintainers for
	// investigation.
	High
	// Critical error: something is seriously wrong, and the system is unlikely
	// to be able to operate normally.
	//
	// For example, the model is down.
	//
	// Critical errors should be logged and reported to the maintainers
	// immediately.
	Critical
)

// LLMError is the core interface that all autofix-specific errors implement.
type LLMError interface {
	// The underlying error.
	Unwrap() error

	// The underlying error message.
	Error() string

	// The type of error.
	Type() string

	// Retryable is true if the request can be retried. For example, if there is
	// a transient issue with CAPI or another dependency.
	Retryable() bool

	// RetryDelay is the minimum amount of time to wait before retrying the request,
	// for example if the request failed due to rate limiting.
	RetryDelay() time.Duration

	// Deterministic is true if the request failed due a deterministic operation.
	// For example, it is true if the request fails due to the problem type being
	// explicitly excluded from autofix, and it is false if the request fails due
	// to the model output.
	Deterministic() bool

	// WithContext returns a new error of the same type with the given context.
	WithContext(ctx string) LLMError

	// ErrorSeverity returns the severity of the error.
	// This is used for telemetry and logging purposes.
	ErrorSeverity() ErrorSeverity
}

// Verify that LLMError implements the error interface.
var _ error = LLMError(nil)

// Error type constants for consistent error classification
const (
	// Main error types
	ErrorTypeBadModelOutput  = "bad_model_output"
	ErrorTypeNotAutofixable  = "not_autofixable"
	ErrorTypeRetryable       = "retryable"
	ErrorTypeLogic           = "logic"
	ErrorTypeInvalidRequest  = "invalid_request"
	ErrorTypeContextCanceled = "context_canceled"
	ErrorTypeGenericFatal    = "generic_fatal_error"

	// Error categories for model output errors
	ErrorCategoryParsing     = "parsing_error"
	ErrorCategoryReplacement = "replacement_error"
	ErrorCategoryMatching    = "matching_error"
	ErrorCategoryValidation  = "validation_error"
	ErrorCategoryFormatting  = "formatting_error"

	// Specific error types
	ErrorTypeNoReplacementBlock = "no_replacement_block"
	ErrorTypeBlockMismatch      = "block_mismatch"
	ErrorTypeFileNotFound       = "file_not_found"
	ErrorTypeEllipsisMismatch   = "ellipsis_mismatch"

	// HTTP status error type
	ErrorTypeHTTPStatus = "http_status_error"
)

var typeSeverityMap = map[string]ErrorSeverity{
	// Main error types
	// We expect model output errors to happen occasionally, so they are low severity
	ErrorTypeBadModelOutput: Low,

	// We expect some alerts to be unfixable, so they are low severity
	ErrorTypeNotAutofixable: Low,

	// Retryble errors are transient, so they are low severity
	ErrorTypeRetryable: Low,

	// Logic errors should not happen in production, so they are critical
	ErrorTypeLogic: Critical,

	// InvalidRequestError should not happen in production, so they are high severity
	ErrorTypeInvalidRequest: Critical,

	// ContextCanceledErrors do not represent an error.
	ErrorTypeContextCanceled: Ignore,

	// We want to know about HTTP status errors, since they can indicate an incident is happening.
	ErrorTypeHTTPStatus: High,

	ErrorTypeGenericFatal: Critical,

	// Error categories for model output errors
	ErrorCategoryParsing:     Low,
	ErrorCategoryReplacement: Low,
	ErrorCategoryMatching:    Low,
	ErrorCategoryValidation:  Low,
	ErrorCategoryFormatting:  Low,

	// Specific error types
	ErrorTypeNoReplacementBlock: Low,
	ErrorTypeBlockMismatch:      Low,
	ErrorTypeFileNotFound:       Low,
	ErrorTypeEllipsisMismatch:   Low,
}

// getSeverity returns the severity for a given error type from the typeSeverityMap.
// If the error type is not found, it returns High as a fallback.
func getSeverity(errorType string) ErrorSeverity {
	if sev, ok := typeSeverityMap[errorType]; ok {
		return sev
	}
	// We should not reach here, and if we do, we should fix.
	return High
}

// ModelOutputError is an interface for errors related to model output processing
type ModelOutputError interface {
	LLMError
	Category() string
	ErrorType() string
	FilePath() string
	ErrorSeverity() ErrorSeverity
}

// MarkedAutofixError wraps an LLMError and adds category information
type MarkedAutofixError struct {
	baseError     LLMError
	errorCategory string
	errorType     string
	filePath      string
}

// Ensure MarkedAutofixError implements both interfaces
var _ LLMError = (*MarkedAutofixError)(nil)
var _ ModelOutputError = (*MarkedAutofixError)(nil)

// NewMarkedError creates a new MarkedAutofixError with the given base error, category, type, and file path.
func NewMarkedError(baseError LLMError, category, errorType, filePath string) *MarkedAutofixError {
	return &MarkedAutofixError{
		baseError:     baseError,
		errorCategory: category,
		errorType:     errorType,
		filePath:      filePath,
	}
}

// RetryableModelOutputError is a map that defines which model error categories and types are not retryable.
var RetryableModelOutputError = map[string]bool{
	ErrorCategoryParsing:     false,
	ErrorCategoryReplacement: false,
	ErrorCategoryMatching:    false,
	ErrorCategoryValidation:  false,
	ErrorCategoryFormatting:  false,
	// Specific error types
	ErrorTypeNoReplacementBlock: false,
	ErrorTypeBlockMismatch:      false,
	ErrorTypeFileNotFound:       false,
	ErrorTypeEllipsisMismatch:   false,
}

// Unwrap part of LLMError interface
func (e *MarkedAutofixError) Unwrap() error { return e.baseError }

// Error part of LLMError interface
func (e *MarkedAutofixError) Error() string { return e.baseError.Error() }

// Type part of LLMError interface
func (e *MarkedAutofixError) Type() string { return e.baseError.Type() }

// Retryable part of LLMError interface
func (e *MarkedAutofixError) Retryable() bool {
	if e.errorCategory != "" {
		if retryable, exists := RetryableModelOutputError[e.errorCategory]; exists {
			return retryable
		}
	}

	if e.errorType != "" {
		if retryable, exists := RetryableModelOutputError[e.errorType]; exists {
			return retryable
		}
	}

	return e.baseError.Retryable()
}

// RetryDelay part of LLMError interface
func (e *MarkedAutofixError) RetryDelay() time.Duration { return e.baseError.RetryDelay() }

// Deterministic part of LLMError interface
func (e *MarkedAutofixError) Deterministic() bool { return e.baseError.Deterministic() }

// ErrorSeverity part of LLMError interface
func (e *MarkedAutofixError) ErrorSeverity() ErrorSeverity {
	return e.baseError.ErrorSeverity()
}

// WithContext part of LLMError interface
func (e *MarkedAutofixError) WithContext(ctx string) LLMError {
	return &MarkedAutofixError{
		baseError:     e.baseError.WithContext(ctx),
		errorCategory: e.errorCategory,
		errorType:     e.errorType,
		filePath:      e.filePath,
	}
}

// Category part of ModelOutputError interface
func (e *MarkedAutofixError) Category() string { return e.errorCategory }

// ErrorType part of ModelOutputError interface
func (e *MarkedAutofixError) ErrorType() string { return e.errorType }

// FilePath part of ModelOutputError interface
func (e *MarkedAutofixError) FilePath() string { return e.filePath }

// ModelError represents unstructured errors from the model
type ModelError struct {
	Title   string
	Message string
	Source  string
	Target  string
	Fatal   bool
}

// Error implements the error interface for ModelError
func (e *ModelError) Error() string {
	return fmt.Sprintf("%s: %s", e.Title, e.Message)
}

// BadModelOutputError indicates autofix could not generate a fix due to the model output.
// Since the model output is non-deterministic, a retry might help.
type BadModelOutputError struct {
	Err error
}

// NewBadModelOutputError creates a new BadModelOutputError with a message and an optional cause.
func NewBadModelOutputError(message string, cause error) BadModelOutputError {
	return BadModelOutputError{Err: st.EnsureStackTrace(cause, message)}
}

// Unwrap part of LLMError interface
func (e BadModelOutputError) Unwrap() error { return e.Err }

// Error part of LLMError interface
func (e BadModelOutputError) Error() string { return e.Err.Error() }

// Type returns the error type as a string for BadModelOutputError.
func (e BadModelOutputError) Type() string { return ErrorTypeBadModelOutput }

// Retryable always returns true for BadModelOutputError
func (e BadModelOutputError) Retryable() bool { return true }

// RetryDelay returns 0 for BadModelOutputError, indicating no specific delay is required.
func (e BadModelOutputError) RetryDelay() time.Duration { return 0 }

// Deterministic always returns false for BadModelOutputError, indicating non-deterministic behavior.
func (e BadModelOutputError) Deterministic() bool { return false }

// ErrorSeverity returns the severity level of the BadModelOutputError based on its type.
func (e BadModelOutputError) ErrorSeverity() ErrorSeverity {
	return getSeverity(e.Type())
}

// WithContext returns a new BadModelOutputError
func (e BadModelOutputError) WithContext(ctx string) LLMError {
	return BadModelOutputError{Err: st.EnsureStackTrace(e.Err, ctx)}
}

// NotAutofixableError indicates that the problem is not autofixable, and a retry will not help.
type NotAutofixableError struct {
	Err error
}

// NewNotAutofixableError creates a new NotAutofixableError with a message.
func NewNotAutofixableError(message string) NotAutofixableError {
	return NotAutofixableError{Err: errors.New(message)}
}

// Unwrap part of LLMError interface
func (e NotAutofixableError) Unwrap() error { return e.Err }

// Error part of LLMError interface
func (e NotAutofixableError) Error() string { return e.Err.Error() }

// Type returns the error type as a string for NotAutofixableError.
func (e NotAutofixableError) Type() string { return ErrorTypeNotAutofixable }

// Retryable always returns false for NotAutofixableError, indicating no retry is possible.
func (e NotAutofixableError) Retryable() bool { return false }

// RetryDelay returns 0 for NotAutofixableError, indicating no retry delay is applicable.
func (e NotAutofixableError) RetryDelay() time.Duration { return 0 }

// Deterministic always returns true for NotAutofixableError, indicating deterministic behavior.
func (e NotAutofixableError) Deterministic() bool { return true }

// ErrorSeverity returns the severity level of the NotAutofixableError based on its type.
func (e NotAutofixableError) ErrorSeverity() ErrorSeverity {
	return getSeverity(e.Type())
}

// WithContext returns a new NotAutofixableError with the given context.
func (e NotAutofixableError) WithContext(ctx string) LLMError {
	return NotAutofixableError{Err: st.EnsureStackTrace(e.Err, ctx)}
}

// RetryableError indicates that autofix could not generate a fix due to a transient issue.
// The request should be retried at a later date if still relevant.
type RetryableError struct {
	Err         error
	_RetryDelay time.Duration
}

// NewRetryableError creates a new RetryableError with a message and an optional retry delay.
func NewRetryableError(message string, retryDelay time.Duration) RetryableError {
	return RetryableError{Err: pkg_errors.New(message), _RetryDelay: retryDelay}
}

// WrapRetryableError creates a new RetryableError with a message and an optional retry delay, and wrapping the given error.
func WrapRetryableError(err error, message string, retryDelay time.Duration) RetryableError {
	return RetryableError{Err: pkg_errors.Wrap(err, message), _RetryDelay: retryDelay}
}

// NewRetryableErrorNoDelay creates a new RetryableError with a message and no retry delay.
func NewRetryableErrorNoDelay(message string) RetryableError {
	return NewRetryableError(message, 0)
}

// Unwrap part of LLMError interface
func (e RetryableError) Unwrap() error { return e.Err }

// Error part of LLMError interface
func (e RetryableError) Error() string { return e.Err.Error() }

// Type returns the error type as a string for RetryableError.
func (e RetryableError) Type() string { return ErrorTypeRetryable }

// Retryable always returns true for RetryableError, indicating the request can be retried.
func (e RetryableError) Retryable() bool { return true }

// RetryDelay returns the retry delay for RetryableError, indicating how long to wait before retrying.
func (e RetryableError) RetryDelay() time.Duration { return e._RetryDelay }

// Deterministic always returns true for RetryableError, indicating deterministic behavior.
func (e RetryableError) Deterministic() bool { return true }

// ErrorSeverity returns the severity level of the RetryableError based on its type.
func (e RetryableError) ErrorSeverity() ErrorSeverity {
	return getSeverity(e.Type())
}

// WithContext returns a new RetryableError with the given context.
func (e RetryableError) WithContext(ctx string) LLMError {
	return RetryableError{Err: st.EnsureStackTrace(e.Err, ctx), _RetryDelay: e._RetryDelay}
}

// LogicError indicates that autofix encountered a logic error, for example a bug in the code.
// The request should not be retried.
type LogicError struct {
	Err error
}

// NewLogicError creates a new LogicError with a message.
func NewLogicError(message string) LogicError {
	return LogicError{Err: errors.New(message)}
}

// Unwrap part of LLMError interface
func (e LogicError) Unwrap() error { return e.Err }

// Error part of LLMError interface
func (e LogicError) Error() string { return e.Err.Error() }

// Type returns the error type as a string for LogicError.
func (e LogicError) Type() string { return ErrorTypeLogic }

// Retryable always returns false for LogicError, indicating the request should not be retried.
func (e LogicError) Retryable() bool { return false }

// RetryDelay returns 0 for LogicError, indicating no retry delay is applicable.
func (e LogicError) RetryDelay() time.Duration { return 0 }

// Deterministic always returns true for LogicError, indicating deterministic behavior.
func (e LogicError) Deterministic() bool { return true }

// ErrorSeverity returns the severity level of the LogicError based on its type.
func (e LogicError) ErrorSeverity() ErrorSeverity {
	return getSeverity(e.Type())
}

// WithContext returns a new LogicError with the given context.
func (e LogicError) WithContext(ctx string) LLMError {
	return LogicError{Err: st.EnsureStackTrace(e.Err, ctx)}
}

// InvalidRequestError indicates that the request to autofix was invalid.
// The request should not be retried.
type InvalidRequestError struct {
	Err error
}

// NewInvalidRequestError creates a new InvalidRequestError with a message.
func NewInvalidRequestError(message string) InvalidRequestError {
	return InvalidRequestError{Err: errors.New(message)}
}

// Unwrap part of LLMError interface
func (e InvalidRequestError) Unwrap() error { return e.Err }

// Error part of LLMError interface
func (e InvalidRequestError) Error() string { return e.Err.Error() }

// Type returns the error type as a string for InvalidRequestError.
func (e InvalidRequestError) Type() string { return ErrorTypeInvalidRequest }

// Retryable always returns false for InvalidRequestError, indicating the request should not be retried.
func (e InvalidRequestError) Retryable() bool { return false }

// RetryDelay returns 0 for InvalidRequestError, indicating no retry delay is applicable.
func (e InvalidRequestError) RetryDelay() time.Duration { return 0 }

// Deterministic always returns true for InvalidRequestError, indicating deterministic behavior.
func (e InvalidRequestError) Deterministic() bool { return true }

// ErrorSeverity returns the severity level of the InvalidRequestError based on its type.
func (e InvalidRequestError) ErrorSeverity() ErrorSeverity {
	return getSeverity(e.Type())
}

// WithContext returns a new InvalidRequestError with the given context.
func (e InvalidRequestError) WithContext(ctx string) LLMError {
	return InvalidRequestError{Err: st.EnsureStackTrace(e.Err, ctx)}
}

// ContextCanceledError indicates that the operation was canceled due to context cancellation.
// These errors typically indicate client cancellation rather than server failure.
type ContextCanceledError struct {
	Err error
}

// NewContextCanceledError creates a new ContextCanceledError with a message and the original context error.
func NewContextCanceledError(message string, ctxErr error) ContextCanceledError {
	return ContextCanceledError{Err: st.EnsureStackTrace(ctxErr, message)}
}

// Unwrap part of LLMError interface
func (e ContextCanceledError) Unwrap() error { return e.Err }

// Error part of LLMError interface
func (e ContextCanceledError) Error() string { return e.Err.Error() }

// Type returns the error type as a string for ContextCanceledError.
func (e ContextCanceledError) Type() string { return ErrorTypeContextCanceled }

// Retryable always returns false for ContextCanceledError, indicating the request should not be retried.
func (e ContextCanceledError) Retryable() bool { return false }

// RetryDelay returns 0 for ContextCanceledError, indicating no retry delay is applicable.
func (e ContextCanceledError) RetryDelay() time.Duration { return 0 }

// Deterministic always returns true for ContextCanceledError, indicating deterministic behavior.
func (e ContextCanceledError) Deterministic() bool { return true }

// ErrorSeverity returns the severity level of the ContextCanceledError based on its type.
func (e ContextCanceledError) ErrorSeverity() ErrorSeverity {
	return getSeverity(e.Type())
}

// WithContext returns a new ContextCanceledError with the given context.
func (e ContextCanceledError) WithContext(ctx string) LLMError {
	return ContextCanceledError{Err: st.EnsureStackTrace(e.Err, ctx)}
}

// NewParsingError creation helpers
func NewParsingError(message string, cause error) LLMError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryParsing, "", "")
}

// NewNoReplacementBlockError creates a new error indicating that no replacement block was found in the model output.
func NewNoReplacementBlockError(message string, cause error, filePath string) LLMError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryReplacement, ErrorTypeNoReplacementBlock, filePath)
}

// NewBlockMismatchError creates a new error indicating that the model output block does not match the expected format.
func NewBlockMismatchError(message string, cause error, filePath string) LLMError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryMatching, ErrorTypeBlockMismatch, filePath)
}

// NewFileNotFoundError creates a new error indicating that a file was not found in the model output.
func NewFileNotFoundError(message string, cause error, filePath string) LLMError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryValidation, ErrorTypeFileNotFound, filePath)
}

// NewEllipsisMismatchError creates a new error indicating that the model output has an ellipsis mismatch.
func NewEllipsisMismatchError(message string, cause error, filePath string) LLMError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryMatching, ErrorTypeEllipsisMismatch, filePath)
}

// NewErrorFromContextErr error helper
func NewErrorFromContextErr(ctx context.Context, message string) LLMError {
	if ctx.Err() == nil {
		return nil
	}
	return NewContextCanceledError(message, ctx.Err())
}

// IsErrorOfCategory checks if an error belongs to a specific category
func IsErrorOfCategory(err error, category string) bool {
	var modelErr ModelOutputError
	if errors.As(err, &modelErr) {
		return modelErr.Category() == category
	}
	return false
}

// IsErrorOfType checks if an error has a specific error type
func IsErrorOfType(err error, errorType string) bool {
	var modelErr ModelOutputError
	if errors.As(err, &modelErr) {
		return modelErr.ErrorType() == errorType
	}
	return false
}

// IsContextCanceledError checks if an error is related to context cancellation
func IsContextCanceledError(err error) bool {
	var contextErr ContextCanceledError
	if errors.As(err, &contextErr) {
		return true
	}
	return errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded)
}

// HTTPStatusError indicates an error related to HTTP status codes
type HTTPStatusError struct { //nolint:recvcheck // Yes, there is a mix of pointer and non-pointer receivers. Marshalling requires a pointer receiver, but the rest are using non-pointer receivers for consistency with the other errors.
	Err         error
	StatusCode  int
	_RetryDelay time.Duration
	_Retryable  bool
}

// NewHTTPStatusError creates a new HTTPStatusError with the given status code, message, retryable flag, and retry delay.
func NewHTTPStatusError(statusCode int, message string, retryable bool, retryDelay time.Duration) HTTPStatusError {
	return HTTPStatusError{
		Err:         pkg_errors.Errorf("HTTP error %d: %s", statusCode, message),
		StatusCode:  statusCode,
		_Retryable:  retryable,
		_RetryDelay: retryDelay,
	}
}

// WrapHTTPStatusError creates a new HTTPStatusError with the given status code, message, retryable flag, and retry delay, and wrapping the given error.
func WrapHTTPStatusError(err error, statusCode int, message string, retryable bool, retryDelay time.Duration) HTTPStatusError {
	return HTTPStatusError{
		Err:         pkg_errors.Wrapf(err, "HTTP error %d: %s", statusCode, message),
		StatusCode:  statusCode,
		_Retryable:  retryable,
		_RetryDelay: retryDelay,
	}
}

// Unwrap part of LLMError interface
func (e HTTPStatusError) Unwrap() error { return e.Err }

// Error part of LLMError interface
func (e HTTPStatusError) Error() string { return e.Err.Error() }

// Type returns the error type as a string for HTTPStatusError.
func (e HTTPStatusError) Type() string { return ErrorTypeHTTPStatus }

// Retryable returns true if the HTTPStatusError is retryable, false otherwise.
func (e HTTPStatusError) Retryable() bool { return e._Retryable }

// RetryDelay returns the retry delay for HTTPStatusError, indicating how long to wait before retrying.
func (e HTTPStatusError) RetryDelay() time.Duration { return e._RetryDelay }

// Deterministic returns true for HTTPStatusError, indicating deterministic behavior.
func (e HTTPStatusError) Deterministic() bool { return true }

// GetStatusCode returns the HTTP status code associated with the error.
func (e HTTPStatusError) GetStatusCode() int { return e.StatusCode }

// ErrorSeverity returns the severity level of the HTTPStatusError based on its type.
func (e HTTPStatusError) ErrorSeverity() ErrorSeverity { return getSeverity(e.Type()) }

// WithContext returns a new HTTPStatusError with the given context.
func (e HTTPStatusError) WithContext(ctx string) LLMError {
	return &HTTPStatusError{
		Err:         st.EnsureStackTrace(e.Err, ctx),
		StatusCode:  e.StatusCode,
		_Retryable:  e._Retryable,
		_RetryDelay: e._RetryDelay,
	}
}

// Ensure HTTPStatusError implements JSON marshaling interfaces
var _ json.Marshaler = (*HTTPStatusError)(nil)
var _ json.Unmarshaler = (*HTTPStatusError)(nil)

// serializedHTTPStatusError is a struct used for JSON serialization of HTTPStatusError.
type serializedHTTPStatusError struct {
	Message    string        `json:"message"`
	StatusCode int           `json:"status_code"`
	RetryDelay time.Duration `json:"retry_delay"`
	Retryable  bool          `json:"retryable"`
}

// MarshalJSON converts an HTTPStatusError to JSON.
func (e *HTTPStatusError) MarshalJSON() ([]byte, error) {
	return json.Marshal(serializedHTTPStatusError{
		Message:    e.Error(),
		StatusCode: e.StatusCode,
		RetryDelay: e._RetryDelay,
		Retryable:  e._Retryable,
	})
}

// UnmarshalJSON populates an HTTPStatusError from JSON.
func (e *HTTPStatusError) UnmarshalJSON(data []byte) error {
	var a serializedHTTPStatusError
	if err := json.Unmarshal(data, &a); err != nil {
		return err
	}
	e.Err = errors.New(a.Message)
	e.StatusCode = a.StatusCode
	e._RetryDelay = a.RetryDelay
	e._Retryable = a.Retryable
	return nil
}

// IsRetryableError determines if an error is retryable based on type and status code
func IsRetryableError(err LLMError) bool {
	if err == nil {
		return false
	}

	// Check if the error itself advertises retryability
	if err.Retryable() {
		return true
	}

	// Check for HTTP status code retryability
	if httpErr, ok := err.(HTTPStatusError); ok {
		return IsRetryableStatusCode(httpErr.StatusCode)
	}

	return false
}

var retryableStatusCodes = map[int]bool{
	-1: true, 0: true, 408: true, 429: true,
	500: true, 502: true, 503: true, 504: true, 520: true,
}

// IsRetryableStatusCode returns whether a given HTTP status code from an LLM backend can be retried.
func IsRetryableStatusCode(code int) bool {
	return retryableStatusCodes[code]
}

// GenericFatalError indicates some kind of fatal error that cannot be retried.
type GenericFatalError struct {
	Err  error
	kind string
}

var _ LLMError = GenericFatalError{} //nolint:exhaustruct // Intentionally not initializing all fields

// NewError creates a new GenericFatalError with the given message and kind.
func NewError(message, kind string) GenericFatalError {
	return GenericFatalError{Err: pkg_errors.New(message), kind: kind}
}

// NewErrorf creates a new GenericFatalError with the given message and kind.
func NewErrorf(kind, message string, args ...interface{}) GenericFatalError {
	return GenericFatalError{Err: pkg_errors.Errorf(message, args...), kind: kind}
}

// WrapError creates a new GenericFatalError with the given error, message and kind.
func WrapError(err error, kind, msg string) GenericFatalError {
	return GenericFatalError{Err: pkg_errors.Wrap(err, msg), kind: kind}
}

// WrapErrorf creates a new GenericFatalError with the given error, message and kind.
func WrapErrorf(err error, kind, format string, args ...interface{}) GenericFatalError {
	return GenericFatalError{Err: pkg_errors.Wrapf(err, format, args...), kind: kind}
}

// EnsureStackTrace creates a new GenericFatalError with the given error, message and kind.
func EnsureStackTrace(err error, kind, msg string) GenericFatalError {
	return GenericFatalError{Err: st.EnsureStackTrace(err, msg), kind: kind}
}

// EnsureStackTracef creates a new GenericFatalError with the given error, message and kind.
func EnsureStackTracef(err error, kind, msg string, args ...interface{}) GenericFatalError {
	return GenericFatalError{Err: st.EnsureStackTracef(err, msg, args...), kind: kind}
}

// Unwrap part of LLMError interface
func (e GenericFatalError) Unwrap() error { return e.Err }

// Error implements the error interface for GenericFatalError.
func (e GenericFatalError) Error() string { return e.Err.Error() }

// Type returns the error type classification.
func (e GenericFatalError) Type() string { return e.kind }

// Retryable returns false as fatal errors cannot be retried.
func (e GenericFatalError) Retryable() bool { return false }

// Deterministic returns true as fatal errors are deterministic.
func (e GenericFatalError) Deterministic() bool { return true }

// RetryDelay returns 0 as there is no retry delay for fatal errors.
func (e GenericFatalError) RetryDelay() time.Duration { return 0 }

// ErrorSeverity returns the severity level of the GenericFatalError based on its type.
func (e GenericFatalError) ErrorSeverity() ErrorSeverity { return getSeverity(e.Type()) }

// WithContext returns a new error with additional context information.
func (e GenericFatalError) WithContext(ctx string) LLMError {
	return GenericFatalError{Err: st.EnsureStackTrace(e.Err, ctx), kind: e.kind}
}

// Ensure all error types implement the LLMError interface
var _ LLMError = BadModelOutputError{}  //nolint:exhaustruct // for type checking
var _ LLMError = NotAutofixableError{}  //nolint:exhaustruct // for type checking
var _ LLMError = RetryableError{}       //nolint:exhaustruct // for type checking
var _ LLMError = LogicError{}           //nolint:exhaustruct // for type checking
var _ LLMError = InvalidRequestError{}  //nolint:exhaustruct // for type checking
var _ LLMError = ContextCanceledError{} //nolint:exhaustruct // for type checking
var _ LLMError = HTTPStatusError{}      //nolint:exhaustruct // for type checking
