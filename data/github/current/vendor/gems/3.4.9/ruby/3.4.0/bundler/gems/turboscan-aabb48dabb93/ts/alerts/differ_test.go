package alerts

import (
	"testing"

	"github.com/github/turboscan/ts"

	"github.com/stretchr/testify/require"
)

func TestCompareAlerts(t *testing.T) {

	before := []*ts.PhysicalAlert{
		{
			ID:             1,
			LogicalAlertID: 1,
		},
		{
			ID:             2,
			LogicalAlertID: 2,
		},
	}

	after := []*ts.PhysicalAlert{
		{
			ID:             3,
			LogicalAlertID: 1,
		},
		{
			ID:             4,
			LogicalAlertID: 3,
		},
	}

	diff := compareAlerts(before, after)
	require.Equal(t, 1, len(diff.Added))
	require.Equal(t, after[1], diff.Added[0])
	require.Equal(t, 1, len(diff.Removed))
	require.Equal(t, before[1], diff.Removed[0])

	require.Equal(t, len(diff.Added), len(diff.AddedIDs))
	for _, p := range diff.Added {
		require.True(t, diff.AddedIDs[p.LogicalAlertID])
	}
	require.Equal(t, len(diff.Removed), len(diff.RemovedIDs))
	for _, p := range diff.Removed {
		require.True(t, diff.RemovedIDs[p.LogicalAlertID])
	}
}
