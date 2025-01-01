// Package main implements the entrypoint for the transition-job.
package main

import (
	"context"
	"flag"
	"fmt"

	"github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	ghconfig "github.com/github/go-config"

	"github.com/github/notifyd/internal/pkg/config"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/o11y/stats"
	"github.com/github/notifyd/internal/pkg/process"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
	"github.com/github/notifyd/internal/transitions/registry"
)

var (
	transitionArg string
	dryRun        bool
)

const unitName = "transition-job"

func main() {
	flag.StringVar(&transitionArg, "transition", "", "name of the transition to run")
	flag.BoolVar(&dryRun, "dryRun", true, "whether to run in dry run")
	flag.Parse()

	config.LoadDotEnv()
	cfg := Config{Environment: "development"}
	if err := ghconfig.Load(&cfg); err != nil {
		fmt.Printf("couldn't load config: %v", err)
		process.Exit(process.ConfigLoadError)
	}
	ctx := o11y.CtxSetProcessInfo(context.Background(), cfg.Deployment.Environment, unitName)

	// Telemetry
	telem, err := telemetry.NewFromConfig(cfg.Telemetry)
	if err != nil {
		fmt.Printf("couldn't initialize telemetry: %v", err)
		process.Exit(process.ConfigLoadError)
	}
	telem.Logger = logs.New(telem.Logger)
	defer func() {
		if err := telem.Shutdown(ctx); err != nil {
			fmt.Printf("failed to shutdown telemetry: %v", err)
			process.Exit(process.ShutdownError)
		}
	}()

	c := clock.New()
	statter, err := stats.NewClient(cfg.StatsdAddr, "notifyd."+unitName, cfg.Deployment.Environment)
	if err != nil {
		telem.Logger.WithContext(ctx).WithError(err).Error("failed to build statter")
		process.Exit(process.RuntimeError)
	}

	// Database
	db, dbCleanup, err := mysql.New(ctx, cfg.Database, cfg.Environment)
	if err != nil {
		telem.Logger.WithError(err).Error("failed to build database connection")
		process.Exit(process.DBConnectionError)
	}
	defer func() {
		if err := dbCleanup(); err != nil {
			fmt.Printf("failed to shutdown database: %v", err)
			process.Exit(process.ShutdownError)
		}
	}()

	settingsService := routing.NewSettingsService(routing.NewStorage(c, telem, db), telem, statter)
	subscriptionsService := subscriptions.NewService(subscriptions.NewStorage(c, telem, db), telem, statter)
	registry.Init(telem, settingsService, subscriptionsService)

	telem.Logger.WithContext(ctx).WithFields(
		kvp.String("transition_name", transitionArg),
		kvp.Bool("dryRun", dryRun),
	).Info("running transition job with provided arguments")

	// bail out if there was no transition requested to run. We could do this
	// earlier in the function but this way we have an easier way to test that
	// all the setup works
	if transitionArg == "" {
		telem.Logger.WithContext(ctx).Info("no transition passed, exiting...")
		return
	}

	transition, found := registry.Get(transitionArg)
	if !found {
		telem.Logger.WithContext(ctx).WithError(err).Error("failed to retrieve transition from registry")
		process.Exit(process.RuntimeError)
	}

	// run retrieved transition with provided dryRun flag
	if err := transition.Run(ctx, dryRun); err != nil {
		telem.Logger.WithContext(ctx).WithError(err).Error("runtime error")
		process.Exit(process.RuntimeError)
	}

	telem.Logger.WithContext(ctx).WithFields(
		kvp.String("transition_name", transitionArg),
		kvp.Bool("dryRun", dryRun),
	).Info("finished running transition job with provided arguments")
}
