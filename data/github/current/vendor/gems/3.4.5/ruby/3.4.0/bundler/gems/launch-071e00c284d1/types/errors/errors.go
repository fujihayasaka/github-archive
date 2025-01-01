package errors

import (
	"fmt"
	"net/http"
	"regexp"
	"strings"

	errs "github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/types"
)

type causer interface {
	Cause() error
}

type httpError struct {
	code int
	u    string
}

var _ HTTPError = (*httpError)(nil)

type HTTPError interface {
	error
	MatchStatusCodes(codes ...int) bool
}

func NewHTTPError(resp *http.Response) error {
	if resp == nil {
		return &httpError{code: 0, u: ""}
	}
	code := resp.StatusCode
	u := ""
	if resp.Request != nil && resp.Request.URL != nil {
		u = resp.Request.URL.String()
	}
	return &httpError{code: code, u: u}
}

func (e *httpError) Error() string {
	return fmt.Sprintf("unexpected response `%d` from `%s`", e.statusCode(), e.cleanURL())
}

func (e *httpError) statusCode() int {
	return e.code
}

func (e *httpError) url() string {
	return e.u
}

var urlCleaner = regexp.MustCompile(`[0-9]+`)

func (e *httpError) cleanURL() string {
	return urlCleaner.ReplaceAllString(e.url(), "***")
}

func (e *httpError) MatchStatusCodes(codes ...int) bool {
	for _, code := range codes {
		if code == e.statusCode() {
			return true
		}
	}
	return false
}

func (e *httpError) Code() int {
	return e.code
}

func GetHTTPError(err error) HTTPError {
	for err != nil {
		// Check if the err is a Message
		httpErr, ok := err.(HTTPError)
		if ok {
			return httpErr
		}

		// Check the underlying cause for a Message
		cause, ok := err.(causer)
		if !ok {
			break
		}

		err = cause.Cause()
	}
	return nil
}

type GraphQLError struct {
	err error
}

func NewGraphQLError(err error) error {
	return &GraphQLError{err: err}
}

// Used to parse request IDs out of graphql error messages (they look like "Please include `0401:B462:E560A07:15208BE3:5F593141` when reporting this issue.")
var requestIDCleaner = regexp.MustCompile("`[0-9a-zA-Z:]+`")

func (e *GraphQLError) Error() string {
	return fmt.Sprintf("error making graphql request: %s", requestIDCleaner.ReplaceAllString(e.err.Error(), "<request-id>"))
}

func (e *GraphQLError) Cause() error {
	return e.err
}

// Unwrap provides compatibility for Go 1.13 error chains.
func (e *GraphQLError) Unwrap() error {
	return e.err
}

func (e *GraphQLError) StackTrace() errs.StackTrace {
	type stackTracer interface {
		StackTrace() errs.StackTrace
	}
	if st, ok := e.err.(stackTracer); ok {
		return st.StackTrace()
	}
	return nil
}

func (e *GraphQLError) Rollup(stacktrace errs.StackTrace) string {
	// Use the last (first in execution) github client line from the stack trace.
	// If no lines can be determined to come from the app then use the first line.
	for i := len(stacktrace) - 1; i >= 0; i-- {
		line := stacktrace[i]
		if strings.HasPrefix(fmt.Sprintf("%+s", line), "github.com/github/launch/clients/github.(*client)") {
			return fmt.Sprintf("%+v", line)
		}
	}
	return ""
}

type unreachableCommitError struct {
	error
}

func NewUnreachableCommitError(commitOID types.CommitSha) error {
	return &unreachableCommitError{
		errs.Errorf("This run was triggered by the commit `%s` which is not referenced by any branches or tags in this repository. It is either an orphaned commit or from a fork of this repository.", commitOID.String()),
	}
}

func IsUnreachableCommitError(err error) bool {
	_, ok := err.(*unreachableCommitError)
	return ok
}

type forbiddenInternalActionError struct {
	message string
}

func (fw forbiddenInternalActionError) Error() string {
	return fw.message
}

func NewForbiddenInternalActionError(repoNames []string) error {
	return &forbiddenInternalActionError{
		message: fmt.Sprintf("Cannot access repositories '%s'.", strings.Join(repoNames, ", ")),
	}
}

func IsForbiddenInternalActionError(err error) bool {
	_, ok := err.(*forbiddenInternalActionError)
	return ok
}

type InternalError struct {
	Err error
}

func (e InternalError) Error() string {
	return e.Err.Error()
}

func NewInternalError(e error) *InternalError {
	return &InternalError{e}
}

// IsInternalError indicates the error chain includes an InternalError
func IsInternalError(err error) bool {
	var internalError *InternalError
	return errs.As(err, &internalError)
}

type NotFoundError struct {
	Err error
}

func NewNotFoundError(e error) *NotFoundError {
	return &NotFoundError{e}
}

func (e *NotFoundError) Error() string {
	return e.Err.Error()
}

// Replication lag can cause "Not Found" responses
// Implementing IsRetryable() so aqueduct jobs will be retried
func (e *NotFoundError) IsRetryable() bool {
	return true
}

// Retrieve error details from the wrapped error
func (e *NotFoundError) Context() *kvp.KVP {
	type contexter interface {
		Context() *kvp.KVP
	}

	ctxer, ok := e.Err.(contexter)
	if !ok {
		return nil
	}

	return ctxer.Context()
}

// RefResolutionError occurs when a ref is unable to be resolved from the API.
type RefResolutionError struct {
	Count int
}

func (e *RefResolutionError) Error() string {
	return fmt.Sprintf("Unable to resolve ref after %d tries", e.Count)
}

// CheckRefProtectedRuleError occurs when a ref is unable to be resolved from the API.
type CheckRefProtectedRuleError struct {
	Count int
}

func (e *CheckRefProtectedRuleError) Error() string {
	return fmt.Sprintf("Unable to check branch protection rules for ref after %d tries", e.Count)
}

type ForbiddenError struct {
	Err error
}

func (e *ForbiddenError) Error() string {
	return e.Err.Error()
}

func NewForbiddenError(err error) error {
	return &ForbiddenError{Err: err}
}
