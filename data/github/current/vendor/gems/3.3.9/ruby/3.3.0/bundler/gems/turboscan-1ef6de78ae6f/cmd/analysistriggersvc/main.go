// analysistriggersvc consumes push and pr events from the Hydro and runs managed analysis jobs for the affected repositories.
package main

import (
	"os"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/cmd/analysistriggersvc/root"
)

func main() {
	if err := root.AnalysisTriggerCmd.Execute(); err != nil {
		log.WithError(err).Error("error executing command")
		os.Exit(1)
	}
}
