package sessions_test

import (
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"

	"github.com/github/turboscan/ts/cassettes"
)

func TestOrgLevel(t *testing.T) {
	var repo1 uint64 = 351
	var repo2 uint64 = 300
	var repo3 uint64 = 404
	var orgId uint64 = 71

	session := cassettes.NewSessionWithES(t)

	// Make the created at time of all deliveries (and therefore the logical alerts) consistent.
	// Because the cursor sort order depends on the created at time, we need this to be consistent so the requests we make can be consistent.
	createdAtOpt := cassettes.WithCreatedAt(sqltime.Date(2000, 01, 01, 00, 00, 00, 00, time.UTC))

	// Ingest from two different Tools
	session.Analyze(t, repo1, "./data/7e084a1.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master", createdAtOpt)
	session.Analyze(t, repo2, "./data/other.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master", createdAtOpt)
	session.Analyze(t, repo3, "./data/1-alert.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master", createdAtOpt)

	// Define the content for ts_repositories and update the ES index
	session.IndexWithRepoMetadata(t, repo1, orgId, "refs/heads/master", "public", true)
	session.IndexWithRepoMetadata(t, repo2, orgId, "refs/heads/master", "private", true)
	session.IndexWithRepoMetadata(t, repo3, orgId, "refs/heads/master", "private", false) // Code scanning not enabled

	// Close the alert number 1 for repo 351
	session.Replay(t, "code-scanning/org-set-status.yml")
	session.RefreshES(t)

	session.Replay(t, "code-scanning/org-alerts.yml")
	session.Replay(t, "code-scanning/org-alerts-pagination.yml")
	session.Replay(t, "code-scanning/org-tools.yml")
	session.Replay(t, "code-scanning/org-rules.yml")
	session.Replay(t, "code-scanning/org-rule-tags.yml")
	session.Replay(t, "code-scanning/org-repositories.yml")
	session.Replay(t, "code-scanning/org-severities.yml")
	session.Replay(t, "code-scanning/org-alerts-negation.yml")
	session.Replay(t, "code-scanning/org-alerts-repo-visibility.yml")
	session.Replay(t, "code-scanning/org-repo-numbers.yml")
	session.Replay(t, "code-scanning/counts-by-repo-numbers.yml")

	// Even though this is a repo-level endpoint, it uses the org-level search under-the-hood,
	// so we are including it in this test.
	session.Replay(t, "code-scanning/get-alerts-for-insights-backfill.yml")
}
