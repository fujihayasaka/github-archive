package flipper

import (
	"context"

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

const CodeQLActionCppBuildModeNone = "codeql_action_cpp_build_mode_none"

func HasCodeQLActionCppBuildModeNone(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID) bool {
	res, err := ffs.isOrgOrRepoEnabled(ctx, orgID, repoID, CodeQLActionCppBuildModeNone)
	return err == nil && res
}

const DependabotAutofix = "dependabot_autofix"

func HasDependabotAutofix(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, DependabotAutofix)
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

const CodeScanningSuggestedFixIncludesQuality = "code_scanning_suggested_include_quality"

func HasSuggestedFixIncludeCCRQuality(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID) bool {
	res, err := ffs.isOrgOrRepoEnabled(ctx, orgID, repoID, CodeScanningSuggestedFixIncludesQuality)
	return err == nil && res
}

const CodeScanningNewCampaignsEndpointStats = "code_scanning_new_campaigns_endpoint_stats"

func HasCodeScanningNewCampaignsEndpointStats(ctx context.Context, orgID ts.OwnerEID) bool {
	res, err := ffs.isOrgEnabled(ctx, orgID, CodeScanningNewCampaignsEndpointStats)
	return err == nil && res
}

const CodeScanningUbuntu2204Runner = "code_scanning_ubuntu2204_runner"

func HasCodeScanningUbuntu2204Runner(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID) bool {
	res, err := ffs.isOrgOrRepoEnabled(ctx, orgID, repoID, CodeScanningUbuntu2204Runner)
	return err == nil && res
}

const CodeScanningSkipOffboardingOnMissingServices = "code_scanning_skip_offboarding_on_missing_services"

func SkipOffboardingOnMissingServices(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID) bool {
	res, err := ffs.isOrgOrRepoEnabled(ctx, orgID, repoID, CodeScanningSkipOffboardingOnMissingServices)
	return err == nil && res
}

const CodeScanningListenToComputeUsage = "code_scanning_listen_to_compute_usage"

func HasCodeScanningListenToComputeUsage(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID) bool {
	res, err := ffs.isOrgOrRepoEnabled(ctx, orgID, repoID, CodeScanningListenToComputeUsage)
	return err == nil && res
}

const CodeScanningCountsExperiment = "code_scanning_counts_experiment"

func WithCodeScanningCountsExperiment(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, CodeScanningCountsExperiment)
	return err == nil && res
}
