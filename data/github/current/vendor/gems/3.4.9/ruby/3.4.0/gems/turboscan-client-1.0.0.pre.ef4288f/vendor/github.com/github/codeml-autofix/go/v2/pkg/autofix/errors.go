package autofix

import (
	"context"
	"fmt"

	llmErrors "github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

// ErrorSeverity levels
type ErrorSeverity int

const (
	// Ignore errors are not errors, but rather situations
	// where we needed to skip processing. Eg- when we
	// cancel a request due to other changes.
	Ignore ErrorSeverity = iota

	// Low is a low-severity error: we were unable to propose a fix, but overall the
	// system is probably working fine.
	//
	// For example, the model sends us a response that we are unable to process,
	// or the content filter suppresses a response.
	//
	// Low-severity errors should be logged; if they happen frequently they could
	// indicate a problem.
	Low

	// High is a high-severity error: something is not working as expected, but the system
	// can probably continue to function.
	//
	// For example, an internal invariant is violated.
	//
	// High-severity errors should be logged and reported to the maintainers for
	// investigation.
	High

	// Critical is a critical error: something is seriously wrong, and the system is unlikely
	// to be able to operate normally.
	//
	// For example, the model is down.
	//
	// Critical errors should be logged and reported to the maintainers
	// immediately.
	Critical

	// ErrorTypeHTTPStatus indicates a network problem with the request.
	ErrorTypeHTTPStatus = "http_status_error"
)

// AutofixError is the core interface that all autofix-specific errors implement.
type AutofixError interface { //nolint:revive // Revive wants us to change this name and remove "Autofix", but it's fine the way it is.
	// The underlying error.
	Unwrap() error

	// The underlying error message.
	Error() string

	// The type of error.
	Type() string

	// Retryable is true if the request can be retried. For example, if there is
	// a transient issue with CAPI or another dependency.
	Retryable() bool

	// Deterministic is true if the request failed due a deterministic operation.
	// For example, it is true if the request fails due to the problem type being
	// explicitly excluded from autofix, and it is false if the request fails due
	// to the model output.
	Deterministic() bool

	// WithContext returns a new error of the same type with the given context.
	WithContext(context string) AutofixError

	// ErrorSeverity returns the severity of the error.
	// This is used for telemetry and logging purposes.
	ErrorSeverity() ErrorSeverity
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
	} else {
		// We should not reach here, and if we do, we should fix.
		return High
	}
}

