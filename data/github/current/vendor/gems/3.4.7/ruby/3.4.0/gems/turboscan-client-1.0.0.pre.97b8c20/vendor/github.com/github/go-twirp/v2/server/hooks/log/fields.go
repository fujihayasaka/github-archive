// Package log provides Twirp hooks for logging.
package log

import (
	"context"

	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-reqmeta/v2"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-twirp/v2/server"
	"github.com/twitchtv/twirp"
)

// FieldsFunc is a function that can generate a slice of kvp.Fields based on a context.Context.
type FieldsFunc func(ctx context.Context) []kvp.Field

func genFields(ctx context.Context, ffs []FieldsFunc) (fields []kvp.Field) {
	for _, fieldFn := range ffs {
		fields = append(fields, fieldFn(ctx)...)
	}
	return fields
}

// DefaultFields are the set of fields that are recommended to be recorded with any Twirp related
// log messages.
func DefaultFields(ctx context.Context) (fields []kvp.Field) {
	fields = append(fields, kvp.String("component", "twirp"))

	if sc, ok := twirp.StatusCode(ctx); ok {
		fields = append(fields, kvp.String(server.StatusCodeLabel, sc))
	}

	if mthd, ok := twirp.MethodName(ctx); ok {
		fields = append(fields, kvp.String(server.MethodNameLabel, mthd))
	}

	if svc, ok := twirp.ServiceName(ctx); ok {
		fields = append(fields, kvp.String(server.ServiceNameLabel, svc))
	}

	if pkg, ok := twirp.PackageName(ctx); ok {
		fields = append(fields, kvp.String(server.PackageNameLabel, pkg))
	}

	if rm, ok := reqmeta.GetRequestMetadata(ctx); ok {
		fields = append(fields, rm.LogFields()...)
	}

	fields = append(fields, kvp.String(requestid.GitHubRequestIDLabel, requestid.GetGitHubRequestID(ctx)))

	return fields
}
