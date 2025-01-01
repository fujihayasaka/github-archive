package deltaingest

import (
	"context"

	"golang.org/x/sync/semaphore"
)

// Blocks waiting to acquire a calculated number of work units from the weighted
// semaphore. These units are proportional to the size of the diff which is a
// proxy for the amount of crawling work to do.
//
//   - numWorkers must be at least 8 and a power of 2.
//   - sem is the weighted semaphore to acquire from. If nil, no lock will be
//     acquired.
//   - diffSize is the number of diff entries.
//
// Returns the number of work units acquired and a function to release them or
// an error.
//
// Panics if numWorkers is less than 8.
func acquireWorkUnits(ctx context.Context, numWorkers int64, sem *semaphore.Weighted, diffSize int) (int64, func(), error) {
	if sem == nil {
		return 0, func() {}, nil
	}

	// NB: Examples are given for numWorkers = 64.
	workUnits := int64(1) // XS: Each task = 1 unit (e.g. use all 64 workers)
	switch {
	case diffSize > 100_000:
		workUnits = 32 // L: Each task = 32 units (e.g. use 2 workers)
	case diffSize > 10_000:
		workUnits = 8 // L: Each task = 8 units (e.g. use 8 workers)
	case diffSize > 1_000:
		workUnits = 4 // M: Each task = 4 units (e.g. use 16 workers)
	case diffSize > 100:
		workUnits = 2 // S: Each task = 2 units (e.g. use 32 workers)
	}

	if workUnits > numWorkers {
		workUnits = numWorkers
	}

	// Acquire the appropriate work units from the weighted semaphore before
	// proceeding.
	if err := sem.Acquire(ctx, workUnits); err != nil {
		return workUnits, nil, err
	}

	return workUnits, func() { sem.Release(workUnits) }, nil
}
