package cocofix

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/flipper"
	"github.com/stretchr/testify/require"
)

func TestShouldGenerateFixForRule_SupportedRule(t *testing.T) {
	ctx := context.Background()

	repoID := ts.RepositoryEID(351)
	result := ShouldGenerateFixForRule(ctx, repoID, mockLogicalAlert("rb/unsafe-code-construction", "CodeQL"))

	require.True(t, result)
}

func TestShouldGenerateFixForRule_UnsupportedRule(t *testing.T) {
	ctx := context.Background()

	repoID := ts.RepositoryEID(351)
	result := ShouldGenerateFixForRule(ctx, repoID, mockLogicalAlert("foo/bar", "CodeQL"))

	require.False(t, result)
}

func TestShouldGenerateFixForRule_ThirdPartyTool(t *testing.T) {
	ctx := context.Background()

	repoID := ts.RepositoryEID(351)
	result := ShouldGenerateFixForRule(ctx, repoID, mockLogicalAlert("constructor-super", "ESLint"))

	require.True(t, result)
}

func TestShouldGenerateFixForRule_RuleToolMismatch(t *testing.T) {
	ctx := context.Background()

	repoID := ts.RepositoryEID(351)
	// rb/unsafe-code-construction is a valid rule but only for CodeQL
	result := ShouldGenerateFixForRule(ctx, repoID, mockLogicalAlert("rb/unsafe-code-construction", "ESLint"))

	require.False(t, result)
}

func TestShouldGenerateFixForRule_UnsupportedTool(t *testing.T) {
	ctx := context.Background()

	repoID := ts.RepositoryEID(351)
	result := ShouldGenerateFixForRule(ctx, repoID, mockLogicalAlert("rb/unsafe-code-construction", "otherTool"))

	require.False(t, result)
}

func TestShouldGenerateFixForRule_WhenFeatureIsDisabled_UnsupportedRule(t *testing.T) {
	ctx := context.Background()
	ctx = flipper.WithFeatureDisabled(ctx, flipper.CodeScanningSuggestedFixAllQueries)

	repoID := ts.RepositoryEID(351)
	result := ShouldGenerateFixForRule(ctx, repoID, mockLogicalAlert("rb/not-supported-rule", "CodeQL"))

	require.False(t, result)
}

func TestShouldGenerateFixForRule_WhenFeatureIsEnabled_UnsupportedRule(t *testing.T) {
	ctx := context.Background()
	ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningSuggestedFixAllQueries)

	repoID := ts.RepositoryEID(351)
	result := ShouldGenerateFixForRule(ctx, repoID, mockLogicalAlert("rb/not-supported-rule", "CodeQL"))

	require.True(t, result)
}

func TestShouldGenerateFixForRule_WhenFeatureIsDisabled_ActionsQueries(t *testing.T) {
	ctx := context.Background()
	ctx = flipper.WithFeatureDisabled(ctx, "code_scanning_autofix_actions_workflow")

	repoID := ts.RepositoryEID(351)
	result := ShouldGenerateFixForRule(ctx, repoID, mockLogicalAlert("actions/code-injection/critical", "CodeQL"))

	require.False(t, result)
}

func TestShouldGenerateFixForRule_WhenFeatureIsEnabled_ActionsQueries(t *testing.T) {
	// Since actions support has not been merged yet, we should only run the code part
	// of the test if the rule we're trying to use actually exists in the rule coverage.
	_, ruleExists := loadRuleCoverages()["CodeQL"]["actions/code-injection/critical"]

	if !ruleExists {
		t.Skip("Rule does not exist in the rule coverage")
	}

	ctx := context.Background()
	ctx = flipper.WithFeatureEnabled(ctx, "code_scanning_autofix_actions_workflow")

	repoID := ts.RepositoryEID(351)
	result := ShouldGenerateFixForRule(ctx, repoID, mockLogicalAlert("actions/code-injection/critical", "CodeQL"))

	require.True(t, ruleExists, result)
}
