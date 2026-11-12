package routing

import (
	"slices"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_ProximaStampSorting(t *testing.T) {
	stamps := ProximaStamps
	require.Equal(t, StaffWUS201, stamps[0], "staff ship stamp should be first")
	require.True(t, slices.IsSorted(stamps[1:]), "non-staff ship proxima stamps should be sorted")
}
