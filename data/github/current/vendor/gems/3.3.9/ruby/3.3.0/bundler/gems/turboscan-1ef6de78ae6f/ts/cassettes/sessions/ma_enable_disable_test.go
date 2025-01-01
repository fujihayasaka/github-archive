package sessions

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cassettes"
	"github.com/github/turboscan/ts/config"
)

func TestEnableWhileEnabled(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Onboard the repo using the existing logic
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-enabling.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info.yml")

	// State should not change
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable.yml")

	// Call the enable endpoint. It should be a noop.
	session.Replay(t, "code-scanning/managed-analyses-enable-noop.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable.yml")
}

func TestManagedAnalysisEnableWithSelectedLanguagesAndDisable(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Repo starts disabled
	session.Replay(t, "code-scanning/get-managed-analysis-info-disabled.yml")

	// Disabling a repo that is disabled should be a no-op
	session.Replay(t, "code-scanning/managed-analyses-disable-noop.yml")

	// Enable the repo with selected languages
	session.Replay(t, "code-scanning/managed-analyses-enable.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-onboarding.yml")

	// Validation run succeeds
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-stable.yml")

	// Calling enable again should be a noop
	session.Replay(t, "code-scanning/managed-analyses-enable-noop.yml")

	// Disable
	session.Replay(t, "code-scanning/managed-analyses-disable.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-disabled.yml")
}

func TestManagedAnalysisEnableWithSelectedLanguagesOnboardingFailed(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Repo starts disabled
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-disabled.yml")

	// Enable the repo with selected languages
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-onboarding.yml")

	// Validation run fails
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_FAILED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-waiting-onboarding-failed.yml")

	// Calling enable again should be a noop
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable-noop.yml")

	// Disable
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-disable.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-disabled.yml")
}

func TestManagedAnalysisEnableWithoutSelectedLanguagesAndDisable(t *testing.T) {
	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Repo starts disabled
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-disabled.yml")

	// Enable the repo without selected languages
	session.Replay(t, "code-scanning/managed-analyses-enable-no-selected-languages.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-waiting.yml")

	// Calling enable again should be a noop
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable-noop.yml")

	// Disable
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-disable.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-disabled.yml")
}

func TestManagedAnalysisEnableWithoutSupportedLanguagesAndDisable(t *testing.T) {
	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Repo starts disabled
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-disabled.yml")

	// Enable the repo without supported languages
	session.Replay(t, "code-scanning/managed-analyses-enable-no-supported-languages.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-waiting.yml")
}

func TestManagedAnalysisEnableRuby(t *testing.T) {
	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Repo starts disabled
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-disabled.yml")

	// Enable the repo without supported languages
	session.Replay(t, "code-scanning/managed-analyses-enable-ruby.yml")
}

func TestManagedAnalysisEnableSwift(t *testing.T) {
	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	session.Replay(t, "code-scanning/managed-analyses-enable-swift.yml")
}

func TestManagedAnalysisEnableQuerySuiteExtended(t *testing.T) {
	var repositoryID ts.RepositoryEID = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	session.Replay(t, "code-scanning/managed-analyses-enable-query-suite-extended.yml")
	session.UpsertCodeqlRunStatus(t, repositoryID, workflowRunID, ts.CodeqlRunStatus_COMPLETED)
	session.Replay(t, "code-scanning/get-managed-analysis-info-extended-query-suite-three-languages.yml")
}

func TestManagedAnalysisOnboardThreatModelLocalAndRemote(t *testing.T) {
	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	session.Replay(t, "code-scanning/managed-analyses-enable-threat-model-remote-local.yml")
}

func TestEnableUsingCodeScanningRunnerLabel(t *testing.T) {
	session := cassettes.NewSession(t)

	// Try to enable and succeed
	session.Replay(t, "code-scanning/managed-analyses-enable-with-cs-runner-label.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-enabling-with-default-cs-runner-label.yml")
}

func TestEnableUsingExplicitCodeScanningRunnerLabel(t *testing.T) {
	session := cassettes.NewSession(t)

	// Try to enable and succeed
	session.Replay(t, "code-scanning/managed-analyses-enable-with-explicit-cs-runner-label.yml")
	session.ReplayReadOnly(t, "code-scanning/get-managed-analysis-info-enabling-with-default-cs-runner-label.yml")
}

func TestEnableUsingCustomRunnerLabel(t *testing.T) {
	session := cassettes.NewSession(t)

	// The enablement statusService will emit a Sentry exception after a completed validation run and
	// after onboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Try to enable and succeed
	session.Replay(t, "code-scanning/managed-analyses-enable-with-custom-runner-label.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-enabling-with-custom-runner-label.yml")
}

func TestManagedAnalysisOnboardJavaBuildless(t *testing.T) {
	session := cassettes.NewSession(t)

	session.Replay(t, "code-scanning/managed-analyses-enable-java.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-buildless-java.yml")
}
func TestManagedAnalysisOnboardCSharpBuildless(t *testing.T) {
	session := cassettes.NewSession(t)

	session.Replay(t, "code-scanning/managed-analyses-enable-csharp.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-buildless-csharp.yml")
}

func TestManagedAnalysisOnboardCSharpBuildlessDisabled(t *testing.T) {
	session := cassettes.NewSessionWithConfigOverride(t, func(config *config.Config) {
		config.CSharpBuildlessDisabled = true
	})

	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable-csharp.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-buildless-disabled-csharp.yml")
}

func TestManagedAnalysisOnboardKotlin(t *testing.T) {
	session := cassettes.NewSession(t)

	session.Replay(t, "code-scanning/managed-analyses-enable-java-kotlin.yml")
	session.Replay(t, "code-scanning/get-managed-analysis-info-java-kotlin.yml")
}
