package main

import (
	"context"
	"fmt"
	"net/http"

	"github.com/github/go-http/middleware/hmac"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/otel-instrumentation-go/oteltwirp"

	"github.com/github/launch/pkg/mu"

	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/launchserver"
)

// TwirpServer is the interface for a generated Twirp server. We redefine the
// interface here because all of the other interfaces are included within
// auto-generated code.
type TwirpServer interface {
	http.Handler
	// ServiceDescriptor returns gzipped bytes describing the .proto file that
	// this service was generated from. Once unzipped, the bytes can be
	// unmarshalled as a
	// github.com/golang/protobuf/protoc-gen-go/descriptor.FileDescriptorProto.
	//
	// The returned integer is the index of this particular service within that
	// FileDescriptorProto's 'Service' slice of ServiceDescriptorProtos. This is a
	// low-level field, expected to be used for reflection.
	ServiceDescriptor() ([]byte, int)
	// ProtocGenTwirpVersion is the semantic version string of the version of
	// twirp used to generate this file.
	ProtocGenTwirpVersion() string
	// PathPrefix returns the HTTP URL path prefix for all methods handled by this
	// service. This can be used with an HTTP mux to route twirp requests
	// alongside non-twirp requests on one HTTP listener.
	PathPrefix() string
}

func registerTwirpService(
	ctx context.Context,
	obs *observability.Observability,
	svc *mu.Service,
	twirpSrv TwirpServer,
	serviceName string,
) {
	ctxStashHandler := launchserver.SetupCtxStashMiddleware(&launchserver.CtxStashConfig{
		Name:         svc.Name,
		BuildVersion: svc.Config.BuildVersion,
		Host:         mu.AppHost(),
		StatsTags:    stats.Tags(svc.Config.StatsTags),
	})

	panicHandler := launchserver.RecoverPanics(obs)
	tenantHandler := launchserver.SetupGitHubTenantMiddleware(launchconfig.IsMultiTenant(), obs)

	svc.PrimaryMux.Method(
		http.MethodPost,
		twirpSrv.PathPrefix()+"*",
		panicHandler(oteltwirp.Middleware((tenantHandler(ctxStashHandler(hmac.Handler(twirpSrv)))))),
	)

	registerMsg := fmt.Sprintf("registered twirp for %s", serviceName)
	obs.Logger.Debug(ctx, registerMsg, kvp.String("gh.launch.component", "twirp"))
}
