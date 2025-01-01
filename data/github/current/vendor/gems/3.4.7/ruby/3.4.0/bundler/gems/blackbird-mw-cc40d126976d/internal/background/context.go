package background

import (
	"context"

	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-reqmeta"
)

// Create a new background context (using `context.Background()`), but copy over
// request_id and request metadata for logging and stats.
func Context(ctx context.Context) context.Context {
	bgCtx := requestid.WithGitHubRequestID(context.Background(), requestid.GetGitHubRequestID(ctx))

	if m, ok := reqmeta.GetRequestMetadata(ctx); ok {
		bgCtx = reqmeta.WithRequestMetadata(bgCtx, m.Copy())
	}

	return bgCtx
}
