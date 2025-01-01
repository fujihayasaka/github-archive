package sessions

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cassettes"
	"github.com/github/turboscan/ts/flipper"
)

func TestManagedAnalysisUpdate(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Onboard the repo
	session.Replay(t, "code-scanning/managed-analyses-enable-js-only.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable-js.yml")
	// Change the workflow run id as we always receive 5 during the tests and it cause successive runs to fail
	session.ChangeCodeqlRunWorkflowRunId(t)

	// Attempt the update
	session.Replay(t, "code-scanning/managed-analyses-update.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-enabled-updating.yml")

	// Mark it as success
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)

	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-stable.yml")

	// Repeating the same update should be a noop
	session.Replay(t, "code-scanning/managed-analyses-update-noop.yml")
}

func TestManagedAnalysisManualUpdateFailed(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Update an existing configuration
	session.Replay(t, "code-scanning/managed-analyses-enable-js-only.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable-js.yml")
	// Change the workflow run id as we always receive 5 during the tests and it cause successive runs to fail
	session.ChangeCodeqlRunWorkflowRunId(t)

	// Attempt the update
	session.Replay(t, "code-scanning/managed-analyses-update.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-enabled-updating.yml")

	// then mark it as failed
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_FAILED)

	session.Replay(t, "code-scanning/get-managed-analysis-info-enabled-failed-update.yml")
}
func TestManagedAnalysisUpdateStaging(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351

	session := cassettes.NewSession(t)
	session.CreateRepository(t, repositoryID, []byte("refs/heads/master"))

	// Try to update a staging configuration
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.Replay(t, "code-scanning/managed-analyses-update-conflict.yml")
}

func TestManagedAnalysisUpdateQuerySuites(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Update an existing configuration
	session.Replay(t, "code-scanning/managed-analyses-enable-js-only.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable-js.yml")
	// Change the workflow run id as we always receive 5 during the tests and it cause successive runs to fail
	session.ChangeCodeqlRunWorkflowRunId(t)

	// Attempt the update
	session.Replay(t, "code-scanning/managed-analyses-update-querysuite.yml")
	// Mark is as success
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)

	session.Replay(t, "code-scanning/get-managed-analysis-info-extended-querysuite_new.yml")
}

func TestManagedAnalysisUpdateNoop(t *testing.T) {
	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Update a staging configuration with no changes - the same workflow ID should be returned
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.Replay(t, "code-scanning/managed-analyses-update-noop.yml")
}

func TestManagedAnalysisUpdateRuby(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Update an existing configuration
	session.Replay(t, "code-scanning/managed-analyses-enable-js-only.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable-js.yml")
	// Change the workflow run id as we always receive 5 during the tests and it cause successive runs to fail
	session.ChangeCodeqlRunWorkflowRunId(t)

	// Attempt the update
	session.Replay(t, "code-scanning/managed-analyses-update-ruby.yml")
}

func TestManagedAnalysisUpdateThreatModelLocalAndRemote(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Update an existing configuration
	session.Replay(t, "code-scanning/managed-analyses-enable-js-only.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable-js.yml")
	// Change the workflow run id as we always receive 5 during the tests and it cause successive runs to fail
	session.ChangeCodeqlRunWorkflowRunId(t)

	// Attempt the update
	session.Replay(t, "code-scanning/managed-analyses-update-threat-model-remote-local.yml")

	// Mark is as success
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)

	session.Replay(t, "code-scanning/get-managed-analysis-info-threat-model-remote-local.yml")
}

func TestManagedAnalysisUpdateOnboards(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Repo is waiting
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable-no-selected-languages.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-waiting.yml")

	// Attempt the update
	session.Replay(t, "code-scanning/managed-analyses-update.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-onboarding.yml")

	// Mark is as success
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)

	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-stable.yml")
}

func TestManagedAnalysisUpdateNoSelectedLanguages(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Repo is stable
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-stable.yml")

	session.Replay(t, "code-scanning/managed-analyses-update-no-selected-languages.yml")

	// Repo should be waiting
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-waiting.yml")
}

func TestManagedAnalysisUpdateLanguages(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Repo is stable
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-stable.yml")

	session.Replay(t, "code-scanning/managed-analyses-update-languages-none.yml")
	session.Replay(t, "code-scanning/managed-analyses-update-languages-test.yml")

	// Repo should be waiting
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-waiting.yml")
}
func TestManagedAnalysisUpdateWaiting(t *testing.T) {
	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Repo is waiting
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable-no-selected-languages.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-waiting.yml")

	// Update only query suite
	session.Replay(t, "code-scanning/managed-analyses-update-querysuite-waiting.yml")

	// Repo should be waiting
	session.Replay(t, "code-scanning/get-managed-analysis-info-waiting-querysuite-extended.yml")
}

func TestManagedAnalysisUpdateRunnerLabelsWaitingState(t *testing.T) {
	session := cassettes.NewSession(t)
	session = session.WithFeatureEnabled(flipper.CodeScanningCustomRunnerLabels)

	session.Replay(t, "code-scanning/managed-analyses-enable-no-selected-languages-runner-label.yml")
	session.Replay(t, "code-scanning/managed-analyses-update-no-selected-languages-runner-label.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-waiting-runner-label-custom.yml")
}

func TestManagedAnalysisUpdateRunnerLabels(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)
	session = session.WithFeatureEnabled(flipper.CodeScanningCustomRunnerLabels)

	// Update an existing configuration
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable-js-only.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-stable-js.yml")

	// An update telling to keep the labels unchanged does not change anything
	session.Replay(t, "code-scanning/managed-analyses-update-runner-labels-unchanged.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-stable-js.yml")

	// Switch to using labeled runners
	session.Replay(t, "code-scanning/managed-analyses-update-runner-labels-custom.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-runner-label-custom.yml")

	// An update telling to keep the labels unchanged does not change anything
	session.Replay(t, "code-scanning/managed-analyses-update-runner-labels-unchanged.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-runner-label-custom.yml")

	// Change to a different custom label
	session.Replay(t, "code-scanning/managed-analyses-update-runner-labels-custom2.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-runner-label-custom2.yml")

	// Switch back to using standard runners
	session.Replay(t, "code-scanning/managed-analyses-update-runner-labels-standard.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-stable-js.yml")
}
