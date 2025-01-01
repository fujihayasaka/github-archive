package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cassettes"
)

func TestPullRequests(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"
	commitC := "199ac6daea3b6d8f2dfa0301688fd9f0071a7e69"
	commitWithExperimentalAlert := "0000000000000000000000000000000000000003"

	session.Analyze(t, repositoryID, "./data/3-warnings-1-note.sarif", "abc", "refs/heads/main", cassettes.WithCommitOid(commitA))

	session.Analyze(t, repositoryID, "./data/1-critical-sec-sev.sarif", "abc", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	session.Analyze(t, repositoryID, "./data/1-medium-sec-sev.sarif", "abc", "refs/pull/1/merge", cassettes.WithCommitOid(commitC))

	// By using the oids above, this database can be used to simulate a
	// successful Diff, a base that requires the Tips strategy,
	// a missing head analysis, or both missing.

	session.Replay(t, "code-scanning/critical-sec-sev-annotations.yml")

	session.Replay(t, "code-scanning/medium-sec-sev-annotations.yml")

	session.Replay(t, "code-scanning/missing-after.yml")

	// This cassette and the one below are for the Annotations endpoint
	session.Replay(t, "code-scanning/annotations.yml")

	session.Analyze(t, repositoryID, "./data/experimental-alerts.sarif", "abc", "refs/pull/1/merge", cassettes.WithCommitOid(commitWithExperimentalAlert))
	session.Replay(t, "code-scanning/annotations-experimental.yml")

	session.ResolveAllAlerts(t, ts.RepositoryEID(repositoryID))
	session.Replay(t, "code-scanning/resolved-annotations.yml")
}
