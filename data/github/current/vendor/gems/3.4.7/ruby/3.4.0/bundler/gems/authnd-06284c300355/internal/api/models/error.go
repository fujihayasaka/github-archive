package models

import (
	"fmt"
	"strings"

	pb "github.com/github/authnd/client/proto/authentication/v0"
)

// AuthenticationFailure represents an error from validating credentials.
// Returning an error of this type indicates to the user that no "error" occurred, but the credentials were considered invalid.
type AuthenticationFailure struct {
	// Code is the class of error, such as ssh public key mismatch, unknown
	// user, token not found.
	Code pb.AuthenticateResponse_Result
}

func (e *AuthenticationFailure) Error() string {
	var b strings.Builder

	if e.Code != 0 {
		fmt.Fprintf(&b, "<%s> ", e.Code.String())
	} else {
		fmt.Fprintf(&b, "<%s> ", pb.AuthenticateResponse_RESULT_FAILED_GENERIC.String())
	}

	return b.String()
}

func (e *AuthenticationFailure) Is(err error) bool {
	failure, ok := err.(*AuthenticationFailure)
	return ok && failure.Code == e.Code
}
