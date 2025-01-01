package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestGetAlert(t *testing.T) {
	var repositoryID uint64 = 15
	session := cassettes.NewSessionWithES(t)

	session.Analyze(t, repositoryID, "./data/bar.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/ref1")

	session.Replay(t, "code-scanning/alert-titles.yml")

	session.Analyze(t, repositoryID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/ref1")
	session.IndexWithRepoMetadata(t, repositoryID, 1, "refs/heads/main", "public", true)

	session.Replay(t, "code-scanning/get-alert.yml")
}
