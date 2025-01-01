package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestGetAlertInstances(t *testing.T) {
	var repositoryID uint64 = 15
	session := cassettes.NewSessionWithES(t)

	session.Replay(t, "code-scanning/instances-alert-not-found.yml")

	session.Analyze(t, repositoryID, "./data/bar.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/pull/1/merge")

	session.Replay(t, "code-scanning/get-instances-branches-only-no-data.yml")

	session.Analyze(t, repositoryID, "./data/bar.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main")

	session.Analyze(t, repositoryID, "./data/bar.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/ref1")
	session.IndexWithRepoMetadata(t, repositoryID, 1, "refs/heads/main", "public", true)

	session.Replay(t, "code-scanning/get-instances.yml")

	session.Replay(t, "code-scanning/get-instances-empty.yml")

	session.Replay(t, "code-scanning/get-instances-branches-only.yml")

	session.Replay(t, "code-scanning/get-instances-page-1.yml")

	session.Replay(t, "code-scanning/get-instances-page-2.yml")

	session.Replay(t, "code-scanning/turbocassette-dev.yml")

	session.Replay(t, "code-scanning/get-instances-by-pr-alias.yml")
}
