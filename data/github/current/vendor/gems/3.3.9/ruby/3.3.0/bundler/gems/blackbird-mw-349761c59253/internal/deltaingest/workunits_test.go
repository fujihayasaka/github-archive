package deltaingest

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"golang.org/x/sync/semaphore"
)

const numWorkers = 32

func Test_Acquire(t *testing.T) {
	ctx := context.Background()
	tests := []struct {
		name          string
		numWorkers    int64
		diffSize      int
		expectedUnits int64
	}{
		{name: "XS", numWorkers: numWorkers, diffSize: 1, expectedUnits: 1},
		{name: "Last XS", numWorkers: numWorkers, diffSize: 100, expectedUnits: 1},
		{name: "S", numWorkers: numWorkers, diffSize: 101, expectedUnits: 2},
		{name: "Last S", numWorkers: numWorkers, diffSize: 1000, expectedUnits: 2},
		{name: "M", numWorkers: numWorkers, diffSize: 1001, expectedUnits: 4},
		{name: "Last M", numWorkers: numWorkers, diffSize: 10_000, expectedUnits: 4},
		{name: "L", numWorkers: numWorkers, diffSize: 10_001, expectedUnits: 8},

		{name: "L with fewer workers", numWorkers: 16, diffSize: 10_001, expectedUnits: 8},
		{name: "L with fewer odd workers", numWorkers: 9, diffSize: 10_001, expectedUnits: 8},
		{name: "L with even fewer workers", numWorkers: 8, diffSize: 10_001, expectedUnits: 8},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			sem := semaphore.NewWeighted(test.numWorkers)
			n, release, err := acquireWorkUnits(ctx, test.numWorkers, sem, test.diffSize)
			defer release()
			require.NoError(t, err)
			require.EqualValues(t, test.expectedUnits, n)
		})
	}
}

func Test_AcquireTooFewWorkers(t *testing.T) {
	ctx := context.Background()
	numWorkers := int64(1)
	sem := semaphore.NewWeighted(numWorkers)
	n, _, err := acquireWorkUnits(ctx, numWorkers, sem, 10_000)
	require.NoError(t, err)
	require.EqualValues(t, 1, n)
}
