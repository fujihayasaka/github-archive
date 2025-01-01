package limits_test

import (
	"testing"

	"github.com/github/turboscan/ts"

	"github.com/github/turboscan/ts/limits"

	"github.com/stretchr/testify/require"
)

func TestNoOverrides(t *testing.T) {
	lt := limits.NewLimitSelector(nil, false).GetLimits(1)
	require.Equal(t, 20, lt.RunsPerSarifLimit)
	require.Equal(t, 5000, lt.RulesPerRunLimit)
	require.Equal(t, 5000, lt.ResPerRunLimit)
	require.Equal(t, 100, lt.ToolExtensionsPerRunLimit)
	require.Equal(t, 100, lt.LocPerResLimit)
	require.Equal(t, 1000, lt.StepsPerResLimit)
	require.Equal(t, 5000, lt.MetricsPerRunLimit)
	require.Equal(t, 10, lt.TagsPerRuleLimit)
	require.Equal(t, 5000, lt.NotExtractedFilesMessagesLimit)
}

func TestOverrides(t *testing.T) {
	lt := limits.NewLimitSelector(map[ts.RepositoryEID]limits.Table{
		1: limits.LimitsHuge(),
	}, false).GetLimits(1)

	require.Equal(t, 20, lt.RunsPerSarifLimit)
	require.Equal(t, 10000, lt.RulesPerRunLimit)
}

func TestOverrideDefault(t *testing.T) {
	lt := limits.NewLimitSelector(map[ts.RepositoryEID]limits.Table{
		// 0 is used as a fallback value.
		0: limits.LimitsHuge(),
	}, false).GetLimits(1)

	require.Equal(t, 20, lt.RunsPerSarifLimit)
	require.Equal(t, 10000, lt.RulesPerRunLimit)
}

func TestHardLimits(t *testing.T) {
	lt, enabled := limits.NewLimitSelector(nil, false).GetHardLimits(1)
	require.True(t, enabled)
	require.Equal(t, 20, lt.RunsPerSarifLimit)
	require.Equal(t, 25000, lt.RulesPerRunLimit)
	require.Equal(t, 25000, lt.ResPerRunLimit)
	require.Equal(t, 100, lt.ToolExtensionsPerRunLimit)
	require.Equal(t, 1000, lt.LocPerResLimit)
	require.Equal(t, 10000, lt.StepsPerResLimit)
	require.Equal(t, 20, lt.TagsPerRuleLimit)
}
