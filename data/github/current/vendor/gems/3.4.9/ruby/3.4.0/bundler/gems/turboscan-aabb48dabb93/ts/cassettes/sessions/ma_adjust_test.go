package sessions

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cassettes"
)

func TestManagedAnalysisAdjust(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)
	session.CreateRepository(t, repositoryID, []byte("refs/heads/master"))

	// Enable will create an staged config
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")

	// A staged configuration can be adjusted
	session.Replay(t, "code-scanning/managed-analyses-adjust.yml")
	// A configuration cannot be adjusted from the wrong workflow run
	session.Replay(t, "code-scanning/managed-analyses-adjust-error-wrong-workflow.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-enabled-adjusted.yml")
	session.Replay(t, "code-scanning/managed-analyses-adjust-error.yml")
}

func TestManagedAnalysisAdjustGeneralError(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351

	session := cassettes.NewSession(t)
	session.CreateRepository(t, repositoryID, []byte("refs/heads/master"))

	// Enable will create an staged config
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")

	// This request contains an invalid language and causes an internal error
	session.Replay(t, "code-scanning/managed-analyses-adjust-error-internal.yml")
}
