package flipper

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts"
)

// HasDemoFeatureFlag provides an example of a predicate to check a feature flag.
// Helper methods for checking feature flags should be defined in this package
// so that the rest of the codebase is decoupled from the FF API.
func HasDemoFeatureFlag(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID) bool {
	res, err := ffs.isOrgOrRepoEnabled(ctx, orgID, repoID, "code_scanning_demo_feature_flag")
	// See isRepoEnabled if you do not have (or care about) the Org.

	// While the underlying methods can return errors, in most cases we want
	// to hide this from the client and only return a true/false value.
	// Typically, we want to treat a failed request as a false value.
	return err == nil && res
}

const CodeScanningSuggestedFixAllQueries = "code_scanning_suggested_all_queries"

func HasSuggestedFixAllQueries(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, CodeScanningSuggestedFixAllQueries)
	return err == nil && res
}

const CodeScanningSkipAlertIndexing = "code_scanning_skip_alert_indexing"

func HasSkipAlertIndexing(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, CodeScanningSkipAlertIndexing)
	return err == nil && res
}

const CodeScanningCustomRunnerLabels = "code_scanning_custom_runner_labels"

func HasCodeScanningCustomRunnerLabels(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID) bool {
	res, err := ffs.isOrgOrRepoEnabled(ctx, orgID, repoID, CodeScanningCustomRunnerLabels)
	return err == nil && res
}

// HasOmitFilesNotExtracted allows us to slim down the extracted files response for problematic repositories
func HasOmitFilesNotExtracted(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, "code_scanning_omit_files_not_extracted")
	return err == nil && res
}

func HasLimitAlertFixes(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, "code_scanning_limit_alert_fixes")
	return err == nil && res
}

func HasNewLatestAnalysesByRef(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, "code_scanning_new_latest_analyses_by_ref")
	return err == nil && res
}

func StoreLimitAlertFixesInContext(ctx context.Context, repoID ts.RepositoryEID) context.Context {
	res, err := ffs.isRepoEnabled(ctx, repoID, "code_scanning_limit_alert_fixes")
	if err == nil && res {
		return WithFeatureEnabledFor(ctx, "code_scanning_limit_alert_fixes", repoID)
	}
	return WithFeatureDisabledFor(ctx, "code_scanning_limit_alert_fixes", repoID)
}

func HasSkipEmittingAlertEvents(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, "code_scanning_skip_emitting_alert_events")
	return err == nil && res
}

const CodeScanningPrivateRegistry = "private_registry_config_ui"

func HasCodeScanningPrivateRegistry(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID) bool {
	res, err := ffs.isOrgOrRepoEnabled(ctx, orgID, repoID, CodeScanningPrivateRegistry)
	return err == nil && res
}

const CodeScanningActionsYml = "code_scanning_actions_yml"

func HasCodeScanningActionsYml(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID) bool {
	res, err := ffs.isOrgOrRepoEnabled(ctx, orgID, repoID, CodeScanningActionsYml)
	return err == nil && res
}

func HasCodeScanningAutofixActionsWorkflow(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, "code_scanning_autofix_actions_workflow")
	return err == nil && res
}

const CodeScanninDataModelExperiment = "code_scanning_data_model_experiment"

func WithCodeScanninDataModelExperiment(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, CodeScanninDataModelExperiment)
	return err == nil && res
}

const DependabotAutofix = "dependabot_autofix"

func HasDependabotAutofix(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, DependabotAutofix)
	return err == nil && res
}

const CodeScanningAlertsAuditLog = "code_scanning_alerts_audit_log"

func HasCodeScanningAlertsAuditLog(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, CodeScanningAlertsAuditLog)
	return err == nil && res
}

// CodeScanningRerunCommitAnalysis controls whether default setup will skip running an analysis for a commit
// it has already seen.
// In general, we want to skip those commits as the result of the analysis is unlikely to change.
// However, while https://github.com/github/code-scanning/issues/12399 is open, we sometimes face race conditions
// that mean that we *think* we analyzed a given commit but we did not.
// Enabling this FF will force the commit to be analyzed again.
const CodeScanningRerunCommitAnalysis = "code_scanning_rerun_commit_analysis"

func HasCodeScanningRerunCommitAnalysis(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID) bool {
	res, err := ffs.isOrgOrRepoEnabled(ctx, orgID, repoID, CodeScanningRerunCommitAnalysis)
	return err == nil && res
}

const CodeScanningSparsePhysicalAlerts = "code_scanning_sparse_physical_alerts"

func HasCodeScanningSparsePhysicalAlerts(ctx context.Context, repoID ts.RepositoryEID) bool {
	if testing.Testing() {
		return true
	}
	res, err := ffs.isRepoEnabled(ctx, repoID, CodeScanningSparsePhysicalAlerts)
	return err == nil && res
}

const CodeScanningSkipCodeFlows = "code_scanning_stop_storing_code_flows"

func HasCodeScanningSkipCodeFlows(ctx context.Context, repoID ts.RepositoryEID) bool {
	if testing.Testing() {
		return true
	}
	res, err := ffs.isRepoEnabled(ctx, repoID, CodeScanningSkipCodeFlows)
	return err == nil && res
}

func HasCodeScanningNoDelayCodeqlRun(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, "code_scanning_no_delay_codeql_run")
	return err == nil && res
}
