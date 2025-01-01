package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestGetAlertsWithPathFilter(t *testing.T) {
	var repositoryID uint64 = 351
	var orgId uint64 = 0
	session := cassettes.NewSessionWithES(t)

	session.Analyze(t, repositoryID, "./data/path-filter.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")

	// Update the indices for both alerts and orgs
	codeScanningEnabled := true
	session.IndexWithRepoMetadata(t, repositoryID, orgId, "refs/heads/master", "public", codeScanningEnabled)

	session.Replay(t, "code-scanning/get-alerts-path-filter.yml")
}

func TestGetAlertsWithPathAndLanguageFilter(t *testing.T) {
	var repositoryID uint64 = 351
	var orgId uint64 = 0
	session := cassettes.NewSessionWithES(t)

	session.Analyze(t, repositoryID, "./data/path-filter.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")

	// Update the indices for both alerts and orgs
	codeScanningEnabled := true
	session.IndexWithRepoMetadata(t, repositoryID, orgId, "refs/heads/master", "public", codeScanningEnabled)

	session.Replay(t, "code-scanning/get-alerts-language-path-filter.yml")
}
