package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

// TestGetAlerts creates cassettes for the GetAlerts endpoint
// See also TestWithCodeScanningSeed, which also generates cassettes that use this endpoint
func TestGetExperimentalAlerts(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/experimental-alerts.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")

	session.Replay(t, "code-scanning/index-experimental-alerts.yml")
}

func TestGetAlertsExcludingTags(t *testing.T) {
	var repositoryID uint64 = 351
	var orgId uint64 = 0
	session := cassettes.NewSessionWithES(t)

	session.Analyze(t, repositoryID, "./data/3-warnings-1-note.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")

	// Update the indices for both alerts and orgs
	codeScanningEnabled := true
	session.IndexWithRepoMetadata(t, repositoryID, orgId, "refs/heads/master", "public", codeScanningEnabled)

	session.Replay(t, "code-scanning/index-alerts-excluding-tag.yml")
}

func TestGetAlertsWithCursor(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/3alerts.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")

	session.Replay(t, "code-scanning/get-alerts-without-cursor.yml")
	session.Replay(t, "code-scanning/get-alerts-with-cursor-empty.yml")
	session.Replay(t, "code-scanning/get-alerts-with-cursor-next.yml")
	session.Replay(t, "code-scanning/get-alerts-with-cursor-prev.yml")
	session.Replay(t, "code-scanning/get-alerts-with-cursor-first.yml")
	session.Replay(t, "code-scanning/get-alerts-with-cursor-last.yml")
	session.Replay(t, "code-scanning/get-alerts-with-cursor-invalid.yml")
}
