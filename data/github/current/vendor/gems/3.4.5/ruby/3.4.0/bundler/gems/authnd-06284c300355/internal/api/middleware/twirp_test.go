package middleware

import (
	"context"
	"testing"

	"github.com/github/go-auth/hmac"
	mwhmac "github.com/github/go-http/v2/middleware/hmac"
	"github.com/stretchr/testify/assert"
)

func TestVerifyRequestHMACHook(t *testing.T) {
	ctxWithRequestHMACFn := func(key string) func(context.Context) context.Context {
		return func(ctx context.Context) context.Context {
			return mwhmac.WithRequestHMAC(ctx, hmac.NewRequestHMAC(key).String())
		}
	}

	const (
		secret1 = "octocat"
		secret2 = "top-secret-key"
		secret3 = "yet-another-top-secret-key"
	)

	var tests = []struct {
		name         string
		keys         []string
		ctxFn        func(context.Context) context.Context
		valid        bool
		expectedHash string
	}{
		{
			name:         "valid on single key",
			keys:         []string{secret1},
			ctxFn:        ctxWithRequestHMACFn(secret1),
			valid:        true,
			expectedHash: "b2N0b2NhdOOwxEKY/BwU",
		},
		{
			name:         "valid on first key",
			keys:         []string{secret1, secret2},
			ctxFn:        ctxWithRequestHMACFn(secret1),
			valid:        true,
			expectedHash: "b2N0b2NhdOOwxEKY/BwU",
		},
		{
			name:         "valid on last key",
			keys:         []string{secret1, secret2, secret3},
			ctxFn:        ctxWithRequestHMACFn(secret3),
			valid:        true,
			expectedHash: "eWV0LWFub3RoZXItdG9w",
		},
		{
			name:  "invalid due to secret",
			keys:  []string{secret1, secret2},
			ctxFn: ctxWithRequestHMACFn("invalid"),
			valid: false,
		},
		{
			name: "invalid due no Request-HMAC in context",
			keys: []string{secret1, secret2},
			ctxFn: func(ctx context.Context) context.Context {
				return ctx
			},
			valid: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			hooks := verifyRequestHMACHooks(tc.keys...)
			ctx, err := hooks.RequestReceived(tc.ctxFn(context.Background()))
			if tc.valid {
				assert.NoError(t, err)
			} else {
				assert.Error(t, err)
				assert.NotNil(t, ctx)
			}
			assert.Equal(t, tc.expectedHash, GetValidatingHMAC(ctx))
		})
	}
}
