package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"runtime/debug"
	"syscall"

	"github.com/github/go-http/middleware/hmac"
	"github.com/github/go-http/middleware/recovery"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/twitchtv/twirp"

	"github.com/github/blackbird-mw/internal/copilot"
	"github.com/github/blackbird-mw/internal/env"
	"github.com/github/blackbird-mw/internal/kube"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/query"
	server_pkg "github.com/github/blackbird-mw/internal/server"
	"github.com/github/blackbird-mw/internal/utils"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cfg := env.New(ctx)
	defer cfg.Close()
	defer utils.PanicLogger(ctx)

	logging.Info(ctx, fmt.Sprintf("%s starting up", cfg.App()),
		kvp.String("cfg", fmt.Sprintf("%+v", cfg)),
		kvp.Int("go_max_procs", runtime.GOMAXPROCS(-1)),
	)

	store := cfg.Store()

	queryService := query.NewService(
		cfg.GetStamp(),
		cfg.IndexerClusters(),
		cfg.SearchClusters(),
		store,
		cfg.PagerCache(),
		cfg.AuthClient(store),
		cfg.QuotaRateEstimator(ctx),
		cfg.GetTreelightsClient(),
		cfg.GitClient(),
	)
	queryServer := pb.NewQueryAPIServer(queryService, cfg.QueryServiceHooks())
	handler := buildHTTPMux(cfg, queryServer)
	server := &http.Server{
		Addr:    fmt.Sprintf(":%d", cfg.GetHTTPPort()),
		Handler: handler,
	}

	debugServer := server_pkg.NewDebug(cfg)

	// Wait on OS signals and allow graceful shutdown.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		defer utils.PanicLogger(ctx)
		defer close(stop)
		defer cancel()

		// Received stop signal (SIGINT/SIGTERM)
		<-stop
		logging.Info(ctx, "received shutdown signal, exiting")
		err := debugServer.Shutdown(ctx)
		if err != nil {
			logging.Error(ctx, "debugServer.Shutdown failed", kvp.Err(err))
		}
		err = server.Shutdown(ctx) // Do this last so that k8s probes stay alive
		if err != nil {
			logging.Error(ctx, "server.Shutdown failed", kvp.Err(err))
		}
	}()

	go func() {
		logging.Info(ctx, "starting debug web server", kvp.Int("port", cfg.GetDebugHTTPPort()))
		if err := debugServer.ListenAndServe(); err != nil {
			if err == http.ErrServerClosed {
				logging.Info(ctx, "debug server has shutdown", kvp.Err(err))
			} else {
				logging.Error(ctx, "debug server exited with error", kvp.Err(err))
			}
		}
	}()

	logging.Info(ctx, "starting query web server", kvp.Int("port", cfg.GetHTTPPort()))
	if err := server.ListenAndServe(); err != nil {
		if err == http.ErrServerClosed {
			logging.Info(ctx, "query server has shutdown", kvp.Err(err))
		} else {
			logging.Error(ctx, "query server exited with error", kvp.Err(err))
		}
	}

	logging.Info(ctx, "exiting...")
}

func buildHTTPMux(cfg env.Config, queryServer pb.TwirpServer) http.Handler {
	mux := chi.NewRouter()
	mux.Use(requestid.Handler)
	mux.Use(copilot.LicenseHandler) // Add copilot license (if any) to context
	rec := recovery.Recovery{
		Report: func(err error, req *http.Request) error {
			logging.Error(req.Context(), "unhandled panic occurred", kvp.Err(err),
				kvp.String("path", req.URL.Path),
				kvp.String("stack", string(debug.Stack())))
			statting.Counter(req.Context(), "panic_count", 1, stats.Tags{"path": req.URL.Path})

			return twirp.InternalError("internal server error")
		},
	}

	mux.Mount(queryServer.PathPrefix(), rec.Handler(hmac.Handler(queryServer)))
	mux.Mount("/debug", middleware.Profiler())
	mux.HandleFunc("/ready", kube.Ready(cfg))

	return mux
}
