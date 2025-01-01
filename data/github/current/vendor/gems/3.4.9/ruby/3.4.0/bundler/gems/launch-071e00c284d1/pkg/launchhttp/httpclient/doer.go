package httpclient

import (
	"context"
	"net/http"

	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/reqmw"
)

// applyMiddleware applies any options that are implemented as request middleware to the operation
func applyMiddleware(ctx context.Context, dst any, attempt int, do operation, o *DoOptions, hc *HookContext) (chain launchhttp.RequestMiddleware) {
	// chain in the reverse order that the middleware should be called.

	// called last
	chain = &doer{
		ctx:       ctx,
		dst:       dst,
		attempt:   attempt,
		operation: do,
		hc:        hc,
	}

	if o.Breaker != nil {
		chain = reqmw.NewBreakerMiddleware(chain, o.Breaker)
	}

	return chain
}

// doer adapts the operation to the RequestMiddleware interface
type doer struct {
	ctx       context.Context
	dst       any
	attempt   int
	hc        *HookContext
	operation operation
}

func (df *doer) Do(req *http.Request) (*http.Response, error) {
	return df.operation(df.ctx, req, df.dst, df.attempt, df.hc)
}
