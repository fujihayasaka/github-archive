package sessions

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestGetToolStatus(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "../../sarif/testdata/toolExecutionNotificationExtensionLookup.sarif", ".github/workflows/w1.yml:job2", "refs/heads/master", cassettes.WithTrackStatus())

	session.Replay(t, "code-scanning/get-tool-status.yml")
}

func TestGetToolStatusCodeQLConfig(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "../../sarif/testdata/codeql_config.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master", cassettes.WithTrackStatus())

	session.Replay(t, "code-scanning/get-tool-status-codeql-config.yml")
}

func TestGetToolStatusNoLanguageFiles(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "../../sarif/testdata/tool-status-notification-with-no-files.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master", cassettes.WithTrackStatus())

	session.Replay(t, "code-scanning/get-tool-status-blank.yml")
}

func TestGetToolStatusModelPacks(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "../../sarif/testdata/tool-status-extensions-model-packs.sarif", ".github/workflows/codeql-analysis.yml:analyze/language:java/", "refs/heads/master", cassettes.WithTrackStatus())

	session.Replay(t, "code-scanning/get-tool-status-model-packs.yml")
}

func TestFilesExtractedSummaryMultipleLanguageFiles(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "../../sarif/testdata/get_tool_status_with_multiple_languages.sarif", ".github/workflows/w1.yml:job1", "refs/heads/master", cassettes.WithTrackStatus())

	session.Replay(t, "code-scanning/get-extracted-files-summary-multiple-languages.yml")
}

func TestStatusPageVisibility(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(
		t,
		repositoryID,
		"../../sarif/testdata/example-with-tool-status-notifications-visibility-true.sarif",
		".github/workflows/w1.yml:job1",
		"refs/heads/master",
		cassettes.WithTrackStatus(),
	)

	session.Replay(t, "code-scanning/save-codeql-notification-message.yml")
}

func TestGetToolStatusOutdated(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/3alerts.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")
	session.Analyze(t, repositoryID, "", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master", cassettes.WithIsOutdated("Some other tool", ".github/workflows/codeql.yml:CodeQL"))
	session.Replay(t, "code-scanning/get-tool-status-messages-outdated.yml")
}

func TestGetToolStatusManagedAnalysis(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", "dynamic/github-code-scanning/codeql:", "refs/heads/master")
	session.Replay(t, "code-scanning/get-tool-status-ma.yml")
}

func TestToolStatusMultipleAnalyses(t *testing.T) {
	var repositoryID uint64 = 351

	session := cassettes.NewSession(t)

	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", "dynamic/github-code-scanning/codeql:", "refs/heads/master")
	session.Analyze(t, repositoryID, "./data/7e084a1-fix-but-one.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")
	session.Analyze(t, repositoryID, "./data/other.sarif", ".github/workflows/third-party.yml", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-multiple-analyses.yml")
}
