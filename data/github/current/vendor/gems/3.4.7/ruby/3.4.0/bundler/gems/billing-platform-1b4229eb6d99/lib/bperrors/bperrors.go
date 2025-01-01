package bperrors

import (
	"errors"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/twitchtv/twirp"
)

type ErrorCode byte

const (
	// The requested resource couldn't be found.
	NotFound ErrorCode = iota
	// The resource already exists.
	AlreadyExists
	// Bad inputs were provided.
	// This is most likely due to invalid arguments.
	BadRequest
	// The caller could not be authenticated with the provided inputs.
	// The request likely lacks sufficient credentials for proper authentication.
	Unauthorized
	// An underlying service is unavailable.
	Unavailable
	// The request timed out.
	Timedout
	// The request was blocked due to rate limiting.
	TooManyRequests
	// The caller does not have sufficient permissions to access to the requested resource.
	Forbidden
	// Any other unexpected error that can't be classified by the above error types.
	Internal
)

func (code ErrorCode) String() string {
	switch code {
	case NotFound:
		return "not found"
	case AlreadyExists:
		return "already exists"
	case BadRequest:
		return "bad request"
	case Unauthorized:
		return "unauthorized"
	case Unavailable:
		return "unavailable"
	case Timedout:
		return "request timed out"
	case TooManyRequests:
		return "too many requests"
	case Forbidden:
		return "forbidden"
	}

	return "internal"
}

// Returns a new Error with the corresponding ErrorCode and OriginalError message.
func NewError(code ErrorCode, originalError error) *Error {
	return &Error{
		ErrorCode:     code,
		OriginalError: originalError,
	}
}

// Returns a new Error with the corresponding ErrorCode and the provided message as both OriginalError and FriendlyError.
// Use this if the original error message is safe to provide to consumers.
func NewFriendlyError(code ErrorCode, friendlyError error) *Error {
	return &Error{
		ErrorCode:     code,
		OriginalError: friendlyError,
		FriendlyError: friendlyError,
	}
}

func GenericInternalError() *Error {
	return NewError(Internal, errors.New("something went wrong"))
}

type Error struct {
	ErrorCode     ErrorCode
	OriginalError error

	// An optional friendly error message typically displayed to consumers.
	FriendlyError error
	// An optional custom error code typically displayed to consumers.
	CustomErrorCode string
}

// Returns the Error with the provided friendly error message.
func (e *Error) WithFriendlyError(friendlyError error) *Error {
	e.FriendlyError = friendlyError
	return e
}

// Returns the Error with the provided custom error code.
func (e *Error) WithCustomCode(customErrorCode string) *Error {
	e.CustomErrorCode = customErrorCode
	return e
}

func (e *Error) Error() string {
	var errorCodeStr = e.ErrorCode.String()
	if len(e.CustomErrorCode) > 0 {
		errorCodeStr = e.CustomErrorCode
	}

	var errorMsgStr = e.OriginalError.Error()
	if e.FriendlyError != nil {
		errorMsgStr = e.FriendlyError.Error()
	}

	return fmt.Sprintf("%s - %s", errorCodeStr, errorMsgStr)
}

// Returns a new twirp.Error with corresponding twirp.ErrorCode and the original error message.
// If the Error has a FriendlyError, its message will be provided via the "friendlyMsg" Twirp meta tag.
// If the Error has a CustomErrorCode, it will be provided via the "customCode" Twirp meta tag.
func (e *Error) ToTwirpError() twirp.Error {
	var twirpErrorCode = twirp.Internal
	switch e.ErrorCode {
	case NotFound:
		twirpErrorCode = twirp.NotFound
	case AlreadyExists:
		twirpErrorCode = twirp.AlreadyExists
	case BadRequest:
		twirpErrorCode = twirp.InvalidArgument
	case Unauthorized:
		twirpErrorCode = twirp.Unauthenticated
	case Unavailable:
		twirpErrorCode = twirp.Unavailable
	case Timedout:
		twirpErrorCode = twirp.DeadlineExceeded
	case TooManyRequests:
		twirpErrorCode = twirp.ResourceExhausted
	case Forbidden:
		twirpErrorCode = twirp.PermissionDenied
	}

	twirpErr := twirp.NewError(twirpErrorCode, e.OriginalError.Error())
	if e.FriendlyError != nil {
		twirpErr = twirpErr.WithMeta("friendlyMsg", e.FriendlyError.Error())
	} else if e.ErrorCode == Internal {
		twirpErr = twirpErr.WithMeta("friendlyMsg", "An unexpected error occurred.")
	}
	if len(e.CustomErrorCode) > 0 {
		twirpErr = twirpErr.WithMeta("customCode", e.CustomErrorCode)
	}

	return twirpErr
}

// Returns a new azcore.ResponseError
func (e *Error) ToAzureError() *azcore.ResponseError {
	var responseErr *azcore.ResponseError
	errors.As(e.OriginalError, &responseErr)
	return responseErr
}
