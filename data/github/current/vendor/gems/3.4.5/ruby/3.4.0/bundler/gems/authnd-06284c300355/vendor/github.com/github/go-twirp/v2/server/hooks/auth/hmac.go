// Package auth provides Twirp hooks for authenticating requests.
package auth

import (
	"context"

	"github.com/github/go-auth/hmac"
	mwhmac "github.com/github/go-http/v2/middleware/hmac"
	"github.com/twitchtv/twirp"
)

// VerifyRequestHMACHooks returns a Twirp hook that verifies the Request-HMAC
// value using the provided keys. Multiple keys are allowed to enable key
// rotation. If any keys successfully validate, the request is allowed to
// continue. If none of the keys validate, an error is returned and the request
// will fail.
//
// The value of the Request-HMAC header must be put into the request context.
// You can use middleware.RequestHMAC for this.
func VerifyRequestHMACHooks(keys ...string) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		RequestReceived: func(ctx context.Context) (context.Context, error) {
			if len(keys) == 0 {
				return ctx, twirp.InternalError("no HMAC keys are defined")
			}

			value := mwhmac.GetRequestHMAC(ctx)
			if value == "" {
				return ctx, twirp.NewError(twirp.Unauthenticated, "no Request-HMAC provided")
			}

			reqHMAC, err := hmac.ParseRequestHMAC(value)
			if err != nil {
				return ctx, twirp.NewError(twirp.Unauthenticated, err.Error())
			}

			for _, key := range keys {
				err = reqHMAC.Validate(key)
				if err == nil {
					return ctx, nil
				}
			}

			return ctx, twirp.NewError(twirp.Unauthenticated, err.Error())
		},
	}
}
