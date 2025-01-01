package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cassettes"
)

// TestErrorAnalyses creates analyses with errors
func TestErrorAnalyses(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)

	// An incomplete analysis
	session.Analyze(t, repositoryID, "./data/1-medium-sec-sev.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main")
	session.MarkLastAnalysisAsIncomplete(t)

	session.Replay(t, "code-scanning/get-analyses-incomplete.yml")

	// A failed analysis with a ProcessError
	session.Analyze(t, repositoryID, "./data/malformed.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main")

	// A failed analysis with no ProcessError
	session.Analyze(t, repositoryID, "./data/malformed.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/main")
	session.DeleteProcessErrorForLastAnalysis(t)

	session.Replay(t, "code-scanning/get-analyses-errors.yml")

	session.Replay(t, "code-scanning/get-analysis-unknown-error.yml")

	session.Replay(t, "code-scanning/get-analysis-process-error.yml")

	session.Replay(t, "code-scanning/get-analysis-incomplete.yml")

	session.Replay(t, "code-scanning/get-analysis-incomplete-sarif.yml")
}

// Tests messages for successful and valid sarif deliveries for failed runs (containing error/debug information).
func TestDeliveryMessages(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)
	// A valid analysis with no warnings
	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-messages.yml")

	// A valid analysis with executionSuccessful False with a message and a ProcessError (due to CodeQL)
	session.Analyze(t, repositoryID, "./data/execution-failed.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-messages-warning.yml")

	// A valid analysis with executionSuccessful False with message and no ProcessError (as it comes from another tool)
	session.Analyze(t, repositoryID, "./data/execution-failed-other-tool.sarif", ".github/workflows/codeql.yml:OtherTool", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-messages-two-warnings.yml")

	// Analyses for those two tools with a different deliveryOrigin
	deliveryOriginOp := cassettes.WithDeliveryOrigin(ts.DeliveryOrigin_API)
	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", "some-api-category", "refs/heads/master", deliveryOriginOp)
	session.Analyze(t, repositoryID, "./data/execution-failed.sarif", "different-api-category", "refs/heads/master", deliveryOriginOp)
	session.Analyze(t, repositoryID, "./data/execution-failed-other-tool.sarif", "other-tool-api", "refs/heads/master", deliveryOriginOp)
	session.Analyze(t, repositoryID, "./data/execution-failed-other-tool.sarif", "other-tool-api-2", "refs/heads/master", deliveryOriginOp)

	session.Replay(t, "code-scanning/get-tool-status-messages-two-tools-two-configuration-groups.yml")
}

func TestDeliveryMessageWithoutAnalysisID(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)

	// An analysis with one failed run and one successful run
	session.Analyze(t, repositoryID, "./data/multi-run-with-different-success.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-delivery-message.yml")
}

func TestDeliveryMessageSarifParsingFailed(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only finds delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	// Then we produce the error
	session.Analyze(t, repoID, "./data/invalid-syntax.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-delivery-message-sarif-parsing-failed.yml")
}

func TestCreateDeliverySarifParsingFailed(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only finds delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-create-delivery-sarif-parsing-failed.yml")
}

func TestCreateDeliveryZipTooBig(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only finds delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-create-delivery-zip-too-big.yml")
}

func TestCreateDeliverySarifTooBig(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only finds delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-create-delivery-sarif-too-big.yml")
}

func TestCreateDeliveryZipEmpty(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only finds delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-create-delivery-zip-empty.yml")
}

func TestCreateDeliveryZipInvalid(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only finds delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-create-delivery-zip-invalid.yml")
}

func TestDeliveryMessageSarifHardLimitLocationsPerResult(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only finds delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	// Then we produce the error
	session.Analyze(t, repoID, "./data/too-many-locations.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-delivery-message-sarif-hard-limit-locations-per-result.yml")
}

func TestDeliveryMessageSarifHardLimitTagsPerRule(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only finds delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	// Then we produce the error
	session.Analyze(t, repoID, "./data/too-many-tags.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-delivery-message-sarif-hard-limit-tags-per-rule.yml")
}

func TestDeliveryMessageSarifHardLimitRuns(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only find delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	// Then we produce the error
	session.Analyze(t, repoID, "./data/too-many-runs.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-delivery-message-sarif-hard-limit-runs.yml")
}

func TestDeliveryMessageSarifHardLimitThreadFlows(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only find delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	// Then we produce the error
	session.Analyze(t, repoID, "./data/tsp-too-many-thread-flows.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-delivery-message-sarif-hard-limit-thread-flows.yml")
}

