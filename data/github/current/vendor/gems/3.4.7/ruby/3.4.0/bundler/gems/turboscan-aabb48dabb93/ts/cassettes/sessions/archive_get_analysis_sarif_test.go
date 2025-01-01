package sessions

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestArchiveGetAnalysisSarif(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)

	commitA := "a270ea0fdfba2bd5a33934e5184784cddce87f38"
	commitB := "480d4f47447129f015cb327536c522ca683939a1"

	session.Analyze(t, repositoryID, "./data/empty.sarif", "", "refs/heads/main", cassettes.WithCommitOid(commitA))
	session.Analyze(t, repositoryID, "./data/bar.sarif", "", "refs/pull/1/merge", cassettes.WithCommitOid(commitB))

	// First check that the response makes sense without archival.
	session.Replay(t, "code-scanning/archive-get-analysis-sarif.yml")

	session.ArchiveAll(t)

	// Now check that we get the same response even if we archive everything.
	session.Replay(t, "code-scanning/archive-get-analysis-sarif.yml")
}

func TestBuildSarifExtensionDeduplication(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/split-extensions.sarif", "", "refs/pull/1/merge", cassettes.WithCommitOid("a270ea0fdfba2bd5a33934e5184784cddce87f38"))

	// Fetching a live analysis should succeed
	session.Replay(t, "code-scanning/get-analysis-sarif-extensions.yml")

	session.ArchiveAll(t)

	// Fetching an archived analysis should succeed
	session.Replay(t, "code-scanning/get-analysis-sarif-extensions.yml")
}

func TestProcessedSarifExtensionDeduplication(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/split-extensions.sarif", "", "refs/pull/1/merge", cassettes.WithCommitOid("a270ea0fdfba2bd5a33934e5184784cddce87f38"))

	// The feature flag should be enabled, so we should respond using the processed SARIF
	session.Replay(t, "code-scanning/get-analysis-sarif-extensions.yml")
}
