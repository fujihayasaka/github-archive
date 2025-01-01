// codeql-garbage-collector garbage collects CodeQL items such as CodeQL Runs.

package main

import (
	"os"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/cmd/codeql-garbage-collector/root"
)

const (
	// Name for the CodeQL garbage collector service
	ServiceName = "codeql-garbage-collector"
)

func main() {
	if err := root.CodeQLGarbageCollectorCmd.Execute(); err != nil {
		log.WithError(err).Error("failed to run " + ServiceName)
		os.Exit(1)
	}
}
