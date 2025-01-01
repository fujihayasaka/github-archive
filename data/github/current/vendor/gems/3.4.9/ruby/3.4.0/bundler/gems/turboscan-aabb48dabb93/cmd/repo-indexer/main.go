// repo-indexer is used to (re-)sync information to the `turboscan-*` Elasticsearch index and the database.
// For Elasticsearch the information is updated in two stages:
//   - repository metadata is fetched from Dotcom via the internal Twirp API and updated in the `ts_repositories` table.
//   - repository alert information is synced to Elasticsearch based on the current data in MySQL
//
// Deleted repositories on Dotcom are found via its internal repositories/audits REST API and added into `ts_deleted_repositories` table.
package main

import (
	"os"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/cmd/repo-indexer/root"
)

func main() {
	if err := root.RepoIndexerCmd.Execute(); err != nil {
		log.WithError(err).Error("failed to run repo-indexer")
		os.Exit(1)
	}
}
