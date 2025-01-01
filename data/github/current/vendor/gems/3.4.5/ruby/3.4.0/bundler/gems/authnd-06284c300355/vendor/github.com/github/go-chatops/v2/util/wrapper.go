// Package util provides common utility functions.
package util

import (
	"context"

	chatops "github.com/github/go-chatops/v2"
)

// Hook is a function which takes a request and performs some action, returning
// an error if it should be aborted.
type Hook func(context.Context, *chatops.CommandRequest) error

// WrapCommandFunction wraps a command handler function with a hook.  If the
// hook returns nil (i.e., no error), the handler function executes as normal;
// otherwise, the error is returned, and the handler function is not executed.
func WrapCommandFunction(before Hook, cmd chatops.CommandFunc) chatops.CommandFunc {
	return func(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
		if before != nil {
			err := before(ctx, req)
			if err != nil {
				return nil, err
			}
		}

		return cmd(ctx, req)
	}
}
