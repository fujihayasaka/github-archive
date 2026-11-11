// Package main is the main package
package main

import (
	"context"
	"log"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/osslicensecompliance/internal/chatops"
	"github.com/github/osslicensecompliance/internal/config"
)

func main() {
	if err := realMain(); err != nil {
		log.Fatalf("failed to run service: %v", err)
	}
}

func realMain() error {
	ctx := context.Background()
	telemetryProvider, err := telemetry.NewFromEnv()
	if err != nil {
		return err
	}

	logger := telemetryProvider.Logger.Named("chatops")

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	reporter, err := cfg.NewExceptionReporter()
	if err != nil {
		return err
	}

	chatopsStruct := &chatops.Chatops{
		AuthBaseURL:      cfg.ChatopsAuthBaseURL,
		HTTPAddr:         cfg.ChatopsHTTPAddr,
		HealthHTTPAddr:   cfg.ChatopsHealthHTTPAddr,
		AuthPublicKey:    []byte(cfg.ChatopsAuthPublicKey),
		AuthAltPublicKey: []byte(cfg.ChatopsAuthAltPublicKey),
		Namespace:        chatops.Namespace,
		HMACSecret:       cfg.HMACSecret,
	}
	err = chatopsStruct.ListenAndServe()
	if err != nil {
		// Report the error to Sentry via failbotg before logging
		if reportErr := reporter.Report(ctx, err, map[string]string{
			"service":   "chatops",
			"component": "listen_and_serve",
		}); reportErr != nil {
			logger.WithError(reportErr).Error("Failed to report error to Sentry")
		}
		logger.Fatal(err.Error())
	}

	return nil
}
