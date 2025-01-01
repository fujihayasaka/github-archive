package main

import (
	"os"

	"github.com/github/github-telemetry-go/log"
)

func main() {
	if err := rootCmd.Execute(); err != nil {
		log.WithError(err).Error("failed to run service")
		os.Exit(1)
	}
}
