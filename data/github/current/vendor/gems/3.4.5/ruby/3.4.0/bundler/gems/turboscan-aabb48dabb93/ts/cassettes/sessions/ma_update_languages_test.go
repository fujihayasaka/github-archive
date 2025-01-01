package sessions

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cassettes"
)

func TestManagedAnalysisUpdateLanguagesSuccess(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Enable Repo
	session.Replay(t, "code-scanning/managed-analyses-enable-js-only.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable-js.yml")
	// Change the workflow run id as we always receive 5 during the tests and it cause successive runs to fail
	session.ChangeCodeqlRunWorkflowRunId(t)

	session.Replay(t, "code-scanning/managed-analyses-update-languages.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-only-ruby.yml")
}
func TestManagedAnalysisUpdateLanguagesFailed(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Enable Repo
	session.Replay(t, "code-scanning/managed-analyses-enable-js-only.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable-js.yml")
	// Change the workflow run id as we always receive 5 during the tests and it cause successive runs to fail
	session.ChangeCodeqlRunWorkflowRunId(t)

	// mark the update validation run as failed
	session.Replay(t, "code-scanning/managed-analyses-update-languages.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_FAILED)

	session.Replay(t, "code-scanning/get-managed-analysis-info-enabled-failed-auto-update.yml")
}

func TestManagedAnalysisUpdateLanguagesNoop(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Enable Repo
	session.Replay(t, "code-scanning/managed-analyses-enable-js-only.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable-js.yml")

	session.Replay(t, "code-scanning/managed-analyses-update-languages-noop.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable-js.yml")
}

func TestManagedAnalysisUpdateLanguagesRemovesAllLanguages(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Enable Repo
	session.Replay(t, "code-scanning/managed-analyses-enable-js-only.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable-js.yml")

	session.Replay(t, "code-scanning/managed-analyses-update-languages-remove-last-lang.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-waiting.yml")
}

func TestManagedAnalysisUpdateLanguagesUpdateInProgress(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Enable Repo
	session.Replay(t, "code-scanning/managed-analyses-enable-js-only.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable-js.yml")
	// Change the workflow run id as we always receive 5 during the tests and it cause successive runs to fail
	session.ChangeCodeqlRunWorkflowRunId(t)

	session.Replay(t, "code-scanning/managed-analyses-update-querysuite.yml")
	session.Replay(t, "code-scanning/managed-analyses-update-languages-update-in-progress.yml")
}

func TestManagedAnalysisUpdateLanguagesOffboardedRepo(t *testing.T) {
	session := cassettes.NewSession(t)

	// Repo starts disabled
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-disabled.yml")

	session.Replay(t, "code-scanning/managed-analyses-update-languages-disabled_new.yml")
}

func TestManagedAnalysisUpdateLanguagesWaitingRepo(t *testing.T) {
	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Enable the repo without selected languages
	session.Replay(t, "code-scanning/managed-analyses-enable-no-selected-languages.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-waiting.yml")

	session.Replay(t, "code-scanning/managed-analyses-update-languages-add-java.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-onboarding-java.yml")
}
