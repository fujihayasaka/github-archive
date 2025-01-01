package health

import (
	"context"
	"expvar"
	"fmt"
	"net/http"
	"net/http/pprof"
	"time"

	"github.com/github/launch/observability"
)

// Config denotes configuration required for the health http service
type Config struct {
	Version string
	Address string
}

// Health service responds to ping and various debug endpoints
type Health struct {
	obs     *observability.Observability
	version string
	*http.Server
}

// New returns an http service with a _ping and various _debug endpoints
func New(cfg Config, obs *observability.Observability) (*Health, error) {
	h := &Health{
		version: cfg.Version,
		obs:     obs,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/_ping", h.ping)
	mux.HandleFunc("/_debug/vars", expvar.Handler().ServeHTTP)
	mux.HandleFunc("/_debug/pprof", pprof.Index)
	mux.HandleFunc("/_debug/pprof/heap", pprof.Handler("heap").ServeHTTP)
	mux.HandleFunc("/_debug/pprof/cmdline", pprof.Cmdline)
	mux.HandleFunc("/_debug/pprof/mutex", pprof.Handler("mutex").ServeHTTP)
	mux.HandleFunc("/_debug/pprof/block", pprof.Handler("block").ServeHTTP)
	mux.HandleFunc("/_debug/pprof/threadcreate", pprof.Handler("threadcreate").ServeHTTP)
	mux.HandleFunc("/_debug/pprof/profile", pprof.Profile)
	mux.HandleFunc("/_debug/pprof/symbol", pprof.Symbol)
	mux.HandleFunc("/_debug/pprof/trace", pprof.Trace)
	mux.HandleFunc("/_debug/pprof/goroutine", pprof.Handler("goroutine").ServeHTTP)

	h.Server = &http.Server{
		Addr:         cfg.Address,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 1 * time.Minute,
		Handler:      mux,
	}

	return h, nil
}

// Run starts the server
func (h *Health) Run(ctx context.Context) error {
	h.obs.Log(ctx, fmt.Sprintf("Health service starting at %s", h.Addr))
	if err := h.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		return err
	}
	return nil
}

func (h *Health) ping(w http.ResponseWriter, _ *http.Request) {
	fmt.Fprintf(w, "OK - %s - %s\n", // nolint: errcheck, gosec
		h.version,
		time.Now().UTC())
}
