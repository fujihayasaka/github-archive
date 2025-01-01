package transport

import (
	"fmt"
	"net/http"

	"github.com/github/go-stats"

	"github.com/github/github-telemetry-go/log"

	"github.com/github/attester/pkg/service"
	"github.com/github/go-exceptions"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/twitchtv/twirp"
)

// TwirpService is a wrapper for individual TwirpServers emitted from the Twirp
// code auto-generated from protobufs. A TwirpService's purpose in life is
// two-fold:
// 1. Encapsulate the logic for building the twirp.ServerHook chains and
// http.Handler middleware that enforces authentication via HMAC, and
// 2. Expose the PathPrefix() for easy mounting in an http multiplexer
type TwirpService struct {
	Handler      http.Handler
	PathPrefix   string
	hooks        *twirp.ServerHooks
	interceptors twirp.Interceptor
	service      service.Service
	log          log.Logger
	metrics      stats.Client
	reporter     *exceptions.Reporter
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

// TwirpWithErrorReporter sets the error reporter for the TwirpService.
func TwirpWithErrorReporter(reporter *exceptions.Reporter) TwirpServiceOption {
	return func(s *TwirpService) {
		s.reporter = reporter
	}
}

// newTwirpService instantiates a TwirpService and configures the adequate set
// of twirp.ServerHooks we want to be applied to our TwirpServers.
func newTwirpService(s service.Service, opts ...TwirpServiceOption) (*TwirpService, error) {
	logger, err := log.NewFromConfig(log.Config{
		LogConsoleEncoding: "logfmt",
		LogLevel:           log.InfoLevel.String(),
	})
	if err != nil {
		return nil, fmt.Errorf("configuring logger: %w", err)
	}

	service := &TwirpService{service: s, log: logger}

	// eval functional options
	for _, opt := range opts {
		opt(service)
	}

	service.hooks = twirp.ChainHooks(
		twhooks.DefaultHooks(),
		twstats.DefaultHooks(service.metrics),
	)
	service.interceptors = twirp.ChainInterceptors(
		translateServiceErrorInterceptor())
	return service, nil
}
