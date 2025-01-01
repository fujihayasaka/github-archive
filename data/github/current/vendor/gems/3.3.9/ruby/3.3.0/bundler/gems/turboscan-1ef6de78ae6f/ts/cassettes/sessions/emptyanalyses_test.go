package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cassettes"
)

// TestWithEmptyAnalyses creates three analyses with no results
func TestWithEmptyAnalyses(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)

	session.CreateRepository(t, ts.RepositoryEID(repositoryID), []byte("refs/heads/main"))

	for _, keySuffix := range []string{"w1.yml:job1", "w1.yml:job2", "w2.yml:job1"} {
		session.Analyze(t,
			repositoryID,
			"./data/empty.sarif",
			".github/workflows/"+keySuffix,
			"refs/heads/master",
		)

		session.Analyze(t,
			repositoryID,
			"./data/empty.sarif",
			".github/workflows/"+keySuffix,
			"refs/heads/master",
		)
	}

	session.Replay(t, "code-scanning/index-no-analysis.yml")

	session.Replay(t, "code-scanning/index-no-results.yml")

	session.Replay(t, "code-scanning/no-analyses-diff.yml")

	session.Replay(t, "code-scanning/delete-analysis.yml")

	session.Replay(t, "code-scanning/delete-analysis-not-found.yml")

	session.Replay(t, "code-scanning/delete-analysis-noconfirm.yml")

	session.Replay(t, "code-scanning/delete-analysis-confirm.yml")

	session.Replay(t, "code-scanning/delete-analysis-not-most-recent.yml")

	session.Replay(t, "code-scanning/get-analyses-empty.yml")

	session.ArchiveAnalysis(t, ts.RepositoryEID(repositoryID), ts.AnalysisID(3))

	session.Replay(t, "code-scanning/delete-analysis-clean-slate.yml")
}
