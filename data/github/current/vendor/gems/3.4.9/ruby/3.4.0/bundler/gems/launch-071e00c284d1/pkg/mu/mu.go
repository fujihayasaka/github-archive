package mu

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/github/go-kvp"

	"github.com/github/launch/pkg/mu/shutdown"
)

// Run is the entry point of a mu service
func Run(cfg *Config) {
	cmdline := flag.NewFlagSet(os.Args[0], flag.ContinueOnError)
	shutdownPID := cmdline.Int("shutdown", 0, "pid to shutdown")
	if err := cmdline.Parse(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "error parsing command line: %s\n", err) // nolint: errcheck, gosec
		os.Exit(1)
	}

	if *shutdownPID > 0 {
		_ = shutdown.Wait(*shutdownPID, cfg.ShutdownSocket) // nolint: gosec
		os.Exit(0)
	}

	service, err := New(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error building application: %s\n", err) // nolint: errcheck, gosec
		os.Exit(1)
	}

	log := service.Logger()

	ctx, ctxShutdown := context.WithCancel(context.Background())
	configureShutdownSignal(func(signal os.Signal) {
		log.Log(ctx, "Received shutdown signal", kvp.Any("process.signal", signal))
		ctxShutdown()
	}, syscall.SIGTERM, syscall.SIGINT)

	// Run the HTTP server and gRPC server (if configured)
	exitCode := 0
	err = service.Run(ctx)
	if err != nil {
		log.Report(ctx, err)
		exitCode = 1
	}

	// Begin shutdown procedure
	_ = shutdown.Signal(cfg.ShutdownSocket) // nolint: gosec
	log.Log(ctx, "shutdown complete")

	if exitCode != 0 {
		os.Exit(exitCode)
	}
}

// AppHost will return os.Hostname or unknown if there is an error.
func AppHost() string {
	if appHost, err := os.Hostname(); err == nil {
		return appHost
	}
	return "unknown"
}

func configureShutdownSignal(shutdown func(os.Signal), sigs ...os.Signal) {
	signalCh := make(chan os.Signal, 1)

	signal.Notify(signalCh, sigs...)
	go func() {
		signalReceived := <-signalCh
		shutdown(signalReceived)
	}()
}
