package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cassettes"
)

func TestPRAlerts(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/empty.sarif", "b", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/1-error.sarif", "a", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))
	session.Analyze(t, repositoryID, "./data/empty.sarif", "b", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	session.Replay(t, "code-scanning/pr-alerts.yml")
}

func TestPRAlertsResolution(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/1-error.sarif", "a", "refs/heads/main", cassettes.WithCommitOid(commitA))

	session.ResolveAllAlerts(t, ts.RepositoryEID(repositoryID))

	session.Analyze(t, repositoryID, "./data/1-error.sarif", "a", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	session.Replay(t, "code-scanning/pr-alerts-resolution.yml")
}

func TestPRAlertsMissingCategories(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/1-error.sarif", "a", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/1-error.sarif", "b", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/1-error.sarif", "c", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "", "c", "refs/heads/main", cassettes.WithCommitOid(commitA), cassettes.WithIsOutdated("Old CodeQL", "c"))
	session.Analyze(t, repositoryID, "./data/1-warning.sarif", "a", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	session.Replay(t, "code-scanning/pr-alerts-missing-categories.yml")
}

func TestPRAlertsFixes(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/1-warning.sarif", "a", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/1-error.sarif", "a", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	session.Replay(t, "code-scanning/pr-alerts-fixes.yml")
}
