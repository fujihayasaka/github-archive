package autofix

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/github/codeml-autofix/go/pkg/autofix/enhancedctx"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
)

// Error severity levels
type ErrorSeverity int

const (
	High ErrorSeverity = iota
	Medium
	Low
	ErrorTypeHTTPStatus = "http_status_error"
)

// AutofixError is the core interface that all autofix-specific errors implement.
type AutofixError interface {
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
	WithContext(context string) AutofixError
}

// Verify that AutofixError implements the error interface.
var _ error = (AutofixError)(nil)

// Error type constants for consistent error classification
const (
	// Main error types
	ErrorTypeBadModelOutput  = "bad_model_output"
	ErrorTypeNotAutofixable  = "not_autofixable"
	ErrorTypeRetryable       = "retryable"
	ErrorTypeLogic           = "logic"
	ErrorTypeInvalidRequest  = "invalid_request"
	ErrorTypeContextCanceled = "context_canceled"

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
)

// ModelOutputError is an interface for errors related to model output processing
type ModelOutputError interface {
	AutofixError
	Category() string
	ErrorType() string
	FilePath() string
}

// MarkedAutofixError wraps an AutofixError and adds category information
type MarkedAutofixError struct {
	baseError     AutofixError
	errorCategory string
	errorType     string
	filePath      string
}

// Ensure MarkedAutofixError implements both interfaces
var _ AutofixError = (*MarkedAutofixError)(nil)
var _ ModelOutputError = (*MarkedAutofixError)(nil)

// NewMarkedError creates a new MarkedAutofixError
func NewMarkedError(baseError AutofixError, category string, errorType string, filePath string) *MarkedAutofixError {
	return &MarkedAutofixError{
		baseError:     baseError,
		errorCategory: category,
		errorType:     errorType,
		filePath:      filePath,
	}
}

// Implement AutofixError interface
func (e *MarkedAutofixError) Unwrap() error             { return e.baseError }
func (e *MarkedAutofixError) Error() string             { return e.baseError.Error() }
func (e *MarkedAutofixError) Type() string              { return e.baseError.Type() }
func (e *MarkedAutofixError) Retryable() bool           { return e.baseError.Retryable() }
func (e *MarkedAutofixError) RetryDelay() time.Duration { return e.baseError.RetryDelay() }
func (e *MarkedAutofixError) Deterministic() bool       { return e.baseError.Deterministic() }

func (e *MarkedAutofixError) WithContext(context string) AutofixError {
	return &MarkedAutofixError{
		baseError:     e.baseError.WithContext(context),
		errorCategory: e.errorCategory,
		errorType:     e.errorType,
		filePath:      e.filePath,
	}
}

// Implement ModelOutputError interface
func (e *MarkedAutofixError) Category() string  { return e.errorCategory }
func (e *MarkedAutofixError) ErrorType() string { return e.errorType }
func (e *MarkedAutofixError) FilePath() string  { return e.filePath }

// ModelError represents unstructured errors from the model
type ModelError struct {
	Title    string
	Message  string
	Source   string
	Target   string
	Fatal    bool
	Severity ErrorSeverity
}

func (e *ModelError) Error() string {
	return fmt.Sprintf("%s: %s", e.Title, e.Message)
}

// BadModelOutputError indicates autofix could not generate a fix due to the model output.
// Since the model output is non-deterministic, a retry might help.
type BadModelOutputError struct {
	Err error
}

func NewBadModelOutputError(message string, cause error) BadModelOutputError {
	return BadModelOutputError{Err: fmt.Errorf("%s: %w", message, cause)}
}

func (e BadModelOutputError) Unwrap() error             { return e.Err }
func (e BadModelOutputError) Error() string             { return e.Err.Error() }
func (e BadModelOutputError) Type() string              { return ErrorTypeBadModelOutput }
func (e BadModelOutputError) Retryable() bool           { return true }
func (e BadModelOutputError) RetryDelay() time.Duration { return 0 }
func (e BadModelOutputError) Deterministic() bool       { return false }

