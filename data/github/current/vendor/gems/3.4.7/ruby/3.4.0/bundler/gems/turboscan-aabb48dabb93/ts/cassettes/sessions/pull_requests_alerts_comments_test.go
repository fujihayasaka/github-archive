package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestPullRequestsReviewComments(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/other.sarif", "abc", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/2-alerts-in-separate-files.sarif", "abc", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	session.Replay(t, "code-scanning/pr-alerts-and-annotations-2-alerts.yml")

	// Ensure the same result after archival
	session.ArchiveAll(t)
	session.Replay(t, "code-scanning/pr-alerts-and-annotations-2-alerts.yml")
}

func TestPullRequestsReviewCommentsForFixed(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"
	commitC := "199ac6daea3b6d8f2dfa0301688fd9f0071a7e69"

	session.Analyze(t, repositoryID, "./data/other.sarif", "abc", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/2-alerts-in-separate-files.sarif", "abc", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))
	session.Analyze(t, repositoryID, "./data/1-alert.sarif", "abc", "refs/pull/1/merge", cassettes.WithCommitOid(commitC))

	session.Replay(t, "code-scanning/pr-alerts-and-annotations-1-alert.yml")

	// Ensure the same result after archival
	session.ArchiveAll(t)
	session.Replay(t, "code-scanning/pr-alerts-and-annotations-1-alert.yml")
}

func TestPullRequestsReviewCommentsForDismissed(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/other.sarif", "abc", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/2-alerts-in-separate-files.sarif", "abc", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	// dismiss one of the alerts
	session.Replay(t, "code-scanning/set-status-close-1.yml")
	session.Replay(t, "code-scanning/set-status-close-with-approver.yml")

	session.Replay(t, "code-scanning/pr-alerts-and-annotations-1-open-1-closed.yml")

	// Ensure the same result after archival
	session.ArchiveAll(t)
	session.Replay(t, "code-scanning/pr-alerts-and-annotations-1-open-1-closed.yml")
}
