package sessions

import (
	"testing"

	"github.com/github/turboscan/ts"

	"github.com/github/turboscan/ts/cassettes"
)

func TestShow(t *testing.T) {
	var repositoryID uint64 = 23
	session := cassettes.NewSessionWithES(t)

	env := cassettes.WithEnvironment(ts.AnalysisEnv{"os": "Linux"})

	session.Analyze(t, repositoryID, "./data/empty.sarif", ".github/workflows/codeql.yml:show", "refs/heads/master", env)
	session.Analyze(t, repositoryID, "./data/show.sarif", ".github/workflows/codeql.yml:show", "refs/heads/master", env, cassettes.WithCommitOid("ca28b007b099ad3fd9688f9ff250c0e4464728bd"))
	session.Analyze(t, repositoryID, "./data/show.sarif", ".github/workflows/codeql.yml:show", "refs/heads/protected_a", env, cassettes.WithCommitOid("5ad5bac14c233cc80733ba528ce097dc2eca6aeb"))
	session.IndexWithRepoMetadata(t, repositoryID, 1, "refs/heads/master", "public", true)

	session.Replay(t, "code-scanning/show.yml")

	session.ResolveAllAlerts(t, ts.RepositoryEID(repositoryID))
	session.IndexWithRepoMetadata(t, repositoryID, 1, "refs/heads/master", "public", true)

	session.Replay(t, "code-scanning/show-closed.yml")
}

func TestShowRuby(t *testing.T) {
	var repositoryID uint64 = 23
	session := cassettes.NewSessionWithES(t)

	session.Analyze(t, repositoryID, "./data/show-ruby.sarif", ".github/workflows/codeql.yml:ruby", "refs/heads/master", cassettes.WithCommitOid("ca28b007b099ad3fd9688f9ff250c0e4464728bd"))
	session.Analyze(t, repositoryID, "./data/show-ruby.sarif", ".github/workflows/codeql.yml:ruby", "refs/heads/protected_a", cassettes.WithCommitOid("5ad5bac14c233cc80733ba528ce097dc2eca6aeb"))
	session.IndexWithRepoMetadata(t, repositoryID, 1, "refs/heads/master", "public", true)

	session.Replay(t, "code-scanning/show-ruby.yml")
}

func TestShowExperimental(t *testing.T) {
	var repositoryID uint64 = 23
	session := cassettes.NewSessionWithES(t)

	session.Analyze(t, repositoryID, "./data/experimental-alerts.sarif", ".github/workflows/codeql.yml:ruby", "refs/heads/master", cassettes.WithCommitOid("ca28b007b099ad3fd9688f9ff250c0e4464728bd"))
	session.IndexWithRepoMetadata(t, repositoryID, 1, "refs/heads/master", "public", true)

	session.Replay(t, "code-scanning/show-experimental.yml")
}

func TestShowOtherTool(t *testing.T) {
	var repositoryID uint64 = 23
	session := cassettes.NewSessionWithES(t)

	session.Analyze(t, repositoryID, "./data/other.sarif", ".github/workflows/w1.yml:job2", "refs/heads/master", cassettes.WithCommitOid("ca28b007b099ad3fd9688f9ff250c0e4464728bd"))
	session.IndexWithRepoMetadata(t, repositoryID, 1, "refs/heads/master", "public", true)

	session.Replay(t, "code-scanning/show-other.yml")
}
