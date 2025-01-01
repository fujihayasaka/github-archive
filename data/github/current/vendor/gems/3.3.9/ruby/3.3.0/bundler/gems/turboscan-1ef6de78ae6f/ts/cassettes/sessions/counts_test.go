package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestCounts(t *testing.T) {
	var repositoryID uint64 = 27
	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/3alerts.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main")

	session.Replay(t, "code-scanning/counts-absent.yml")

	session.Replay(t, "code-scanning/counts-present.yml")
}
