package transport

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/github/go-stats"
	"github.com/github/trust-metadata-api/pkg/hydro"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	"github.com/github/go-http/v2/middleware/requestid"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/github/trust-metadata-api/pkg/auth"
	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/twitchtv/twirp"
)

// TwirpService is a wrapper for individual TwirpServers emitted from the Twirp
// code auto-generated from protobufs. A TwirpService's purpose in life is
// two-fold:
// 1. Encapsulate the logic for building the twirp.ServerHook chains and
// http.Handler middleware that enforces authentication via HMAC, and
// 2. Expose the PathPrefix() for easy mounting in an http multiplexer
type TwirpService struct {
	Handler     http.Handler
	PathPrefix  string
	hooks       *twirp.ServerHooks
	tma         service.TMAService
	log         log.Logger
	metrics     stats.Client
	hydroClient *hydro.Client
}

// TwirpServiceOption is a functional option for configuring the TwirpService
type TwirpServiceOption func(*TwirpService)

// TwirpWithLogger sets the logger for the TwirpService.
func TwirpWithLogger(logger log.Logger) TwirpServiceOption {
	return func(s *TwirpService) {
		s.log = logger
	}
}

// TwirpWithMetics sets the stats client for the TwirpService.
func TwirpWithMetrics(metrics stats.Client) TwirpServiceOption {
	return func(s *TwirpService) {
		s.metrics = metrics
	}
}

// TwirpWithHydro sets the hydro client for the TwirpService.
func TwirpWithHydro(hydroClient *hydro.Client) TwirpServiceOption {
	return func(s *TwirpService) {
		s.hydroClient = hydroClient
	}
}

// newTwirpService instantiates a TwirpService and configures the adequate set
// of twirp.ServerHooks we want to be applied to our TwirpServers.
func newTwirpService(tma service.TMAService, opts ...TwirpServiceOption) (*TwirpService, error) {
	logger, err := log.NewFromConfig(log.Config{
		LogConsoleEncoding: "logfmt",
		LogLevel:           log.InfoLevel.String(),
	})
	if err != nil {
		return nil, fmt.Errorf("configuring logger: %w", err)
	}

	service := &TwirpService{tma: tma, log: logger}

	// eval functional options
	for _, opt := range opts {
		opt(service)
	}

	service.hooks = twirp.ChainHooks(
		twhooks.DefaultHooks(),
		twstats.DefaultHooks(service.metrics),
	)
	return service, nil
}

// NewTMATwirpService creates and configures a TwirpService that can be mounted
// on a router and dispatch calls for the TMA rpc interface.
func NewTMATwirpService(tma service.TMAService, cfg []auth.ClientConfig, opts ...TwirpServiceOption) (*TwirpService, error) {
	service, err := newTwirpService(tma, opts...)
	if err != nil {
		return nil, fmt.Errorf("setting up twirp service: %w", err)
	}

	server := rpc.NewTrustMetadataAPIServer(service, service.hooks, twirp.WithServerJSONCamelCaseNames(true))
	service.PathPrefix = server.PathPrefix()
	service.Handler = server

	// If authentication is enabled, create the auth middleware and wrap the
	// Twirp server in it. This middleware validates the HMAC of incoming requests
	authMiddleware, err := auth.NewAuthenticationMiddleware(service.log, cfg)
	if err != nil {
		return nil, fmt.Errorf("setting up HMAC auth: %w", err)
	}

	service.Handler = authMiddleware(server)

	return service, nil
}

// Status returns the status message for the service
func (ts *TwirpService) Status(context.Context, *rpc.StatusRequest) (*rpc.StatusResponse, error) {
	return &rpc.StatusResponse{State: "OK", Commit: ts.tma.GetGitCommit()}, nil
}

// This is an endpoint
func (ts *TwirpService) LogErr(ctx context.Context, req *rpc.LogErrRequest) (*rpc.LogErrResponse, error) {
	testErr := service.NewInternalError(errors.New(req.Message))
	_ = ts.logErr(ctx, testErr)
	_ = ts.tma.ReportError(ctx, testErr)
	return &rpc.LogErrResponse{ErrorMessage: req.Message}, nil
}

func (ts *TwirpService) logErr(ctx context.Context, err error) twirp.Error {
	fields := make([]kvp.Field, 0, 3)
	// NOTE: this key is "gh.request_id"
	fields = append(fields, kvp.String(service.GitHubRequestIDLabel, requestid.GetGitHubRequestID(ctx)))

	if npmReqID, ok := ctx.Value(service.NpmCtxKeyName).(string); ok {
		fields = append(fields, kvp.String(service.NpmRequestIDLabel, npmReqID))
	}
	ts.log.Error(err.Error(), fields...)

	return GetTwirpError(err)
}
