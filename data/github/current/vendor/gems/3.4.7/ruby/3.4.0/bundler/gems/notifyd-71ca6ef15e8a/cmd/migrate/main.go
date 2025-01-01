// Package main implements the entrypoint for the migrate command.
package main

import (
	"context"
	"fmt"
	"os"
	"path"

	"github.com/github/github-telemetry-go/telemetry"
	ghconfig "github.com/github/go-config"
	_ "github.com/go-sql-driver/mysql"
	"github.com/urfave/cli/v2"

	"github.com/github/notifyd/internal/migrate"
	"github.com/github/notifyd/internal/pkg/config"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/process"
)

func main() {
	config.LoadDotEnv()
	cfg := Config{Environment: "development"}
	if err := ghconfig.Load(&cfg); err != nil {
		panic(err)
	}
	ctx := o11y.CtxSetProcessInfo(context.Background(), cfg.Deployment.Environment, "migrate")
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

	cwd, err := os.Getwd()
	if err != nil {
		telem.Logger.WithContext(ctx).WithError(err).Error("could not find cwd")
		panic(err)
	}
	migrationsPath := path.Join(cwd, "migrations")

	app := &cli.App{
		Name:  "migrate",
		Usage: "Run database migrations and transitions. This should be run in development and Enterprise.",
		Action: func(c *cli.Context) error {
			return migrate.RunMigrationsAndTransitions(c.Context, telem, cfg.Environment, cfg.Database, migrationsPath)
		},
	}

	if err := app.Run(os.Args); err != nil {
		telem.Logger.WithContext(ctx).WithError(err).Error("error running migrations")
		process.Exit(process.RuntimeError)
	}
}