func (e BadModelOutputError) WithContext(context string) AutofixError {
	return BadModelOutputError{Err: fmt.Errorf("%s: %s", context, e.Err)}
}

// NotAutofixableError indicates that the problem is not autofixable, and a retry will not help.
type NotAutofixableError struct {
	Err error
}

func NewNotAutofixableError(message string) NotAutofixableError {
	return NotAutofixableError{Err: errors.New(message)}
}

func (e NotAutofixableError) Unwrap() error             { return e.Err }
func (e NotAutofixableError) Error() string             { return e.Err.Error() }
func (e NotAutofixableError) Type() string              { return ErrorTypeNotAutofixable }
func (e NotAutofixableError) Retryable() bool           { return false }
func (e NotAutofixableError) RetryDelay() time.Duration { return 0 }
func (e NotAutofixableError) Deterministic() bool       { return true }

func (e NotAutofixableError) WithContext(context string) AutofixError {
	return NotAutofixableError{Err: fmt.Errorf("%s: %s", context, e.Err)}
}

// RetryableError indicates that autofix could not generate a fix due to a transient issue.
// The request should be retried at a later date if still relevant.
type RetryableError struct {
	Err         error
	_RetryDelay time.Duration
}

func NewRetryableError(message string, retryDelay time.Duration) RetryableError {
	return RetryableError{Err: errors.New(message), _RetryDelay: retryDelay}
}

func NewRetryableErrorNoDelay(message string) RetryableError {
	return NewRetryableError(message, 0)
}

func (e RetryableError) Unwrap() error             { return e.Err }
func (e RetryableError) Error() string             { return e.Err.Error() }
func (e RetryableError) Type() string              { return ErrorTypeRetryable }
func (e RetryableError) Retryable() bool           { return true }
func (e RetryableError) RetryDelay() time.Duration { return e._RetryDelay }
func (e RetryableError) Deterministic() bool       { return true }

func (e RetryableError) WithContext(context string) AutofixError {
	return RetryableError{Err: fmt.Errorf("%s: %s", context, e.Err), _RetryDelay: e._RetryDelay}
}

// LogicError indicates that autofix encountered a logic error, for example a bug in the code.
// The request should not be retried.
type LogicError struct {
	Err error
}

func NewLogicError(message string) LogicError {
	return LogicError{Err: errors.New(message)}
}

func (e LogicError) Unwrap() error             { return e.Err }
func (e LogicError) Error() string             { return e.Err.Error() }
func (e LogicError) Type() string              { return ErrorTypeLogic }
func (e LogicError) Retryable() bool           { return false }
func (e LogicError) RetryDelay() time.Duration { return 0 }
func (e LogicError) Deterministic() bool       { return true }

func (e LogicError) WithContext(context string) AutofixError {
	return LogicError{Err: fmt.Errorf("%s: %s", context, e.Err)}
}

// InvalidRequestError indicates that the request to autofix was invalid.
// The request should not be retried.
type InvalidRequestError struct {
	Err error
}

func NewInvalidRequestError(message string) InvalidRequestError {
	return InvalidRequestError{Err: errors.New(message)}
}

func (e InvalidRequestError) Unwrap() error             { return e.Err }
func (e InvalidRequestError) Error() string             { return e.Err.Error() }
func (e InvalidRequestError) Type() string              { return ErrorTypeInvalidRequest }
func (e InvalidRequestError) Retryable() bool           { return false }
func (e InvalidRequestError) RetryDelay() time.Duration { return 0 }
func (e InvalidRequestError) Deterministic() bool       { return true }

func (e InvalidRequestError) WithContext(context string) AutofixError {
	return InvalidRequestError{Err: fmt.Errorf("%s: %s", context, e.Err)}
}

// ContextCanceledError indicates that the operation was canceled due to context cancellation.
// These errors typically indicate client cancellation rather than server failure.
type ContextCanceledError struct {
	Err error
}

func NewContextCanceledError(message string, ctxErr error) ContextCanceledError {
	return ContextCanceledError{Err: fmt.Errorf("%s: %w", message, ctxErr)}
}

