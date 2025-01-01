package flipper

import (
	"context"

	"github.com/github/turboscan/ts"
)

//
// This file contains long lived Feature Flags.
// For short-lived flags (the majority) use flags.go
//

const CodeScanningConfigWorkflowNext = "code_scanning_workflow_upgrade_next"

func HasWorkflowUpgradeNextVersion(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, CodeScanningConfigWorkflowNext)
	return err == nil && res
}

const CodeScanningDefaultSetupCodeqlRC = "code_scanning_default_setup_codeql_rc"

// HasCodeScanningDefaultSetupCodeqlRC checks whether the repository should be using the
// release candidate branch of the codeql-action when using Default Setup.
func HasCodeScanningDefaultSetupCodeqlRC(ctx context.Context, repoID ts.RepositoryEID) bool {
	res, err := ffs.isRepoEnabled(ctx, repoID, CodeScanningDefaultSetupCodeqlRC)
	return err == nil && res
}

func HasProcessorDisabled(ctx context.Context, processorName string) bool {
	feature := "turboscan-" + processorName + "-paused"
	// This flag is either absent or set globally; repo/org is not relevant
	res, err := ffs.checkActorFeature(ctx, "", feature)
	if err != nil {
		// If there was an error retrieving pause information, we assume "not paused"
		// If an error led to stream processor being paused, that could introduce availability
		// problems just to support the very rare action of pausing. And since you'd only be
		// pausing a stream processor if you were investigating an incident anyway, a problem
		// in that situation is more easily spotted.
		return false
	}

	return res
}

func HasEmitRunAnnotationsForSteadyState(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID) bool {
	res, err := ffs.isOrgOrRepoEnabled(ctx, orgID, repoID, "code_scanning_emit_run_annotations_for_steady_state")
	return err == nil && res
}

func HasSkipRunStatsReporting(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID) bool {
	res, err := ffs.isOrgOrRepoEnabled(ctx, orgID, repoID, "code_scanning_default_setup_skip_run_stats_reporting")
	return err == nil && res
}
