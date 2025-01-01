package reqobs

import (
	"context"
	"strconv"
	"time"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchhttp/httpclient"
)

func logOutgoingRequest(ctx context.Context, obs *observability.Observability, hc *httpclient.HookContext) {
	fields := []kvp.Field{
		kvp.Duration("http.request.elapsed_seconds", time.Since(hc.ReqStartTime)),
		kvp.String("http.request.resend_count", strconv.Itoa(hc.Attempt)),
		kvp.String("gh.launch.service.name", hc.Service),
		kvp.String("gh.launch.package.name", hc.Package),
	}

	if hc.Error != nil {
		fields = append(fields, kvp.Err(hc.Error))
		obs.Error(ctx, "rpc.outgoing", append(hc.Fields, fields...)...)
	} else {
		obs.Log(ctx, "rpc.outgoing", append(hc.Fields, fields...)...)
	}
}