func (e ContextCanceledError) Unwrap() error             { return e.Err }
func (e ContextCanceledError) Error() string             { return e.Err.Error() }
func (e ContextCanceledError) Type() string              { return ErrorTypeContextCanceled }
func (e ContextCanceledError) Retryable() bool           { return false }
func (e ContextCanceledError) RetryDelay() time.Duration { return 0 }
func (e ContextCanceledError) Deterministic() bool       { return true }

func (e ContextCanceledError) WithContext(context string) AutofixError {
	return ContextCanceledError{Err: fmt.Errorf("%s: %s", context, e.Err)}
}

// Ensure all error types implement the AutofixError interface
var _ AutofixError = BadModelOutputError{}  //nolint:exhaustruct
var _ AutofixError = NotAutofixableError{}  //nolint:exhaustruct
var _ AutofixError = RetryableError{}       //nolint:exhaustruct
var _ AutofixError = LogicError{}           //nolint:exhaustruct
var _ AutofixError = InvalidRequestError{}  //nolint:exhaustruct
var _ AutofixError = ContextCanceledError{} //nolint:exhaustruct

// Model output error creation helpers
func NewParsingError(message string, cause error) AutofixError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryParsing, "", "")
}

func NewNoReplacementBlockError(message string, cause error, filePath string) AutofixError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryReplacement, ErrorTypeNoReplacementBlock, filePath)
}

func NewBlockMismatchError(message string, cause error, filePath string) AutofixError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryMatching, ErrorTypeBlockMismatch, filePath)
}

func NewFileNotFoundError(message string, cause error, filePath string) AutofixError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryValidation, ErrorTypeFileNotFound, filePath)
}

func NewEllipsisMismatchError(message string, cause error, filePath string) AutofixError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryMatching, ErrorTypeEllipsisMismatch, filePath)
}

// Context error helper
func NewErrorFromContextErr(ctx context.Context, message string) AutofixError {
	if ctx.Err() == nil {
		return nil
	}
	return NewContextCanceledError(message, ctx.Err())
}

// IsErrorOfCategory checks if an error belongs to a specific category
func IsErrorOfCategory(err error, category string) bool {
	if modelErr, ok := err.(ModelOutputError); ok {
		return modelErr.Category() == category
	}
	return false
}

