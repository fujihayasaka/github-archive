package main

import (
	"context"
	"flag"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/cmd/transitions/commands"
	"github.com/github/hosted-compute-ims/internal/config"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/telemetry"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
)

var (
	commandName = flag.String("command", "dry_run.go", "a specific command to run 'azure_subscription_update.go'")
	inputFlag   = flag.String("input", "", "string input passed to the command")
)

func main() {
	if err := realMain(); err != nil {
		panic(err)
	}
}

func realMain() error {
	ctx := context.Background()

	// load app config
	cfg := &config.Config{}
	if err := cfg.Load(); err != nil {
		return err
	}

	telem, err := telemetry.InitializeTelemetry(ctx, &cfg.Telemetry)
	if err != nil {
		return fmt.Errorf("failed to initialize telemetry: %w", err)
	}
	defer telem.Shutdown(ctx)

	// initialize  db stores
	imagesStore, err := store.NewImagesStoreWithMySQLConnection(&cfg.MySQL)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize database connection", err)
		return err
	}

	flag.Parse()
	helpers := commands.Helpers{
		Config:     cfg,
		ImageStore: imagesStore,
	}

	ctx = stash.WithLoggingFields(ctx,
		kvp.Stringp("command", commandName),
		kvp.Stringp("input", inputFlag),
	)

	logger.Info(ctx, "Running command")

	err = commands.Run(ctx, *commandName, *inputFlag, helpers)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to run command", err)
		return fmt.Errorf("failed to run command: %w", err)
	}

	logger.Info(ctx, "Command finished successfully")

	return nil
}
