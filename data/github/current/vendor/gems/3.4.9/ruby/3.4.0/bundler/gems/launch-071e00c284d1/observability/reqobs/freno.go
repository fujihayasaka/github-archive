package reqobs

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/github/go-kvp"

	"github.com/github/launch/clients/freno"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
)

func FrenoHooks(obs *observability.Observability) *freno.ClientHooks {
	return &freno.ClientHooks{
		OnBeginRPC: func(ctx context.Context, pkgname, svcname, app, dbtype, cluster string) *freno.HookContext {
			opname := fmt.Sprintf("%s.%s.%s", app, dbtype, cluster)
			tags := buildOnBeginRPCTags("rest", svcname, pkgname, opname)
			emitOnAttemptCounter(ctx, obs.Statter, tags)
			return &freno.HookContext{
				Tags:         tags,
				RPCStartTime: time.Now(),
				Service:      svcname,
				Package:      pkgname,
				Operation:    app,
				DBType:       dbtype,
				Cluster:      cluster,
			}
		},

		OnEndRPC: func(ctx context.Context, hc *freno.HookContext, res *freno.CheckResponse) {
			if res == nil || *res == (freno.CheckResponse{}) {
				obs.Debug(ctx, "No freno request, or response not unmarshaled", kvp.String("gh.freno.cluster.name", hc.Cluster))
				return
			}

			// Existing metrics:
			obs.Distribution(ctx, "freno_lag_ms", statter.Tags{
				"freno_cluster":   hc.Cluster,
				"freno_can_write": strconv.FormatBool(res.CanWrite)},
				float64(res.ReplicationLag.Milliseconds()),
			)
			obs.Debug(ctx, "freno response",
				kvp.String("gh.freno.cluster.name", hc.Cluster),
				kvp.Bool("gh.freno.can_write", res.CanWrite),
				kvp.Int("gh.freno.status_code", res.StatusCode),
				kvp.Duration("gh.freno.lag_seconds", res.ReplicationLag),
				kvp.Duration("gh.freno.threshold_seconds", res.Threshold),
				kvp.String("gh.freno.message", res.Message))

			// New metrics:
			hc.Tags = hc.Tags.Merge(statter.Tags{AttemptStatusCodeMetricTag: strconv.Itoa(res.StatusCode)})

			// 200 is the only status code that indicates we should write, so lets consider everything else an error response.
			// See https://github.com/github/freno/blob/master/doc/http.md
			errored := res.StatusCode != http.StatusOK

			emitOnEndRPC(ctx, obs.Statter, time.Since(hc.RPCStartTime), hc.Tags, errored)
		},
	}
}
