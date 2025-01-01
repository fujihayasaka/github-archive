package reqobs

import (
	"context"
	"time"

	"github.com/github/launch/observability/statter"
)

// Well known metric keys:
const (
	// RPCStartedMetricKey is called at the start of every rpc request
	RPCStartedMetricKey = "rpc.started"
	// AttemptDurationMetricKey measures the time spent on any individual request attempt.
	// Each RPC request has at least one attempt.
	AttemptDurationMetricKey = "rpc.attempt.duration_ms"
	// RPCDurationMetrikKey measures the time spent on any all request attempts.
	RPCDurationMetricKey = "rpc.duration_ms"
	// RPCErroredMetricKey is incremented whenever an RPC call ends in error
	RPCErroredMetricKey = "rpc.errored"
	// rpcErrored is incremented whenever an RPC call finishes
	RPCFinishedMetricKey = "rpc.finished"
)

// Well known metric tags:
const (
	// RPCTypeMetricTag is the type of protocol the client is using. Current values
	// are twirp, graphQL, or rest.
	RPCTypeMetricTag = "type"
	// RPCPackageMetricTag is the tag key whose value is the package that the RPC belongs. Packages have many services.
	RPCPackageMetricTag = "pkg"
	// RPCServiceMetricTag is the tag key whose value is the package that the RPC belongs. Services belong to one package.
	RPCServiceMetricTag = "svc"
	// MethodMetricTag is the tag key whose value is the method or operation name
	// associated with the RPC.
	MethodMetricTag = "method"
	// AttemptStatusCodeMetricTag is the HTTP result code associated with the attempt execution or RPC call.
	AttemptStatusCodeMetricTag = "status_code"
	// AttemptErrorCodeMetricTag is the low-cardinality error category associated with the attempt execution or RPC call.
	AttemptErrorCodeMetricTag = "error_code"
	// AttemptErrorMetricTag is the tag that specifies if the attempt or RPC finished in an error state.
	AttemptErrorMetricTag = "error"
)

func buildOnBeginRPCTags(rtype, svcname, pkgname, opname string) statter.Tags {
	return statter.Tags{
		RPCTypeMetricTag:    rtype,
		RPCPackageMetricTag: pkgname,
		RPCServiceMetricTag: svcname,
		MethodMetricTag:     opname,
	}
}

func emitOnAttemptCounter(ctx context.Context, statter statter.Statter, tags statter.Tags) {
	statter.Counter(ctx, RPCStartedMetricKey, tags, 1)
}

func emitOnDonePerformRequest(ctx context.Context, statter statter.Statter, duration time.Duration, err error, tags statter.Tags) {
	if err != nil {
		statter.Distribution(ctx, AttemptDurationMetricKey, tags, float64(duration.Milliseconds()))
	}
}

func emitOnDoneHandleResponse(ctx context.Context, statter statter.Statter, duration time.Duration, tags statter.Tags) {
	statter.Distribution(ctx, AttemptDurationMetricKey, tags, float64(duration.Milliseconds()))
}

func emitOnEndRPC(ctx context.Context, statter statter.Statter, duration time.Duration, tags statter.Tags, errored bool) {
	statter.Distribution(ctx, RPCDurationMetricKey, tags, float64(duration.Milliseconds()))
	if errored {
		statter.Counter(ctx, RPCErroredMetricKey, tags, 1)
	}
	statter.Counter(ctx, RPCFinishedMetricKey, tags, 1)
}
