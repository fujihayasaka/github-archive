package deltaingest

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/types"
)

func Test_MaxBlobLocations(t *testing.T) {
	var tests = []struct {
		name     string
		repoID   types.RepoID
		numStars int32
		isPaying bool
		expected int
	}{
		{
			name:     "paying customer limit",
			repoID:   1,
			numStars: 0,
			isPaying: true,
			expected: 600_000,
		},
		{
			name:     "non-paying, non-important limit",
			repoID:   1,
			numStars: 0,
			isPaying: false,
			expected: 75_000,
		},
		{
			name:     "non-paying, important limit",
			repoID:   1,
			numStars: 5,
			isPaying: false,
			expected: 600_000,
		},
		{
			name:     "override limit",
			repoID:   6223686, // Canva/canva -- must be in the maxBlobLocationsOverrideRepos map.
			numStars: 0,
			isPaying: false,
			expected: 1_250_000,
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			require.Equal(t, test.expected, maxBlobLocations(test.repoID, test.numStars, test.isPaying))
		})
	}
}
