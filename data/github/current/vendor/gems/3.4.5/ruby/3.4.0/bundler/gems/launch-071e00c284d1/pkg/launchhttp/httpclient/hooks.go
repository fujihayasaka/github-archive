package httpclient

import (
	"context"
	"net/http"
	"time"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/statter"
)

// ClientHooks are entry points to the request as it goes through its journey. It's primary use case is
// to emit telemetry without cluttering the primary logic, which has the added benefit of creating a
// single, auditable place showing our systems telemetry patterns.
type ClientHooks struct {

	// OnBeginRequestRPC should be called once at the very beginning of the client request method.
	OnBeginRPC func(ctx context.Context, svcname, pkgname, opname string) *HookContext

	// OnBeginCacheGet
	OnBeginCacheGet func(ctx context.Context, hc *HookContext)

	// OnEndCacheGet
	OnEndCacheGet func(ctx context.Context, hc *HookContext)

	// OnBeginCacheSet
	OnBeginCacheSet func(ctx context.Context, hc *HookContext)

	// OnEndCacheSet
	OnEndCacheSet func(ctx context.Context, hc *HookContext)

	// OnStartPerformRequest is called at the beginning of every request, specifically before the request
	// is built.
	OnStartPerformRequest func(ctx context.Context, attempt int, req *http.Request, hc *HookContext)

	// OnDonePerformRequest is called once a result is recieved. It is only concerned with the returned
	// error.
	OnDonePerformRequest func(ctx context.Context, err error, hc *HookContext)

	// OnStartHandleResponse is called after the request phase and before the response is processed in
	// any way. We do not expect the response to be nil at this point, since no error was returned if
	// our request has made it this far.
	OnStartHandleResponse func(ctx context.Context, resp *http.Response, hc *HookContext)

	// OnDoneHandleResponse is called after the response handling has completed, or an error was encountered
	// during the response handling.
	OnDoneHandleResponse func(ctx context.Context, hc *HookContext)

	// OnEndRPC is the last hook that's called. It should represent the final outcome of the RPC call.
	OnEndRPC func(ctx context.Context, res *HookContext)
}

// NewClientHooks returns client hooks and ensures that any uninitialized hook functions are populated
// with a default. This is used to avoid nil reference errors at runtime.
func NewClientHooks() *ClientHooks {
	h := &ClientHooks{}
	h.ensureDefaults()
	return h
}

// Make sure our hooks do something, even if its nothing, it's better than nil.
//
//nolint:revive
func (ch *ClientHooks) ensureDefaults() {
	if ch.OnBeginRPC == nil {
		ch.OnBeginRPC = func(ctx context.Context, svcname, pkgname, opname string) *HookContext { return &HookContext{} }
	}

	if ch.OnBeginCacheGet == nil {
		ch.OnBeginCacheGet = func(ctx context.Context, hc *HookContext) {}
	}

	if ch.OnEndCacheGet == nil {
		ch.OnEndCacheGet = func(ctx context.Context, hc *HookContext) {}
	}

	if ch.OnBeginCacheSet == nil {
		ch.OnBeginCacheSet = func(ctx context.Context, hc *HookContext) {}
	}

	if ch.OnEndCacheSet == nil {
		ch.OnEndCacheSet = func(ctx context.Context, hc *HookContext) {}
	}

	if ch.OnStartPerformRequest == nil {
		ch.OnStartPerformRequest = func(ctx context.Context, attempt int, req *http.Request, hc *HookContext) {}
	}
	if ch.OnDonePerformRequest == nil {
		ch.OnDonePerformRequest = func(ctx context.Context, err error, hc *HookContext) {}
	}
	if ch.OnStartHandleResponse == nil {
		ch.OnStartHandleResponse = func(ctx context.Context, resp *http.Response, hc *HookContext) {}
	}
	if ch.OnDoneHandleResponse == nil {
		ch.OnDoneHandleResponse = func(ctx context.Context, hc *HookContext) {}
	}
	if ch.OnEndRPC == nil {
		ch.OnEndRPC = func(ctx context.Context, res *HookContext) {}
	}
}

// HookContext represents various pieces of request scoped metadata. Someday, it may actually live in a context.Context
// but for now it dutifully carries interesting data about our request to our hooks by passing it through the functions
// and methods involved in the requests lifecycle.
type HookContext struct {
	Service, Package, Operation string
	Tags                        statter.Tags
	Fields                      []kvp.Field
	RPCStartTime                time.Time
	ReqStartTime                time.Time
	RespStartTime               time.Time
	CacheGetStart               time.Time
	CacheSetStart               time.Time

	CacheGetHit bool
	CacheGetErr error

	CacheSetHit bool
	CacheSetErr error

	Error   error
	Attempt int
}
