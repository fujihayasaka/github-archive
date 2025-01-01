// appcontext provides methods that work on our app contexts, which store data
// via .Value, some of which are themselves key/value objects:
// - RequestMetadata
// - gRPC metadata
package appcontext

import (
	"context"
	"net/http"
	"time"

	"github.com/github/go-ctxutil"
	"github.com/github/go-kvp"
	"github.com/github/go-reqmeta"
	"github.com/pkg/errors"
	"github.com/streadway/simpleuuid"

	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/mu/muhttp/mw"
	mureqmeta "github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/utils/requestid"
)

// Fork copies all of source's appcontext data across, shallow copying all mutable fields. Therefore
// changes to its RMD does not affect the parent's RMD (e.g additional log fields added to either
// context after this method is called will not appear in each others' log output)
func Fork(parent context.Context) context.Context {
	ctx := ctxutil.DetachedCancel(parent)
	// Tired: copy the request metadata
	ctx = context.WithValue(ctx, mureqmeta.RMDContextKey, copyOrCreateRMD(parent))

	// Wired: copy the go-reqmeta
	ctx = reqmeta.WithRequestMetadata(ctx, copyOrCreateReqMeta(parent))

	return EnsureRequestID(ctx)
}

// CopyRequestMetadata is used to prevent changes to RMD in returned context
// affecting source. All other values already on the context will remain
// (e.g. azpcorrelation, plus whatever else is there)
func CopyRequestMetadata(ctx context.Context) context.Context {
	// Tired: copy the request metadata
	ctx = context.WithValue(ctx, mureqmeta.RMDContextKey, copyOrCreateRMD(ctx))

	// Wired: copy the go-reqmeta
	return reqmeta.WithRequestMetadata(ctx, copyOrCreateReqMeta(ctx))
}

// Apply a set of string tags to both stats and logs
func LogsAndStatsWith(ctx context.Context, tags mureqmeta.Tags) {
	if rmd := mw.GetRequestMetadata(ctx); rmd != nil {
		rmd.TagStatsWith(tags)
		fields := make([]kvp.Field, 0, len(tags))
		for k, v := range tags {
			fields = append(fields, kvp.String(k, v))
		}
		rmd.LogWith(fields...)
	}
}

// Initialize will setup ctx with RequestMetadata and log fields
// in the same way mu does for incoming requests. Use for contexts where we're
// initiating an action not in response to a request (e.g scheduled tasks)
func Initialize(ctx context.Context, m ApplicationMetadata) (context.Context, error) {
	// Generate a 'request ID' (since we have no incoming request, we need something equivalent,
	// important as it's used for E2E headers in Azure requests etc).
	requestID, err := generateRequestID()
	if err != nil {
		return nil, err
	}

	return InitializeWithRequestID(ctx, m, requestID)
}

// InitializeWithoutRequestID does the main setup of RMD, except for request_id
func InitializeWithoutRequestID(ctx context.Context, m ApplicationMetadata) context.Context {
	// Tired: Give us something to attach log fields to
	rmd := mureqmeta.NewRequestMetadata()
	ctx = context.WithValue(ctx, mureqmeta.RMDContextKey, rmd)
	fields := []kvp.Field{
		kvp.String("app", "launch"),
		kvp.String("sha", m.BuildVersion),
		kvp.String("mu", m.MuVersion),
		kvp.String("host", mu.AppHost()),
	}
	// initialize logging/stats in same way as mu does for requests
	ctx = ctxstash.WithFields(ctx, MapToLogFields(m.ObservabilityFields)...)
	ctx = ctxstash.WithFields(ctx, fields...)
	mw.TagStatsWith(ctx, m.ObservabilityFields)

	// Wired: Give us something better to attach log fields to
	ctx = reqmeta.WithRequestMetadata(ctx, reqmeta.NewRequestMetadata())

	return ctx
}

// InitializeWithRequestID does the work for Initialize but with the passed in RequestID
func InitializeWithRequestID(ctx context.Context, m ApplicationMetadata, requestID string) (context.Context, error) {
	ctx = InitializeWithoutRequestID(ctx, m)
	ctx = SetRequestID(ctx, requestID)
	return ctx, nil
}

// SetRequestID sets the requestID on context, and in the logging KVP
func SetRequestID(ctx context.Context, requestID string) context.Context {
	ctx = context.WithValue(ctx, mw.RequestIDKey, requestID)
	ctx = requestid.ForwardRequestIDToTwirp(ctx)
	return ctxstash.WithReqID(ctx, requestID)
}

// EnsureRequestID ensures that a request ID is set in the KVPs and
// in the `ctx`, if none exists. If one exists, it is used.
func EnsureRequestID(ctx context.Context) context.Context {
	kvReqID := ctxstash.From(ctx).Correlations().GitHub.RequestID
	kvsHaveReqID := kvReqID != ""
	ctxReqID, ctxHasReqID := ctx.Value(mw.RequestIDKey).(string)
	if kvReqID != "" && ctxReqID != "" && kvReqID == ctxReqID {
		return ctx
	}

	switch {
	case kvsHaveReqID && !ctxHasReqID:
		if kvReqID != "" {
			return SetRequestID(ctx, kvReqID)
		}
	case !kvsHaveReqID && ctxHasReqID:
		if ctxReqID != "" {
			return SetRequestID(ctx, ctxReqID)
		}
	case ctxReqID != "" && kvReqID == "":
		return SetRequestID(ctx, ctxReqID)
	case ctxReqID == "" && kvReqID != "":
		return SetRequestID(ctx, kvReqID)
	}

	// either both are empty, or they don't match...
	if ctxReqID != kvReqID {
		return SetRequestID(ctx, ctxReqID) // ctx wins in a mismatch
	}
	requestID, err := generateRequestID()
	if err != nil {
		// this will only fail if `/dev/urandom` is broken, and we shouldn't be here if that's the case
		panic(err)
	}
	return SetRequestID(ctx, requestID)
}

func MapToLogFields(m map[string]string) []kvp.Field {
	fields := make([]kvp.Field, 0, len(m))
	for key, value := range m {
		fields = append(fields, kvp.String(key, value))
	}
	return fields
}

type ApplicationMetadata struct {
	ServiceName         string
	Environment         launchconfig.AppEnv
	BuildVersion        string
	MuVersion           string
	ObservabilityFields map[string]string
}

func SetupServiceContext(req *http.Request) {
	ctx := requestid.ForwardRequestIDToTwirp(req.Context())

	// Give us something better to attach log fields to (mu does the kvp.RMD in this case)
	ctx = reqmeta.WithRequestMetadata(ctx, reqmeta.NewRequestMetadata())

	*req = *req.WithContext(ctx)
}

func copyOrCreateRMD(source context.Context) *mureqmeta.RequestMetadata {
	if rmd := mw.GetRequestMetadata(source); rmd != nil {
		return rmd.Copy()
	}
	return mureqmeta.NewRequestMetadata()
}

func copyOrCreateReqMeta(source context.Context) *reqmeta.RequestMetadata {
	if rmeta, ok := reqmeta.GetRequestMetadata(source); ok {
		return rmeta.Copy()
	}
	return reqmeta.NewRequestMetadata()
}

func generateRequestID() (string, error) {
	uuid, err := simpleuuid.NewTime(time.Now())
	if err != nil {
		return "", errors.Wrap(err, "failed to generate UUID to use as request ID")
	}

	return uuid.String(), nil
}
