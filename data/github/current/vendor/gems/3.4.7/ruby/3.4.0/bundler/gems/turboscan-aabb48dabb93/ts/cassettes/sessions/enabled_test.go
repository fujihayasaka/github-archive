package sessions

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cassettes"
)

func TestGetCodeScanningEnabledAnalysisExists(t *testing.T) {
	session := cassettes.NewSession(t)
	var repoID uint64 = 351

	// Not enabled if nothing is there
	session.Replay(t, "code-scanning/get-code-scanning-enabled-false.yml")

	// Adding an analysis should cause things to be enabled
	session.Analyze(t, repoID, "data/empty.sarif", "abc", "refs/heads/main")
	session.Replay(t, "code-scanning/get-code-scanning-enabled-true.yml")
}

func TestGetCodeScanningEnabledManagedAnalyses(t *testing.T) {
	var repoID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)
	session.CreateRepository(t, repoID, []byte("refs/heads/master"))

	// Not enabled if nothing is there
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-false.yml")

	// Enable Managed Analyses
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.UpsertCodeqlRunStatus(t, repoID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)

	// Code scanning is enabled now
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-true.yml")

	// Disable Managed Analyses again
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-disable.yml")

	// Code scanning is not enabled anymore
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-false.yml")
}

func TestGetCodeScanningEnabledManagedAnalysesAndManualWorkflows(t *testing.T) {
	var repoID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)
	session.CreateRepository(t, repoID, []byte("heads/refs/main"))

	// Not enabled if nothing is there
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-false.yml")

	// Adding an analysis should cause things to be enabled
	session.Analyze(t, uint64(repoID), "data/empty.sarif", "abc", "refs/heads/main")
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-true.yml")

	// Enable Managed Analyses
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.UpsertCodeqlRunStatus(t, repoID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)

	// Code scanning is still enabled
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-true.yml")

	// Disable Managed Analyses again
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-disable.yml")

	// Code scanning is not enabled anymore
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-false.yml")

	// Adding an analysis should cause things to be enabled again
	session.Analyze(t, uint64(repoID), "data/empty.sarif", "abc", "refs/heads/main")
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-true.yml")
}

func TestGetCodeScanningEnabled3rdParty(t *testing.T) {
	var repoID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)
	session.CreateRepository(t, repoID, []byte("refs/heads/main"))

	// Not enabled if nothing is there
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-false.yml")

	// Adding an analysis and a repo should cause things to be enabled
	session.Analyze(t, uint64(repoID), "data/empty-3rdparty.sarif", "abc", "refs/heads/main")
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-true.yml")

	// Enable Managed Analyses
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.UpsertCodeqlRunStatus(t, repoID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	// Confirm it is on
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info.yml")

	// Code scanning is still enabled
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-true.yml")

	// Disable Managed Analyses again
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-disable.yml")

	// Code scanning is still enabled since there is a 3rd party tool that is enabled
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-true.yml")
}

func TestGetCodeScanningEnabledIsOutdated(t *testing.T) {
	session := cassettes.NewSession(t)
	var repoID uint64 = 351

	// Not enabled if nothing is there
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-false.yml")

	// Adding an analysis should cause things to be enabled
	session.Analyze(t, repoID, "./data/3alerts.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main")
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-true.yml")

	// Adding an outdated analysis ("tombstone" analysis) means the configuration
	// is marked as stale. Code Scanning should be considered not enabled.
	session.Analyze(t, repoID, "", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main", cassettes.WithIsOutdated("Some other tool", ".github/workflows/codeql.yml:CodeQL"))
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-false.yml")

	// Adding an analysis should cause things to be enabled again
	session.Analyze(t, repoID, "data/empty.sarif", "abc", "refs/heads/main")
	session.ReplayReadOnly(t, "code-scanning/get-code-scanning-enabled-true.yml")
}
