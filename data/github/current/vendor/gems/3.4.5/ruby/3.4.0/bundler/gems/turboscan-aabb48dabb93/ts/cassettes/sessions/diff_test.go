package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestMergeDiff(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"
	commitC := "199ac6daea3b6d8f2dfa0301688fd9f0071a7e69"

	session.Analyze(t, repositoryID, "./data/empty.sarif", "", "refs/heads/main", cassettes.WithCommitOid(commitA))

	session.Analyze(t, repositoryID, "./data/empty.sarif", "", "refs/pull/1/head", cassettes.WithCommitOid(commitB))

	session.Analyze(t, repositoryID, "./data/bar.sarif", "", "refs/pull/1/merge", cassettes.WithCommitOid(commitC))

	session.Replay(t, "code-scanning/merge-diff.yml")

}
