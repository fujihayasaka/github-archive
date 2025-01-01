// Package requestid provides some helpers for Github Request IDs.
package requestid

import (
	"context"

	"github.com/github/go-http/middleware/requestid"

	"github.com/github/launch/pkg/mu/muhttp/mw"
)

// ForwardRequestIDToTwirp attaches the request ID to the context for the
// requestid middleware to use.
func ForwardRequestIDToTwirp(ctx context.Context) context.Context {
	return requestid.WithGitHubRequestID(ctx, mw.GetGitHubRequestID(ctx))
}

// RequestID is a request ID.
type RequestID string