func TestDeliveryMessageDefaultSetupRejectedUpload(t *testing.T) {
	var repoID uint64 = 351
	var workflowRunID ts.WorkflowRunEID = 5

	session := cassettes.NewSession(t)
	session.CreateRepository(t, ts.RepositoryEID(repoID), []byte("heads/refs/main"))

	// At the moment get-tool-status only finds delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	// The enablement statusService will emit a Sentry exception after offboarding because there is no entry for the repo in the repositories table.
	// It is ok to ignore that in this test
	session.DisableTestFailuresForEnablementStatusExceptions()

	// Now we enable default setup
	session.ReplayReadOnly(t, "code-scanning/managed-analyses-enable.yml")
	session.UpsertCodeqlRunStatus(t, ts.RepositoryEID(repoID), workflowRunID, ts.CodeqlRunStatus_COMPLETED)

	// Then we produce the error
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-delivery-message-default-setup-rejected-upload.yml")
}

func TestDeliveryMessageSarifHardLimitToolExtensions(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only finds delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	// Then we produce the error
	session.Analyze(t, repoID, "./data/too-many-extensions.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-delivery-message-sarif-hard-limit-tool-extensions.yml")
}

func TestDeliveryMessageSarifHardLimitResultsPerRun(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only finds delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	// Then we produce the error
	session.Analyze(t, repoID, "./data/too-many-results.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-delivery-message-sarif-hard-limit-results-per-run.yml")
}

func TestDeliveryMessageSarifHardLimitRulesPerRun(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	// At the moment get-tool-status only finds delivery errors after at least one analysis has been created.
	// So we first upload valid sarif.
	session.Analyze(t, repoID, "./data/empty.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	// Then we produce the error
	session.Analyze(t, repoID, "./data/too-many-rules.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-delivery-message-sarif-hard-limit-rules-per-run.yml")
}

func TestAnalysisMessageSarifSoftLimitTagsPerRule(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)
	session.Analyze(t, repoID, "./data/soft-limit-tags.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")
	session.Replay(t, "code-scanning/get-tool-status-analysis-message-sarif-soft-limit-tags-per-rule.yml")
}

func TestAnalysisMessageSarifSoftLimitRelatedLocations(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)
	session.Analyze(t, repoID, "./data/soft-limit-related-locations.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")
	session.Replay(t, "code-scanning/get-tool-status-analysis-message-sarif-soft-limit-related-locations.yml")
}

func TestAnalysisMessageSarifSoftLimitThreadFlows(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)
	session.Analyze(t, repoID, "./data/soft-limit-thread-flows.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")
	session.Replay(t, "code-scanning/get-tool-status-analysis-message-sarif-soft-limit-thread-flows.yml")
}

func TestAnalysisMessageSarifSoftLimitResultsPerRun(t *testing.T) {
	var repoID uint64 = 351
	session := cassettes.NewSession(t)

	session.Analyze(t, repoID, "./data/soft-limit-results.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-analysis-message-sarif-soft-limit-results-per-run.yml")
}

func TestDeliveryMessagesWithProcessedSARIF(t *testing.T) {
	var repositoryID uint64 = 351
	session := cassettes.NewSession(t)
	// A valid analysis with no warnings
	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-messages.yml")

	// A valid analysis with executionSuccessful False with a message and a ProcessError (due to CodeQL)
	session.Analyze(t, repositoryID, "./data/execution-failed.sarif", ".github/workflows/codeql.yml:CodeQL", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-messages-warning.yml")

	// A valid analysis with executionSuccessful False with message and no ProcessError (as it comes from another tool)
	session.Analyze(t, repositoryID, "./data/execution-failed-other-tool.sarif", ".github/workflows/codeql.yml:OtherTool", "refs/heads/master")

	session.Replay(t, "code-scanning/get-tool-status-messages-two-warnings.yml")

	// Analyses for those two tools with a different deliveryOrigin
	deliveryOriginOp := cassettes.WithDeliveryOrigin(ts.DeliveryOrigin_API)
	session.Analyze(t, repositoryID, "./data/7e084a1.sarif", "some-api-category", "refs/heads/master", deliveryOriginOp)
	session.Analyze(t, repositoryID, "./data/execution-failed.sarif", "different-api-category", "refs/heads/master", deliveryOriginOp)
	session.Analyze(t, repositoryID, "./data/execution-failed-other-tool.sarif", "other-tool-api", "refs/heads/master", deliveryOriginOp)
	session.Analyze(t, repositoryID, "./data/execution-failed-other-tool.sarif", "other-tool-api-2", "refs/heads/master", deliveryOriginOp)

	session.Replay(t, "code-scanning/get-tool-status-messages-two-tools-two-configuration-groups.yml")
}
