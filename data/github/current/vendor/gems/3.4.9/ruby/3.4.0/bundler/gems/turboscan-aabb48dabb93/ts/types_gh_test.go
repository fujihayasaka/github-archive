package ts_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
)

func TestRepositoryNWO_HasOwner(t *testing.T) {
	require.True(t, ts.ToRepositoryNWO("owner/repo").HasOwner("owner"))
	require.False(t, ts.ToRepositoryNWO("owner/repo").HasOwner("potato"))
	require.False(t, ts.ToRepositoryNWO("owner_repo").HasOwner("owner"))
}

func TestEmptyCheckoutURI_Comparison(t *testing.T) {
	require.True(t, "" == ts.EmptyCheckoutURI)
}

func TestTruncateWorkflowPath(t *testing.T) {
	// Because we are doing something a bit different for this truncation
	// we add an explicit test for it.

	// Create a byte slice that is 1025 bytes long
	longPath := make([]byte, 1025)
	for i := 0; i < len(longPath); i++ {
		longPath[i] = byte(i % 256)
	}

	truncatedPath := ts.ToWorkflowPath(longPath)
	require.Equal(t, 1024, len(truncatedPath))
	require.EqualValues(t, longPath[0:1024], truncatedPath)

	// Create a byte slice with fewer than 10 bytes
	shortPath := make([]byte, 9)
	for i := 0; i < len(shortPath); i++ {
		shortPath[i] = byte(i % 256)
	}

	truncatedPath = ts.ToWorkflowPath(shortPath)
	require.Equal(t, 9, len(truncatedPath))
	require.EqualValues(t, shortPath, truncatedPath)
}
