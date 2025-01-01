package security

import (
	"context"
	"errors"

	chatops "github.com/github/go-chatops/v2"
	"github.com/github/go-chatops/v2/util"
)

// These functions handle wrapping of Chatops RPC callback functions with authorization helpers.

// WrapWithAuthorization wraps an existing chatops command function with
// the security constraints specified in the validator using
// IsRequestAuthorized.  Any prompts required are sent to the specified
// prompter.
func WrapWithAuthorization(v *Validator, p Prompter, f chatops.CommandFunc) chatops.CommandFunc {
	return util.WrapCommandFunction(
		func(ctx context.Context, req *chatops.CommandRequest) error {
			ok, err := v.IsRequestAuthorized(req.User, req.RoomID, req.Method, p)

			if err != nil {
				return err
			}

			// This case should never happen, but if it does, let's
			// fail closed.
			if !ok {
				//nolint:stylecheck,revive // not changing error message to avoid breaking changes
				return errors.New("No error happened, but authorization was denied.")
			}
			return nil
		},
		f,
	)
}