// ModelOutputError is an interface for errors related to model output processing
type ModelOutputError interface {
	AutofixError
	Category() string
	ErrorType() string
	FilePath() string
	ErrorSeverity() ErrorSeverity
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
func NewMarkedError(baseError AutofixError, category, errorType, filePath string) *MarkedAutofixError {
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

// Unwrap returns the underlying error of the MarkedAutofixError
func (e *MarkedAutofixError) Unwrap() error { return e.baseError }

// Error returns the error message of the MarkedAutofixError
func (e *MarkedAutofixError) Error() string { return e.baseError.Error() }

// Type returns the type of the MarkedAutofixError
func (e *MarkedAutofixError) Type() string { return e.baseError.Type() }

// Retryable returns true if the error is retryable based on its category or type
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

// Deterministic returns true if the error is deterministic
func (e *MarkedAutofixError) Deterministic() bool { return e.baseError.Deterministic() }

// ErrorSeverity returns the severity of the error
func (e *MarkedAutofixError) ErrorSeverity() ErrorSeverity {
	return e.baseError.ErrorSeverity()
}

// WithContext returns a new MarkedAutofixError with the given context
func (e *MarkedAutofixError) WithContext(context string) AutofixError {
	return &MarkedAutofixError{
		baseError:     e.baseError.WithContext(context),
		errorCategory: e.errorCategory,
		errorType:     e.errorType,
		filePath:      e.filePath,
	}
}

// Category returns the category of the MarkedAutofixError
func (e *MarkedAutofixError) Category() string { return e.errorCategory }

// ErrorType returns the error type of the MarkedAutofixError
func (e *MarkedAutofixError) ErrorType() string { return e.errorType }

// FilePath returns the file path associated with the MarkedAutofixError
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

// NewBadModelOutputError creates a new BadModelOutputError with the given message and cause.
func NewBadModelOutputError(message string, cause error) BadModelOutputError {
	return BadModelOutputError{Err: st.EnsureStackTrace(cause, message)}
}

// Unwrap returns the underlying error of the BadModelOutputError
func (e BadModelOutputError) Unwrap() error { return e.Err }

// Error returns the error message of the BadModelOutputError
func (e BadModelOutputError) Error() string { return e.Err.Error() }

// Type returns the type of the BadModelOutputError
func (e BadModelOutputError) Type() string { return ErrorTypeBadModelOutput }

// Retryable returns true for BadModelOutputError, indicating that a retry might help
func (e BadModelOutputError) Retryable() bool { return true }

// Deterministic returns false for BadModelOutputError, indicating that the error is non-deterministic
func (e BadModelOutputError) Deterministic() bool { return false }

// ErrorSeverity returns the severity of the BadModelOutputError.
func (e BadModelOutputError) ErrorSeverity() ErrorSeverity {
	return getSeverity(e.Type())
}

// WithContext returns a new BadModelOutputError with the given context
func (e BadModelOutputError) WithContext(context string) AutofixError {
	return BadModelOutputError{Err: st.EnsureStackTrace(e.Err, context)}
}

// NotAutofixableError indicates that the problem is not autofixable, and a retry will not help.
type NotAutofixableError struct {
	Err error
}

// NewNotAutofixableError creates a new NotAutofixableError with the given message.
func NewNotAutofixableError(message string) NotAutofixableError {
	return NotAutofixableError{Err: errors.New(message)}
}

// Unwrap returns the underlying error of the NotAutofixableError
func (e NotAutofixableError) Unwrap() error { return e.Err }

// Error returns the error message of the NotAutofixableError
func (e NotAutofixableError) Error() string { return e.Err.Error() }

// Type returns the type of the NotAutofixableError
func (e NotAutofixableError) Type() string { return ErrorTypeNotAutofixable }

// Retryable returns false for NotAutofixableError, indicating that a retry will not help
func (e NotAutofixableError) Retryable() bool { return false }

// Deterministic returns true for NotAutofixableError, indicating that the error is deterministic
func (e NotAutofixableError) Deterministic() bool { return true }

// ErrorSeverity returns the severity of the NotAutofixableError
func (e NotAutofixableError) ErrorSeverity() ErrorSeverity {
	return getSeverity(e.Type())
}

// WithContext returns a new NotAutofixableError with the given context
func (e NotAutofixableError) WithContext(context string) AutofixError {
	return NotAutofixableError{Err: st.EnsureStackTrace(e.Err, context)}
}

// RetryableError indicates that autofix could not generate a fix due to a transient issue.
// The request should be retried at a later date if still relevant.
type RetryableError struct {
	Err error
}

// NewRetryableError creates a new RetryableError with the given message.
func NewRetryableError(message string) RetryableError {
	return RetryableError{Err: errors.New(message)}
}

// Unwrap returns the underlying error of the RetryableError
func (e RetryableError) Unwrap() error { return e.Err }

// Error returns the error message of the RetryableError
func (e RetryableError) Error() string { return e.Err.Error() }

// Type returns the type of the RetryableError
func (e RetryableError) Type() string { return ErrorTypeRetryable }

// Retryable returns true for RetryableError, indicating that a retry might help
func (e RetryableError) Retryable() bool { return true }

// Deterministic returns true for RetryableError, indicating that the error is deterministic
func (e RetryableError) Deterministic() bool { return true }

// ErrorSeverity returns the severity of the RetryableError
func (e RetryableError) ErrorSeverity() ErrorSeverity {
	return getSeverity(e.Type())
}

// WithContext returns a new RetryableError with the given context
func (e RetryableError) WithContext(context string) AutofixError {
	return RetryableError{Err: st.EnsureStackTrace(e.Err, context)}
}

// LogicError indicates that autofix encountered a logic error, for example a bug in the code.
// The request should not be retried.
type LogicError struct {
	Err error
}

// NewLogicError creates a new LogicError with the given message.
func NewLogicError(message string) LogicError {
	return LogicError{Err: errors.New(message)}
}

// Unwrap returns the underlying error of the LogicError
func (e LogicError) Unwrap() error { return e.Err }

// Error returns the error message of the LogicError
func (e LogicError) Error() string { return e.Err.Error() }

// Type returns the type of the LogicError
func (e LogicError) Type() string { return ErrorTypeLogic }

// Retryable returns false for LogicError, indicating that a retry will not help
func (e LogicError) Retryable() bool { return false }

// Deterministic returns true for LogicError, indicating that the error is deterministic
func (e LogicError) Deterministic() bool { return true }

// ErrorSeverity returns the severity of the LogicError
func (e LogicError) ErrorSeverity() ErrorSeverity {
	return getSeverity(e.Type())
}

// WithContext returns a new LogicError with the given context
func (e LogicError) WithContext(context string) AutofixError {
	return LogicError{Err: st.EnsureStackTrace(e.Err, context)}
}

// InvalidRequestError indicates that the request to autofix was invalid.
// The request should not be retried.
type InvalidRequestError struct {
	Err error
}

// NewInvalidRequestError creates a new InvalidRequestError with the given message.
func NewInvalidRequestError(message string) InvalidRequestError {
	return InvalidRequestError{Err: errors.New(message)}
}

// Unwrap returns the underlying error of the InvalidRequestError
func (e InvalidRequestError) Unwrap() error { return e.Err }

// Error returns the error message of the InvalidRequestError
func (e InvalidRequestError) Error() string { return e.Err.Error() }

// Type returns the type of the InvalidRequestError
func (e InvalidRequestError) Type() string { return ErrorTypeInvalidRequest }

// Retryable returns false for InvalidRequestError, indicating that a retry will not help
func (e InvalidRequestError) Retryable() bool { return false }

// Deterministic returns true for InvalidRequestError, indicating that the error is deterministic
func (e InvalidRequestError) Deterministic() bool { return true }

// ErrorSeverity returns the severity of the InvalidRequestError
func (e InvalidRequestError) ErrorSeverity() ErrorSeverity {
	return getSeverity(e.Type())
}

// WithContext returns a new InvalidRequestError with the given context
func (e InvalidRequestError) WithContext(context string) AutofixError {
	return InvalidRequestError{Err: st.EnsureStackTrace(e.Err, context)}
}

// ContextCanceledError indicates that the operation was canceled due to context cancellation.
// These errors typically indicate client cancellation rather than server failure.
type ContextCanceledError struct {
	Err error
}

// NewContextCanceledError creates a new ContextCanceledError with the given message and cause.
func NewContextCanceledError(message string, ctxErr error) ContextCanceledError {
	return ContextCanceledError{Err: st.EnsureStackTrace(ctxErr, message)}
}

// Unwrap returns the underlying error of the ContextCanceledError
func (e ContextCanceledError) Unwrap() error { return e.Err }

// Error returns the error message of the ContextCanceledError
func (e ContextCanceledError) Error() string { return e.Err.Error() }

// Type returns the type of the ContextCanceledError
func (e ContextCanceledError) Type() string { return ErrorTypeContextCanceled }

// Retryable returns false for ContextCanceledError, indicating that a retry will not help
func (e ContextCanceledError) Retryable() bool { return false }

// Deterministic returns true for ContextCanceledError, indicating that the error is deterministic
func (e ContextCanceledError) Deterministic() bool { return true }

// ErrorSeverity returns the severity of the ContextCanceledError
func (e ContextCanceledError) ErrorSeverity() ErrorSeverity {
	return getSeverity(e.Type())
}

// WithContext returns a new ContextCanceledError with the given context
func (e ContextCanceledError) WithContext(context string) AutofixError {
	return ContextCanceledError{Err: st.EnsureStackTrace(e.Err, context)}
}

// LLMErrorWrapper wraps an llmErrors.LLMError to implement the AutofixError interface.
type LLMErrorWrapper struct {
	Err llmErrors.LLMError
}

// NewLLMError creates a new LLMErrorWrapper from the given llmErrors.LLMError.
func NewLLMError(err llmErrors.LLMError) LLMErrorWrapper {
	return LLMErrorWrapper{Err: err}
}

// Unwrap returns the underlying llmErrors.LLMError
func (e LLMErrorWrapper) Unwrap() error { return e.Err }

// Error returns the error message of the LLMErrorWrapper
func (e LLMErrorWrapper) Error() string { return e.Err.Error() }

// Type returns the type of the LLMErrorWrapper
func (e LLMErrorWrapper) Type() string { return e.Err.Type() }

// Retryable returns true if the underlying llmErrors.LLMError is retryable
func (e LLMErrorWrapper) Retryable() bool { return e.Err.Retryable() }

// Deterministic returns true if the underlying llmErrors.LLMError is deterministic
func (e LLMErrorWrapper) Deterministic() bool { return e.Err.Deterministic() }

// ErrorSeverity maps the llmErrors.LLMError severity to the AutofixError severity.
func (e LLMErrorWrapper) ErrorSeverity() ErrorSeverity {
	wrappedSeverity := e.Err.ErrorSeverity()
	switch wrappedSeverity {
	case llmErrors.Critical:
		return Critical
	case llmErrors.High:
		return High
	case llmErrors.Low:
		return Low
	case llmErrors.Ignore:
		return Ignore
	default:
		// Missing severity mapping, default to High
		return High
	}
}

// WithContext returns a new LLMErrorWrapper with the given context
func (e LLMErrorWrapper) WithContext(context string) AutofixError {
	return LLMErrorWrapper{Err: e.Err.WithContext(context)}
}

// Ensure all error types implement the AutofixError interface
var _ AutofixError = BadModelOutputError{}  //nolint:exhaustruct // Just for type checking
var _ AutofixError = NotAutofixableError{}  //nolint:exhaustruct // Just for type checking
var _ AutofixError = RetryableError{}       //nolint:exhaustruct // Just for type checking
var _ AutofixError = LogicError{}           //nolint:exhaustruct // Just for type checking
var _ AutofixError = InvalidRequestError{}  //nolint:exhaustruct // Just for type checking
var _ AutofixError = ContextCanceledError{} //nolint:exhaustruct // Just for type checking
var _ AutofixError = LLMErrorWrapper{}      //nolint:exhaustruct // Just for type checking

// NewParsingError creates a model output parsing error.
func NewParsingError(message string, cause error) AutofixError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryParsing, "", "")
}

