package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

// TestWithCodeScanningSeed creates a database with some basic alert data and three distinct tools
func TestWithCodeScanningSeed(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSessionWithES(t)

	session.Replay(t, "code-scanning/analysis-not-found.yml")

	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")

	session.Analyze(t, repositoryID, "./data/other.sarif", ".github/workflows/w1.yml:job2", "refs/heads/master")

	session.Analyze(t, repositoryID, "./data/different.sarif", ".github/workflows/ww.yml:job1", "refs/heads/master")

	session.Analyze(t, repositoryID, "./data/different.sarif", ".github/workflows/ww.yml:job1", "refs/heads/protected_a")

	// index will set two alerts to resolved to get the data into the correct state
	session.Replay(t, "code-scanning/index.yml")
	session.IndexWithRepoMetadata(t, repositoryID, 1, "refs/heads/master", "public", true)

	session.Replay(t, "code-scanning/get-alerts.yml")

	session.Replay(t, "code-scanning/get-alerts-results.yml")

	session.Replay(t, "code-scanning/get-closed-alerts.yml")

	session.Replay(t, "code-scanning/get-alerts-by-page.yml")

	session.Replay(t, "code-scanning/analysis-sarif.yml")

	session.Replay(t, "code-scanning/get-analyses-page-1.yml")

	session.Replay(t, "code-scanning/get-analyses-page-2.yml")

	session.Replay(t, "code-scanning/get-analyses-page-3.yml")

	session.Replay(t, "code-scanning/get-analysis.yml")

	session.Replay(t, "code-scanning/get-analyses.yml")

	session.Replay(t, "code-scanning/get-analyses-ascending.yml")

	session.Replay(t, "code-scanning/get-analyses-by-refs.yml")

	session.Replay(t, "code-scanning/counts-by-tool.yml")

	session.Replay(t, "code-scanning/counts-by-tool-no-refs.yml")

	session.Replay(t, "code-scanning/set-status-close.yml")

	session.Replay(t, "code-scanning/set-status-reopen.yml")

	session.Replay(t, "code-scanning/set-status-with-ref.yml")

	session.Replay(t, "code-scanning/set-status-not-found.yml")

	session.Replay(t, "code-scanning/get-alert-2.yml")

	session.Replay(t, "code-scanning/get-code-paths.yml")

	session.Replay(t, "code-scanning/get-rule-tags.yml")

	// Fix one of the alerts for one configuration
	session.Analyze(t, repositoryID, "./data/7e084a1-fix-but-one.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")

	session.Analyze(t, repositoryID, "./data/7e084a1-fix-but-one.sarif", ".github/workflows/w1.yml:job1", "refs/pull/1/head")

	session.Analyze(t, repositoryID, "./data/7e084a1-fix-but-one.sarif", ".github/workflows/w1.yml:job1", "refs/pull/1/merge")

	session.Replay(t, "code-scanning/get-alerts-state-filter-all.yml")

	session.Replay(t, "code-scanning/get-alerts-state-filter-closed.yml")

	session.Replay(t, "code-scanning/get-alerts-state-filter-dismissed.yml")

	session.Replay(t, "code-scanning/get-alerts-state-filter-fixed.yml")

	session.Replay(t, "code-scanning/get-alerts-state-filter-open.yml")

	session.Replay(t, "code-scanning/get-alerts-by-ref.yml")

	session.Replay(t, "code-scanning/get-alerts-order.yml")

	session.Replay(t, "code-scanning/get-alerts-last-state-change.yml")

	session.Replay(t, "code-scanning/get-alerts-last-state-change-ascending.yml")

	session.Replay(t, "code-scanning/get-analyses-by-pr-alias.yml")

	session.Replay(t, "code-scanning/get-alerts-by-pr-alias.yml")
}
