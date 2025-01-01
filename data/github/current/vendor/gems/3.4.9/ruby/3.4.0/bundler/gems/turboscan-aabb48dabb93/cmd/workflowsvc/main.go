// Command workflowsvc is the entry point for ingesting WorkflowExecution messages.
// This will be used to track progress for the managed analysis.
package main

import (
	"os"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/cmd/workflowsvc/root"
)

const appName = "workflowsvc"

func main() {
	if err := root.WorkflowSvcCmd.Execute(); err != nil {
		log.WithError(err).Error("failed to run " + appName)
		os.Exit(1)
	}
}
