// Command repo-deleter deletes the related data of the repository which is permanently deleted on Dotcom. This data includes:
//   - Mysql: records in turboscan database tables which are attached to that repository
//   - ElasticSearch: all documents with matching repository
//   - Azure blob storage: SARIF files associated with the repository
package main

import (
	"os"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/cmd/repo-deleter/root"
)

func main() {
	if err := root.RepoDeleterMainCmd.Execute(); err != nil {
		log.WithError(err).Error("Unexpected error")
		os.Exit(1)
	}
}
