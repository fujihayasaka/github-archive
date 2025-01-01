// Package main is the main package
package main

import (
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
	telemetryProvider, err := telemetry.NewFromEnv()
	if err != nil {
		return err
	}

	logger := telemetryProvider.Logger.Named("chatops")

	cfg, err := config.Load()
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
		logger.Fatal(err.Error())
	}

	return nil
}
