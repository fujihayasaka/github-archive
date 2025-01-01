package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestWithoutElasticSearch(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")
	session.Analyze(t, repositoryID, "./data/other.sarif", ".github/workflows/w1.yml:job2", "refs/heads/master")
	session.Analyze(t, repositoryID, "./data/different.sarif", ".github/workflows/ww.yml:job1", "refs/heads/master")
	session.Analyze(t, repositoryID, "./data/different.sarif", ".github/workflows/ww.yml:job1", "refs/heads/protected_a")

	session.Replay(t, "code-scanning/get-alerts-free-text-not-configured.yml")
}

func TestWithElasticSearch(t *testing.T) {
	var repositoryID uint64 = 351
	var orgId uint64 = 0
	session := cassettes.NewSessionWithES(t)

	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master")
	session.Analyze(t, repositoryID, "./data/other.sarif", ".github/workflows/w1.yml:job2", "refs/heads/master")
	session.Analyze(t, repositoryID, "./data/different.sarif", ".github/workflows/ww.yml:job1", "refs/heads/master")
	session.Analyze(t, repositoryID, "./data/different.sarif", ".github/workflows/ww.yml:job1", "refs/heads/protected_a")

	codeScanningEnabled := true
	session.IndexWithRepoMetadata(t, repositoryID, orgId, "refs/heads/master", "public", codeScanningEnabled)

	session.Replay(t, "code-scanning/get-alerts-free-text.yml")
	session.Replay(t, "code-scanning/get-alerts-free-text-invalid-query.yml")
	session.Replay(t, "code-scanning/tool-names.yml")
}
