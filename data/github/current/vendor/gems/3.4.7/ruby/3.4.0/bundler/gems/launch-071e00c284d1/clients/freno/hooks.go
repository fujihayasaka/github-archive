package freno

import (
	"context"
	"time"

	"github.com/github/launch/observability/statter"
)

type ClientHooks struct {
	OnBeginRPC func(ctx context.Context, pkg, svc, method, dbtype, cluster string) *HookContext
	OnEndRPC   func(ctx context.Context, hc *HookContext, res *CheckResponse)
}

func (ch *ClientHooks) ensureDefaults() {
	if ch.OnBeginRPC == nil {
		ch.OnBeginRPC = func(ctx context.Context, pkg, svc, method, dbtype, cluster string) *HookContext {
			return &HookContext{}
		}
	}
	if ch.OnEndRPC == nil {
		ch.OnEndRPC = func(ctx context.Context, hc *HookContext, res *CheckResponse) {}
	}
}

// HookContext represents various pieces of request scoped metadata. Someday, it may actually live in a context.Context
// but for now it dutifully carries interesting data about our request to our hooks by passing it through the functions
// and methods involved in the requests lifecycle.
type HookContext struct {
	Service, Package, Operation, DBType, Cluster string
	Tags                                         statter.Tags
	RPCStartTime                                 time.Time
}
