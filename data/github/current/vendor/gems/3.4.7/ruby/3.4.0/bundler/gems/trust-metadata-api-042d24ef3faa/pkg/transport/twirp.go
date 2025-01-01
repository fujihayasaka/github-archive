package transport

import (
	"context"
	"fmt"
	"net/http"

	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/trust-metadata-api/pkg/hydro"

	"github.com/github/github-telemetry-go/log"

	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/twitchtv/twirp"
)

// TwirpService is a wrapper for individual TwirpServers emitted from the Twirp
// code auto-generated from protobufs. A TwirpService's purpose in life is
// two-fold:
// 1. Encapsulate the logic for building the twirp.ServerHook chains and
// http.Handler middleware that enforces authentication via HMAC, and
// 2. Expose the PathPrefix() for easy mounting in a http multiplexer
type TwirpService struct {
	Handler      http.Handler
	PathPrefix   string
	hooks        *twirp.ServerHooks
	interceptors twirp.Interceptor
	tma          service.TMAService
	log          log.Logger
	reporter     *exceptions.Reporter
	metrics      stats.Client
	hydroClient  *hydro.Client
}

// TwirpServiceOption is a functional option for configuring the TwirpService
type TwirpServiceOption func(*TwirpService)

// TwirpWithLogger sets the logger for the TwirpService.
func TwirpWithLogger(logger log.Logger) TwirpServiceOption {
	return func(s *TwirpService) {
		s.log = logger
	}
}

// TwirpWithMetrics sets the stats client for the TwirpService.
func TwirpWithMetrics(metrics stats.Client) TwirpServiceOption {
	return func(s *TwirpService) {
		s.metrics = metrics
	}
}

// TwirpWithErrorReporter sets the error reporter for the TwirpService.
func TwirpWithErrorReporter(reporter *exceptions.Reporter) TwirpServiceOption {
	return func(s *TwirpService) {
		s.reporter = reporter
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

	twirpService := &TwirpService{tma: tma, log: logger}

	// eval functional options
	for _, opt := range opts {
		opt(twirpService)
	}

	twirpService.hooks = twirp.ChainHooks(
		twhooks.DefaultHooks(),
		twstats.DefaultHooks(twirpService.metrics),
		errorHooks(twirpService.log, twirpService.reporter),
	)
	twirpService.interceptors = twirp.ChainInterceptors(
		translateServiceErrorInterceptor())

	return twirpService, nil
}

// Status returns the status message for the service
func (ts *TwirpService) Status(context.Context, *rpc.StatusRequest) (*rpc.StatusResponse, error) {
	return &rpc.StatusResponse{State: "OK", Commit: ts.tma.GetGitCommit()}, nil
}
