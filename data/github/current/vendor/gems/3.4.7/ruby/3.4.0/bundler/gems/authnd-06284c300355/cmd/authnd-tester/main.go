package main

import (
	"context"
	"os"

	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/authnd/internal/tester"
)

func main() {
	if err := realMain(); err != nil && !errors.Is(err, context.Canceled) {
		log.WithError(err).Error("failed to run service")
		os.Exit(1)
	}
}

func realMain() error {
	cfg, err := tester.NewConfigFromEnvironment()
	if err != nil {
		return err
	}

	ctx, err := cfg.NewRootContext()
	if err != nil {
		diagnostics.ReportError(ctx, err, "an error occurred creating the root context", map[string]string{})
		return err
	}

	defer func() {
		if r := recover(); r != nil {
			// An error reporting the error isn't really actionable since we don't have anywhere to report it.
			diagnostics.ReportError(ctx, r, "unhandled panic", map[string]string{})
			panic(r)
		}
	}()

	shutdown, err := tracing.Instrument(cfg.NewLogger())
	if err != nil {
		return errors.Wrap(err, "failed to initialize tracing")
	}
	defer shutdown()

	testSvc := tester.NewTester(cfg)

	err = testSvc.Run(ctx)
	if err != nil {
		diagnostics.ReportError(ctx, err, "an error occurred running the service", map[string]string{})
		return err
	}

	return nil
}
