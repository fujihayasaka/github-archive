package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestGetLinksForAlertsEmpty(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSessionWithES(t)

	session.Analyze(t, repositoryID, "./data/3alerts.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")

	session.Replay(t, "code-scanning/get-links-for-alerts-empty.yml")
}

func TestGetLinksForAlertsPrAndRef(t *testing.T) {
	var repositoryID uint64 = 351
	var orgId uint64 = 71
	session := cassettes.NewSessionWithES(t)

	session.Analyze(t, repositoryID, "./data/3alerts.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")

	session.Replay(t, "code-scanning/create-alert-links-pull-request.yml")
	session.Replay(t, "code-scanning/create-alert-links-ref.yml")

	session.Replay(t, "code-scanning/get-links-for-alerts-pr-and-ref.yml")

	// Test that org-level endpoints show correct in progress data
	session.IndexWithRepoMetadata(t, repositoryID, orgId, "refs/heads/master", "public", true)
	session.Replay(t, "code-scanning/org-repo-numbers-links.yml")
	session.Replay(t, "code-scanning/counts-by-repo-numbers-links.yml")
}
