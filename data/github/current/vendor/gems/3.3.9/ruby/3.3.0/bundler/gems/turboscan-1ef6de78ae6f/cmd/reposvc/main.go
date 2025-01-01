// Command reposvc is the entry point for processing Repository metadata updates.
package main

import (
	"os"

	"github.com/github/github-telemetry-go/log"

	"github.com/github/turboscan/cmd/reposvc/root"
)

func main() {
	if err := root.RepoSvcCmd.Execute(); err != nil {
		log.WithError(err).Error("failed to run reposvc")
		os.Exit(1)
	}
}
