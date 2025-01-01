package cocofix

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/flipper"
)

// IsEligibleForAutoFix returns true if the given alert is eligible for an autofix.
// This checks the tool and the rule of the alert against the rule coverages.
// Note: The rule and its tool is expected to be loaded on the alert.
func IsEligibleForAutoFix(ctx context.Context, repoID ts.RepositoryEID, alert *ts.LogicalAlert) bool {
	toolEnabled := ToolCoverageMap.IsSupported(tool(alert.Rule.Tool.CanonicalName))
	if !toolEnabled {
		return false
	}

	c, ok := ToolCoverageMap.FindCoverage(alert.Rule.Tool.CanonicalName.String(), alert.SarifIdentifier)

	if flipper.HasSuggestedFixIncludeCCRQuality(ctx, flipper.UnknownOrg, repoID) && c.IsCopilotCodeReviewSuite() {
		return ok
	}

	return ok && c.IsDefaultSuite()
}

// ShouldGenerateFixForRule returns true if we should generate a fix for the given alert.
// This checks the tool and the rule of the alert for eligibility and also checks
// whether we should generate a fix for all queries for the given repo based on a feature flag.
func ShouldGenerateFixForRule(ctx context.Context, repoID ts.RepositoryEID, alert *ts.LogicalAlert) bool {
	if flipper.HasSuggestedFixAllQueries(ctx, repoID) {
		return true
	}
	return IsEligibleForAutoFix(ctx, repoID, alert)
}
