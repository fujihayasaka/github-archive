package ratelimit

import (
	"fmt"
	"net/http"

	terrors "github.com/github/launch/types/errors"
)

type Error struct {
	msg        string
	statusCode int
}

func (r *Error) Error() string {
	return r.msg
}

func (r *Error) RateLimited() bool {
	return true
}

var _ terrors.RateLimited = (*Error)(nil)
var _ terrors.HTTPError = (*Error)(nil)

func New(msg string, statusCode int) error {
	return &Error{msg, statusCode}
}

func ErrorFromResponse(r *http.Response) error {
	// Attempt to read the error message from the response body.
	body, _ := readBodyRepeatable(r)
	errMsg := errMsgFromBody(body)

	var msg string
	if errMsg == "" {
		msg = "GitHub rate limit exceeded"
	} else {
		msg = fmt.Sprintf("GitHub rate limit exceeded: %s", errMsg)
	}
	return &Error{msg, r.StatusCode}
}

func (r *Error) MatchStatusCodes(statusCodes ...int) bool {
	for _, code := range statusCodes {
		if code == r.statusCode {
			return true
		}
	}

	return false
}

func NewMockRateLimitError(msg string, statusCode int) error {
	return &Error{msg, statusCode}
}