// IsErrorOfType checks if an error has a specific error type
func IsErrorOfType(err error, errorType string) bool {
	if modelErr, ok := err.(ModelOutputError); ok {
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
type HTTPStatusError struct {
	Err         error
	StatusCode  int
	_RetryDelay time.Duration
	_Retryable  bool
}

func NewHTTPStatusError(statusCode int, message string, retryable bool, retryDelay time.Duration) HTTPStatusError {
	return HTTPStatusError{
		Err:         fmt.Errorf("HTTP error %d: %s", statusCode, message),
		StatusCode:  statusCode,
		_Retryable:  retryable,
		_RetryDelay: retryDelay,
	}
}

func (e HTTPStatusError) Unwrap() error             { return e.Err }
func (e HTTPStatusError) Error() string             { return e.Err.Error() }
func (e HTTPStatusError) Type() string              { return ErrorTypeHTTPStatus }
func (e HTTPStatusError) Retryable() bool           { return e._Retryable }
func (e HTTPStatusError) RetryDelay() time.Duration { return e._RetryDelay }
func (e HTTPStatusError) Deterministic() bool       { return true }
func (e HTTPStatusError) GetStatusCode() int        { return e.StatusCode }

func (e HTTPStatusError) WithContext(context string) AutofixError {
	return HTTPStatusError{
		Err:         fmt.Errorf("%s: %s", context, e.Err),
		StatusCode:  e.StatusCode,
		_Retryable:  e._Retryable,
		_RetryDelay: e._RetryDelay,
	}
}

// After the other var declarations, add:
var _ AutofixError = HTTPStatusError{} //nolint:exhaustruct

// ReportErrorToTelemetry reports errors to telemetry systems with appropriate tags
// This emits telemetry events for different error types, including HTTP status errors
func ReportErrorToTelemetry(ctx context.Context, autofixError AutofixError) {
	fields := []kvp.Field{
		kvp.String("autofix_error_type", autofixError.Type()),
	}

	tags := stats.Tags{
		"error_type": autofixError.Type(),
	}

	// HTTP status error reporting
	if httpErr, ok := autofixError.(HTTPStatusError); ok {
		statusCode := httpErr.GetStatusCode()
		fields = append(fields, kvp.Int("http_status_code", statusCode))
		tags["http_status_code"] = fmt.Sprintf("%d", statusCode)

		codeRange := ""
		switch {
		case statusCode >= 400 && statusCode < 500:
			codeRange = "4xx"
		case statusCode >= 500:
			codeRange = "5xx"
		}

		switch statusCode {
		case 400:
			tags["error_reason"] = "bad_request"
		case 401, 403:
			tags["error_reason"] = "authentication"
		case 429:
			tags["error_reason"] = "rate_limited"
		case 500, 502, 503, 504:
			tags["error_reason"] = "server_error"
		default:
			tags["error_reason"] = "unknown_error"
		}

		if statusCode == 429 {
			enhancedctx.Statter(ctx).Counter("rate_limited_requests", tags, 1)
		}

		if codeRange != "" {
			fields = append(fields, kvp.String("http_status_range", codeRange))
			tags["http_status_range"] = codeRange

			// Track status range metrics
			enhancedctx.Statter(ctx).Counter(
				fmt.Sprintf("error.http_status.%s", codeRange),
				tags,
				1,
			)
		}

		// Logs HTTP errors with structured fields
		enhancedctx.Logger(ctx).WithError(autofixError).Error(
			autofixError.Error(),
			fields...,
		)

		// Tracks metrics for HTTP errors
		enhancedctx.Statter(ctx).Counter(
			fmt.Sprintf("error.%s", autofixError.Type()),
			tags,
			1,
		)
	}

	// Checks if this is a model output error with additional info
	if modelErr, ok := autofixError.(ModelOutputError); ok {
		if category := modelErr.Category(); category != "" {
			fields = append(fields, kvp.String("error_category", category))
			tags["error_category"] = category
		}

		if errorType := modelErr.ErrorType(); errorType != "" {
			fields = append(fields, kvp.String("error_specific_type", errorType))
			tags["error_specific_type"] = errorType

			if filePath := modelErr.FilePath(); filePath != "" {
				fields = append(fields, kvp.String("file_path", filePath))
				tags["file_path"] = filePath
			}
		}

		enhancedctx.Logger(ctx).WithError(autofixError).Info(autofixError.Error(), fields...)

		// Tracks metrics based on error type
		if autofixError.Type() != ErrorTypeContextCanceled {
			enhancedctx.Statter(ctx).Counter(fmt.Sprintf("error.%s", autofixError.Type()), tags, 1)

			// If we have category info, track by category too
			if _, hasCategory := tags["error_category"]; hasCategory {
				enhancedctx.Statter(ctx).Counter(
					fmt.Sprintf("error.%s.by_category", autofixError.Type()),
					tags,
					1,
				)
			}
		} else {
			// Tracks cancellations separately
			enhancedctx.Statter(ctx).Counter("context_canceled", tags, 1)
		}
	} else if autofixError.Type() == ErrorTypeContextCanceled {
		// Handles context canceled errors that aren't ModelOutputErrors
		enhancedctx.Logger(ctx).WithError(autofixError).Info("Request canceled by client", fields...)
		enhancedctx.Statter(ctx).Counter("context_canceled", tags, 1)
	} else {
		// Handles other error types that aren't HTTPStatusError or ModelOutputError
		enhancedctx.Logger(ctx).WithError(autofixError).Error(autofixError.Error(), fields...)
		enhancedctx.Statter(ctx).Counter(fmt.Sprintf("error.%s", autofixError.Type()), tags, 1)
	}
}
