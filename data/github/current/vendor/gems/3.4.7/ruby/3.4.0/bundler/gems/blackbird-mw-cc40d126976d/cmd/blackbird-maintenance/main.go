package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"syscall"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"

	"github.com/github/blackbird-mw/internal/env"
	"github.com/github/blackbird-mw/internal/server"
	"github.com/github/blackbird-mw/internal/utils"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	conf := env.New(ctx)
	defer conf.Close()
	defer utils.PanicLogger(ctx)

	logging.Info(ctx, fmt.Sprintf("%s starting up", conf.App()),
		kvp.String("cfg", fmt.Sprintf("%+v", conf)),
		kvp.Int("go_max_procs", runtime.GOMAXPROCS(-1)),
	)

	// initialize web server (contains k8s probes and pprof)
	webServer := server.New(conf)
	go func() {
		defer utils.PanicLogger(ctx)

		logging.Info(ctx, "starting web server", kvp.Int("port", conf.GetHTTPPort()))
		if err := webServer.ListenAndServe(); err != nil {
			if err == http.ErrServerClosed {
				logging.Info(ctx, "web server has shutdown", kvp.Err(err))
			} else {
				logging.Error(ctx, "web server exited with error", kvp.Err(err))
			}
		}
	}()

	defer func() {
		defer utils.PanicLogger(ctx)

		// Do this in a deferred so that k8s probes stay alive until shutdown
		if err := webServer.Shutdown(ctx); err != nil && err != context.Canceled {
			logging.Error(ctx, "error during server shutdown", kvp.Err(err))
		}
	}()

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
	}()

	maint := conf.DatabaseMaintenance()
	dbReportTicker := time.NewTicker(5 * time.Minute)
	defer dbReportTicker.Stop()
	go func() {
		defer utils.PanicLogger(ctx)
		defer cancel()

		for {
			maint.Report(ctx)

			select {
			case <-ctx.Done():
				logging.Info(ctx, "context canceled, exiting reporting loop", kvp.Err(ctx.Err()))
				return
			case <-dbReportTicker.C:
				// ready for next run
			}
		}
	}()

	gcTicker := time.NewTicker(1 * time.Hour)
	defer gcTicker.Stop()
	for {
		if err := maint.GC(ctx); err != nil {
			fatal(ctx, "could not run database GC", err)
		}

		select {
		case <-ctx.Done():
			logging.Info(ctx, "context canceled, exiting GC loop", kvp.Err(ctx.Err()))
			return
		case <-gcTicker.C:
			// ready for next run
		}
	}
}

func fatal(ctx context.Context, msg string, err error) {
	logging.Error(ctx, msg, kvp.Err(err))
	log.Fatalf("%s: %+v\n", msg, err)
}
