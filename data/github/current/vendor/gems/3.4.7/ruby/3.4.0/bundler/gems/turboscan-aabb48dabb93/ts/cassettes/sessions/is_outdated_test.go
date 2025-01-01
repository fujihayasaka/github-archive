package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestIsOutdated(t *testing.T) {
	var repositoryID uint64 = 27
	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/3alerts.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main")
	session.Analyze(t, repositoryID, "", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main", cassettes.WithIsOutdated("Some other tool", ".github/workflows/codeql.yml:CodeQL"))
	session.Replay(t, "code-scanning/outdated-analysis.yml")
	session.Replay(t, "code-scanning/outdated-counts.yml")
	session.Replay(t, "code-scanning/outdated-alert-instances.yml")
}

func TestIsOutdatedWithOutdatedBaseline(t *testing.T) {
	var repositoryID uint64 = 27
	session := cassettes.NewSession(t)

	// create a regular analysis, then another outdated analysis to mark the former one as outdated.
	session.Analyze(t, repositoryID, "./data/3alerts.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main")
	session.Analyze(t, repositoryID, "", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main", cassettes.WithIsOutdated("Some other tool", ".github/workflows/codeql.yml:CodeQL"))

	// create an outdated analysis, which now has the former outdated analysis as its baseline.
	sarifID := "a4e4bbcd-9f4e-4ddd-8e83-66eb9127a6df"
	session.Analyze(t, repositoryID, "", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main", cassettes.WithIsOutdated("Some other tool", ".github/workflows/codeql.yml:CodeQL"), cassettes.WithSarifID(sarifID))
	session.Replay(t, "code-scanning/get-outdated-baseline-delivery-error.yml")
}

func TestIsOutdatedWithMissingBaseline(t *testing.T) {
	var repositoryID uint64 = 27
	session := cassettes.NewSession(t)

	// create an outdated analysis with no baseline analysis
	sarifID := "a4e4bbcd-9f4e-4ddd-8e83-66eb9127a6df"
	session.Analyze(t, repositoryID, "", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main", cassettes.WithIsOutdated("Some other tool", ".github/workflows/codeql.yml:CodeQL"), cassettes.WithSarifID(sarifID))
	session.Replay(t, "code-scanning/get-outdated-no-baseline-delivery-error.yml")
}

func TestIsOutdatedWhereConfigurationHasNoTip(t *testing.T) {
	var repositoryID uint64 = 27
	session := cassettes.NewSession(t)
	session.Analyze(t, repositoryID, "./data/3alerts.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main")
	session.MarkLastAnalysisAsIncomplete(t)
	// create an outdated analysis with no baseline analysis
	sarifID := "a4e4bbcd-9f4e-4ddd-8e83-66eb9127a6df"
	session.Analyze(t, repositoryID, "", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main", cassettes.WithIsOutdated("Some other tool", ".github/workflows/codeql.yml:CodeQL"), cassettes.WithSarifID(sarifID))
	session.Replay(t, "code-scanning/get-outdated-with-no-tip.yml")
}
