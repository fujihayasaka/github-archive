package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestPullRequestAlerts21Alerts(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/other.sarif", "abc", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/21-alerts.sarif", "abc", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	session.Replay(t, "code-scanning/pr-alerts-with-21-annotations.yml")

	// result is the same after the analyses have been archived
	session.ArchiveAll(t)
	session.Replay(t, "code-scanning/pr-alerts-with-21-annotations.yml")
}
