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

func TestCopilotCodeReviewSuite(t *testing.T) {
	c, ok := ToolCoverageMap.FindCoverage("CodeQL", "js/useless-expression")
	require.True(t, ok, "Rule does not exist in the rule coverage")
	require.True(t, c.IsCopilotCodeReviewSuite(), "Rule is not a CCR rule")

	_, ok = ToolCoverageMap.FindCoverage("CodeQL", "js/useless-expression2")
	require.False(t, ok)
}
