package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestGetAlertConfigurationStatuses(t *testing.T) {
	var repositoryID uint64 = 1
	session := cassettes.NewSession(t)

	// Alert created
	session.Analyze(t, repositoryID, "./data/bar.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main")
	// Alert fixed
	session.Analyze(t, repositoryID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main")
	// Alert reappeared
	session.Analyze(t, repositoryID, "./data/bar.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main")

	// Set up new branch
	session.Analyze(t, repositoryID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/develop")
	// Alert appeared in branch
	session.Analyze(t, repositoryID, "./data/bar.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/develop")
	// Alert fixed in branch
	session.Analyze(t, repositoryID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/develop")

	// Alert with no baseline: pretend to be branched off from develop and still containing alert
	session.Analyze(t, repositoryID, "./data/bar.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/feature-branch")

	session.Replay(t, "code-scanning/get-alert-configuration-statuses.yml")
}
