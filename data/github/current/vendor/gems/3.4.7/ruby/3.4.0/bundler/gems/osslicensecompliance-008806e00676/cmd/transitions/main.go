// The transitions tool applies database backfills and the like.
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/transitions"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "transitions failed: %v\n", err) //nolint:revive // unhandled-error: already in an error condition
		os.Exit(1)
	}
}

func getTransition() (transitions.Transition, []string, error) {
	// default to running the check transition. This meets the requirement that the executable
	// runs and does a self-test when no args are provided.
	transitionName := "check"
	args := []string{}
	if len(os.Args) > 1 {
		transitionName = os.Args[1]
		if len(os.Args) > 2 {
			args = os.Args[2:]
		}
	}

	transition, ok := transitions.GetTransitions()[transitionName]
	if !ok {
		return nil, nil, fmt.Errorf("unknown transition: %s", transitionName)
	}
	return transition, args, nil
}

func run() error {
	ctx := context.Background()
	transition, args, err := getTransition()
	if err != nil {
		return err
	}

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	tele, err := telemetry.NewFromEnv()
	if err != nil {
		return err
	}
	logger := tele.Logger.Named("transitions")

	reporter, err := cfg.NewExceptionReporter()
	if err != nil {
		return err
	}

	statter, err := cfg.NewStatsClient()
	if err != nil {
		return err
	}
	logger.Info("starting statsd client.")
	statter.Run()
	defer statter.Stop()

	defer func() {
		if recovered := recover(); recovered != nil {
			tags := stats.Tags{
				"service": "transitions",
			}
			statter.Counter("internal.service.panic", tags, 1)
			panic(recovered)
		}
	}()

	app, err := application.New(cfg, logger, statter)
	if err != nil {
		// Report the error to Sentry via failbotg
		if reportErr := reporter.Report(ctx, err, map[string]string{
			"service":   "transitions",
			"component": "application_setup",
		}); reportErr != nil {
			logger.Error("Failed to report error to Sentry", kvp.String("error", reportErr.Error()))
		}
		return fmt.Errorf("error creating application: %w", err)
	}

	logger.Info("Transitions application successfully set up")

	defer func() {
		if err := app.Close(); err != nil {
			logger.Error("failed to close application %s", kvp.String("error msg:", err.Error()))
		}
	}()

	err = transition(app, args)
	if err != nil {
		// Report the transition error to Sentry via failbotg
		if reportErr := reporter.Report(ctx, err, map[string]string{
			"service":   "transitions",
			"component": "transition_execution",
		}); reportErr != nil {
			logger.Error("Failed to report error to Sentry", kvp.String("error", reportErr.Error()))
		}
	}
	return err
}
