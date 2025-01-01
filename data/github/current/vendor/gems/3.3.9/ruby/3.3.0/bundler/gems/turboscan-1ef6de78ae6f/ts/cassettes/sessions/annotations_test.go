package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestMultilineAnnotations(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/empty.sarif", "abc", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", "abc", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	session.Replay(t, "code-scanning/multi-line-annotations.yml")
}

func TestAnnotationsNoEndColumn(t *testing.T) {
	var repositoryID uint64 = 105
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/empty.sarif", "abc", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", "abc", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	session.Replay(t, "code-scanning/annotations-no-end-column.yml")
}
