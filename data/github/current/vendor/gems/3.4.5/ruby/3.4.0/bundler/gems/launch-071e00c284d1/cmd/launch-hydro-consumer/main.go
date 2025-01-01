package main

import (
	"context"
	"fmt"
	"os"
	"runtime/debug"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/cli"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/services"
	"github.com/github/launch/services/health"
	"github.com/github/launch/services/hydrosvc"
	"github.com/github/launch/services/hydrosvc/config"
	"github.com/github/launch/utils/appcontext"
)

func main() {
	if err := realMain(); err != nil {
		cfg, cfgerr := config.Load()
		if cfgerr != nil {
			os.Exit(1)
		}

		logger := cfg.GetLogger()
		logger.Error(context.Background(), "failed to run launch-hydro-consumer", kvp.Err(err))
		os.Exit(1)
	}
}

func realMain() error {
	cli.ParseFlags()
	metadata := cli.GetApplicationMetadata("launch-hydro-consumer")

	ctx, err := appcontext.Initialize(context.Background(), metadata)
	if err != nil {
		return err
	}

	if err := launchconfig.LoadGlobalConfig(); err != nil {
		return err
	}

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	log := cfg.GetLogger()
	stats := cfg.GetStatter(metadata.ObservabilityFields)
	obs := observability.New(log, stats)

	shutdown, err := tracing.Instrument(ctx, log, cfg.TracingEnabled)
	if err != nil {
		return err
	}
	defer shutdown()

	defer func() {
		if rvr := recover(); rvr != nil {

			var err error
			if e, ok := rvr.(error); ok {
				err = e
			} else {
				err = fmt.Errorf("%v", rvr)
			}

			obs.Report(ctx, errors.WithStack(err), kvp.String("exception_detail", string(debug.Stack())))
		}
	}()

	hydrosvc, err := hydrosvc.New(ctx, cfg, obs)
	if err != nil {
		return err
	}

	healthsvc, err := health.New(health.Config{Version: metadata.BuildVersion, Address: cfg.InternalAddr}, obs)
	if err != nil {
		return err
	}

	return services.RunServices(ctx, obs, healthsvc, hydrosvc)
}
