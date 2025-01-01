package sessions

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cassettes"
)

func TestManagedUsingCombinedLanguages(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Try to enable and succeed
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-enabling.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info.yml")
}

func TestManagedUsingCombinedLanguagesBackwardsCompatibility(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Add a previous onboarding with using-combined-languages set to false
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-disable.yml")
	session.MarkCodeqlConfigsAsNotUsingCombinedLanguages(t, repositoryID)

	// Change the workflow run id as we always receive 5 during the tests and it cause the new onboard to fail
	session.ChangeCodeqlRunWorkflowRunId(t)

	// Try to enable and check that the workflow uses single languages
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-enabling-single-lang.yml")
}
