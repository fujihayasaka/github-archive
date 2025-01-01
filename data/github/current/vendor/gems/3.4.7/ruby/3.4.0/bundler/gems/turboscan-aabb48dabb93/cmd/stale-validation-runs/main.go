//

package main

import (
	"os"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/cmd/stale-validation-runs/root"
)

func main() {
	if err := root.StaleValidationRunsCmd.Execute(); err != nil {
		log.WithError(err).Error("failed to run service")
		os.Exit(1)
	}
}
