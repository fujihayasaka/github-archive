// codeqltelemetryprocessorsvc consumes ProcessedAnalysis events from Hydro and processes CodeQL telemetry diagnostics contained within the SARIF files.
package main

import (
	"os"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/cmd/codeqltelemetryprocessorsvc/root"
)

const (
	// Name for the CodeQL telemetry processor service.
	ServiceName = "codeqltelemetryprocessorsvc"
)

func main() {
	if err := root.CodeQLTelemetryProcessorsCmd.Execute(); err != nil {
		log.WithError(err).Error("failed to run " + ServiceName)
		os.Exit(1)
	}
}
