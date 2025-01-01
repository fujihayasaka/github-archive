package errors

import (
	"net/http"

	"github.com/twitchtv/twirp"
)

// ExtractCode gets the error's twirp.ErrorCode, if it's a twirp.Error error.
func ExtractCode(err error) twirp.ErrorCode {
	if twirpErr, ok := err.(twirp.Error); ok {
		return twirpErr.Code()
	}
	return twirp.Unknown
}

// ExtractHTTPError gets the error's code as an HTTP code and the error's message, if it's a user error.
func ExtractHTTPError(err error) (int, string, bool) {
	if twirpError, ok := err.(twirp.Error); ok {
		switch twirpError.Code() {
		case twirp.InvalidArgument:
			return http.StatusUnprocessableEntity, twirpError.Msg(), true
		case twirp.FailedPrecondition:
			return http.StatusUnprocessableEntity, "Bad request - " + twirpError.Msg(), true
		case twirp.NotFound:
			return http.StatusNotFound, twirpError.Msg(), true
		case twirp.PermissionDenied:
			return http.StatusForbidden, "Forbidden", true
		case twirp.Unauthenticated:
			return http.StatusUnauthorized, "Unauthorized", true
		case twirp.ResourceExhausted:
			return http.StatusTooManyRequests, twirpError.Msg(), true
		}
	}

	return 0, "", false
}

// CallerShouldReportError checks if an error is based on a twirp.Error type.
func CallerShouldReportError(err error) bool {
	if _, ok := err.(twirp.Error); ok {
		return ok
	}

	return false
}

// NewUnimplementedError returns a Twirp error for "Unimplemented"
func NewUnimplementedError(format string, params ...any) error {
	return twirp.NewErrorf(twirp.Unimplemented, format, params...)
}

// NewInvalidArgumentError returns a Twirp error for "Invalid Argument"
func NewInvalidArgumentError(format string, params ...any) error {
	return twirp.NewErrorf(twirp.InvalidArgument, format, params...)
}

// NewInternalError returns a Twirp error for "Internal"
func NewInternalError(format string, params ...any) error {
	return twirp.NewErrorf(twirp.Internal, format, params...)
}

// NewFailedPrecondition returns a Twirp error for "FailedPrecondition"
func NewFailedPrecondition(format string, params ...any) error {
	return twirp.NewErrorf(twirp.FailedPrecondition, format, params...)
}

// NewUnavailableError returns a Twirp error for "Unavailable"
func NewUnavailableError(format string, params ...any) error {
	return twirp.NewErrorf(twirp.Unavailable, format, params...)
}

// NewNotFoundError returns a Twirp error for "NotFound"
func NewNotFoundError(format string, params ...any) error {
	return twirp.NewErrorf(twirp.NotFound, format, params...)
}

// NewResourceExhaustedError returns a Twirp error for "ResourceExhausted"
func NewResourceExhaustedError(format string, params ...any) error {
	return twirp.NewErrorf(twirp.ResourceExhausted, format, params...)
}

// NewDeadlineExceededError returns a Twirp error for "DeadlineExceeded"
func NewDeadlineExceededError(format string, params ...any) error {
	return twirp.NewErrorf(twirp.DeadlineExceeded, format, params...)
}

// NewPermissionDeniedError returns a Twirp error for "PermissionDenied"
func NewPermissionDeniedError(format string, params ...any) error {
	return twirp.NewErrorf(twirp.PermissionDenied, format, params...)
}

// NewAlreadyExistsError returns a Twirp error for "AlreadyExists"
func NewAlreadyExistsError(format string, params ...any) error {
	return twirp.NewErrorf(twirp.AlreadyExists, format, params...)
}
