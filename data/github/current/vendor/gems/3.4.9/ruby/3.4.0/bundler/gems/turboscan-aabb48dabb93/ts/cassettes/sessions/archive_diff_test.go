package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestArchivedMergeDiff(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/empty.sarif", "", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/bar.sarif", "", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	// First check that the response makes sense without archival.
	session.Replay(t, "code-scanning/archive-merge-diff.yml")

	// TODO: uncomment this once https://github.com/github/turboscan/pull/4511 is deployed
	// session.ArchiveAll(t)
	// Now check that we get the same response even if we archive everything.
	// session.Replay(t, "code-scanning/archive-merge-diff.yml")
}