// NewNoReplacementBlockError creates a new ModelOutputError for missing replacement blocks in the model output.
func NewNoReplacementBlockError(message string, cause error, filePath string) AutofixError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryReplacement, ErrorTypeNoReplacementBlock, filePath)
}

// NewBlockMismatchError creates a new ModelOutputError for mismatched code blocks in the model output.
func NewBlockMismatchError(message string, cause error, filePath string) AutofixError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryMatching, ErrorTypeBlockMismatch, filePath)
}

// NewFileNotFoundError creates a new ModelOutputError for file not found errors in the model output.
func NewFileNotFoundError(message string, cause error, filePath string) AutofixError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryValidation, ErrorTypeFileNotFound, filePath)
}

// NewEllipsisMismatchError creates a new ModelOutputError for ellipsis mismatch errors in the model output.
func NewEllipsisMismatchError(message string, cause error, filePath string) AutofixError {
	baseErr := NewBadModelOutputError(message, cause)
	return NewMarkedError(baseErr, ErrorCategoryMatching, ErrorTypeEllipsisMismatch, filePath)
}

// NewErrorFromContextErr creates a ContextCanceledError if the context has been canceled or has exceeded its deadline.
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

// WithClientInfo adds client information to an AutofixError
func WithClientInfo(ctx context.Context, err AutofixError) AutofixError {
	clientName := enhancedctx.ClientNameFromContext(ctx)
	if clientName == "" {
		return err
	}

	return err.WithContext(fmt.Sprintf("client: %s", clientName))
}

// ReportErrorToTelemetry reports errors to telemetry systems with appropriate tags
// This emits telemetry events for different error types, including HTTP status errors
func ReportErrorToTelemetry(ctx context.Context, autofixError AutofixError) {
	clientName := enhancedctx.ClientNameFromContext(ctx)
	fields := []kvp.Field{
		kvp.String("autofix_error_type", autofixError.Type()),
		kvp.String("client_name", clientName),
	}

	tags := stats.Tags{
		"error_type":  autofixError.Type(),
		"client_name": clientName,
	}

	// HTTP status error reporting
	var httpErr llmErrors.HTTPStatusError
	if llmErrWrapper, ok := autofixError.(LLMErrorWrapper); ok && errors.As(llmErrWrapper.Err, &httpErr) {
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
