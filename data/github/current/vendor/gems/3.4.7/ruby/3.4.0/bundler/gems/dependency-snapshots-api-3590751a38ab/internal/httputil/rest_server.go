package httputil

import (
	"context"
	"fmt"
	"net/http"
	"net/http/pprof"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-http/v2/middleware/recovery"
	"github.com/github/otel-instrumentation-go/oteltwirp"

	"github.com/pkg/errors"
)

// ApplyRestHandlers registers the non-Twirp endpoints to an HTTP server mux.
func ApplyRestHandlers(mux *http.ServeMux, reporter *exceptions.Reporter, diagnostic interfaces.DiagnosticService) {
	// Wrap each handler with logging, Open Telemetry, and panic recovery.
	wrap := func(h http.Handler) http.Handler {
		h = panicWrap(h, reporter)
		h = oteltwirp.Middleware(h)
		h = logWrap(h)
		return h
	}

	ping := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, diagnostic.Ping())
	})

	boom := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, err := diagnostic.Boom(true)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	})

	mux.Handle("/_ping", wrap(ping))
	mux.Handle("/boom", wrap(boom))
	applyPprof(mux)
}

func applyPprof(mux *http.ServeMux) {
	mux.HandleFunc("/pprof/", pprof.Index)
	mux.HandleFunc("/pprof/cmdline", pprof.Cmdline)
	mux.HandleFunc("/pprof/profile", pprof.Profile)
	mux.HandleFunc("/pprof/symbol", pprof.Symbol)
	mux.HandleFunc("/pprof/trace", pprof.Trace)

	mux.Handle("/pprof/allocs", pprof.Handler("allocs"))
	mux.Handle("/pprof/threadcreate", pprof.Handler("threadcreate"))
	mux.Handle("/pprof/heap", pprof.Handler("heap"))
	mux.Handle("/pprof/goroutine", pprof.Handler("goroutine"))
	mux.Handle("/pprof/mutex", pprof.Handler("mutex"))
	mux.Handle("/pprof/block", pprof.Handler("block"))
}

func logWrap(h http.Handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Info(fmt.Sprintf("Request to %v", r.URL.Path))
		h.ServeHTTP(w, r)
		log.Info(fmt.Sprintf("End of request to %v", r.URL.Path))
	}
}

func panicWrap(h http.Handler, reporter *exceptions.Reporter) http.Handler {
	// Report panics in the HTTP handler goroutine.
	// Panics in other goroutines will continue to cause unreported process termination.
	rc := recovery.Recovery{
		Report: func(err error, req *http.Request) error {
			_ = reporter.Report(context.Background(), errors.Wrap(err, "HTTP handler PANIC"), map[string]string{
				"http.request.method": req.Method,
				"url.path":            req.URL.String(),
			})
			return nil
		},
		Response: func(err error, rw http.ResponseWriter, r *http.Request) {
			rw.WriteHeader(500)
			fmt.Fprintf(rw, "insert sad robot here")
		},
	}
	return rc.Handler(h)
}
