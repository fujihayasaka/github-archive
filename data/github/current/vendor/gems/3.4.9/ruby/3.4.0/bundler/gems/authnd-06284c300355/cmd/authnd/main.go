package main

import (
	"context"

	"github.com/pkg/errors"

	"github.com/github/authnd/internal/api"
	apiConfig "github.com/github/authnd/internal/api/config"
	"github.com/github/authnd/internal/common/diagnostics"
)

func main() {
	if err := realMain(); err != nil && !errors.Is(err, context.Canceled) {
		panic(err)
	}
}

func realMain() error {
	cfg, err := apiConfig.NewConfigFromEnvironment()
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

	svc, err := api.NewService(ctx, cfg)
	if err != nil {
		diagnostics.ReportError(ctx, err, "an error occurred starting the service", map[string]string{})
		return err
	}

	err = svc.Run(ctx)
	if err != nil {
		diagnostics.ReportError(ctx, err, "an error occurred running the service", map[string]string{})
		return err
	}

	return nil
}
