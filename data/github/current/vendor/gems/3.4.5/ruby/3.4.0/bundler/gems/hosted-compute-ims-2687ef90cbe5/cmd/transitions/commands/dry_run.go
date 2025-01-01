package commands

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
)

//nolint:gochecknoinits
func init() {
	RegisterCommand(Instance{
		Description: "Dry-run command for testing purposes",
		Run: func(ctx context.Context, inputArg string, cmd Instance) error {
			logger.Info(ctx, "Running dry run command with input:", kvp.String("input", inputArg))

			logger.Info(ctx, "Available commands", kvp.String("commands", ListCommands()))
			return nil
		},
	})
}
