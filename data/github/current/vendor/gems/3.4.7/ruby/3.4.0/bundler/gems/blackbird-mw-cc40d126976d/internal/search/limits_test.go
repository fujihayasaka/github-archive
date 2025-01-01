package search

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/blackbird/crates/core/pkg/limits"
	"github.com/stretchr/testify/require"
)

func TestUserQueryLimits(t *testing.T) {
	var tests = []struct {
		name     string
		docs     uint32
		locs     uint32
		shards   int
		expected QueryLimits
	}{
		// Most user queries look like this
		{
			docs:   100,
			locs:   10,
			shards: 32,
			expected: QueryLimits{
				RequestedDocs:  100,
				RequestedLocs:  10,
				LocationsLimit: 10,
				ToRetrieve:     2700,
				ToScore:        27,
				ToReturn:       27,
				WithContent:    9,
				TermMatchLimit: defaultTermMatchLimit,
			},
		},
		// User query with slightly different limits and shard count for testing
		{
			docs:   20,
			locs:   10,
			shards: 8,
			expected: QueryLimits{
				RequestedDocs:  20,
				RequestedLocs:  10,
				LocationsLimit: 10,
				ToRetrieve:     2100,
				ToScore:        21,
				ToReturn:       20,
				WithContent:    7,
				TermMatchLimit: defaultTermMatchLimit,
			},
		},
		// Suggest queries
		{
			docs:   5,
			locs:   5,
			shards: 32,
			expected: QueryLimits{
				RequestedDocs:  5,
				RequestedLocs:  5,
				LocationsLimit: 5,
				ToRetrieve:     600,
				ToScore:        6,
				ToReturn:       5,
				WithContent:    2,
				TermMatchLimit: defaultTermMatchLimit,
			},
		},
		{
			docs:   10,
			locs:   5,
			shards: 32,
			expected: QueryLimits{
				RequestedDocs:  10,
				RequestedLocs:  5,
				LocationsLimit: 5,
				ToRetrieve:     900,
				ToScore:        9,
				ToReturn:       9,
				WithContent:    3,
				TermMatchLimit: defaultTermMatchLimit,
			},
		},
		{
			docs:   1,
			locs:   1,
			shards: 32,
			expected: QueryLimits{
				RequestedDocs:  1,
				RequestedLocs:  1,
				LocationsLimit: 5,
				ToRetrieve:     300,
				ToScore:        3,
				ToReturn:       1,
				WithContent:    1,
				TermMatchLimit: defaultTermMatchLimit,
			},
		},
	}

	for _, test := range tests {
		testName := fmt.Sprintf("%d docs %d locs %d shards", test.docs, test.locs, test.shards)
		t.Run(testName, func(t *testing.T) {
			calc := NewLimitsCalculator()
			actual := calc.Calculate(context.Background(), test.shards, test.docs, test.locs)

			require.Equal(t, test.expected, actual)
		})
	}
}

// NOTE: This can be used to prefill the cache.
func Test_Calculate(t *testing.T) {
	n := limits.CalcLikelyDocsPerShard(.95, 100, 32)
	require.EqualValues(t, 9, n)
	n = limits.CalcLikelyDocsPerShard(.99, 100, 32)
	require.EqualValues(t, 10, n)
}
