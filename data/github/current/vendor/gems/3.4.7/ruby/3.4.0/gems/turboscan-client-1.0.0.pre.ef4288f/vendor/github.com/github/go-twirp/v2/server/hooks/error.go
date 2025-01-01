// Package hooks provides Twirp hooks for capturing errors in the context.
package hooks

import (
	"context"

	"github.com/twitchtv/twirp"
)

type ctxTwirpError struct{}

// StoreTwirpErrorHooks will capture any twirp.Errors and store them in the Context.
func StoreTwirpErrorHooks() *twirp.ServerHooks {
	return &twirp.ServerHooks{
		Error: func(ctx context.Context, err twirp.Error) context.Context {
			return context.WithValue(ctx, ctxTwirpError{}, err)
		},
	}
}

// GetTwirpError will return the twirp.Error that was stored in the Context, and true,
// if one occurred. If there was no error it will return nil and false.
func GetTwirpError(ctx context.Context) (twirp.Error, bool) {
	val, ok := ctx.Value(ctxTwirpError{}).(twirp.Error)
	return val, ok
}
