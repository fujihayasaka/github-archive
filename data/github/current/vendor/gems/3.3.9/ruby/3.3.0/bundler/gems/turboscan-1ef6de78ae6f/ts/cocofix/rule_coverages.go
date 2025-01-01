package cocofix

import (
	"context"
	"strings"
	"sync"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/flipper"
)

type RuleCoverages map[string]map[string]bool

var (
	ruleCoveragesMap RuleCoverages
	initRuleCoverage sync.Once
)

func loadRuleCoverages() RuleCoverages {
	initRuleCoverage.Do(func() {
		var toolsCoverageMap = LoadToolCoverages()
		ruleCoveragesMap = make(RuleCoverages)
		for tool, languages := range toolsCoverageMap {
			rulesCoverageMap := make(map[string]bool)
			for _, rules := range languages {
				for _, rule := range rules {
					rulesCoverageMap[rule] = true
				}
			}

			ruleCoveragesMap[tool] = rulesCoverageMap
		}
	})
	return ruleCoveragesMap
}

// IsEligibleForAutoFix returns true if the given alert is eligible for an autofix.
// This checks the tool and the rule of the alert against the rule coverages.
// Note: The rule and its tool is expected to be loaded on the alert.
func IsEligibleForAutoFix(ctx context.Context, repoID ts.RepositoryEID, alert *ts.LogicalAlert) bool {
	tool := alert.Rule.Tool

	ruleCoverage := loadRuleCoverages()

	rules, toolEnabled := ruleCoverage[string(tool.CanonicalName)]

	if !toolEnabled {
		return false
	}

	_, ok := rules[alert.SarifIdentifier]

	// FF to control rollout of autofix for actions queries
	if ok && strings.HasPrefix(alert.SarifIdentifier, "actions/") {
		return flipper.HasCodeScanningAutofixActionsWorkflow(ctx, repoID)
	}

	return ok
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
