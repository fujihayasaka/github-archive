package stats

import (
	"testing"
	time "time"

	"github.com/benbjohnson/clock"
	"github.com/github/go-stats"
	stats_mock "github.com/github/go-stats/mocks"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestTrackTimeToSentSuccess(t *testing.T) {
	testCases := []struct {
		latencyValue   time.Duration
		expectedBucket string
	}{
		{
			latencyValue:   time.Microsecond,
			expectedBucket: "0s-1s",
		},
		{
			latencyValue:   3 * time.Second,
			expectedBucket: "1s-5s",
		},
		{
			latencyValue:   10 * time.Second,
			expectedBucket: "5s-30s",
		},
		{
			latencyValue:   40 * time.Second,
			expectedBucket: "30s-1m",
		},
		{
			latencyValue:   2 * time.Minute,
			expectedBucket: "1m-3m",
		},
		{
			latencyValue:   4 * time.Minute,
			expectedBucket: "3m-5m",
		},
		{
			latencyValue:   8 * time.Minute,
			expectedBucket: "5m-10m",
		},
		{
			latencyValue:   1 * time.Hour,
			expectedBucket: "10m-plus",
		},
	}

	for _, test := range testCases {
		t.Run(test.expectedBucket, func(t *testing.T) {
			r := require.New(t)

			statter := stats_mock.NewClient(t)
			statter.On("DistributionMs", "delivery.time_to_sent", stats.Tags{"bucket": test.expectedBucket}, mock.Anything)

			clock := clock.NewMock()
			err := TrackTimeToSent(clock, statter, clock.Now().Add(-test.latencyValue))

			r.NoError(err)
		})
	}
}

func TestTrackTimeToSentError(t *testing.T) {
	t.Run("failure", func(t *testing.T) {
		r := require.New(t)

		statter := new(stats_mock.Client)
		statter.AssertNotCalled(t, "DistributionMs")

		var triggeredAt time.Time

		err := TrackTimeToSent(clock.NewMock(), statter, triggeredAt)
		r.ErrorIs(err, errDeliveryTimeIsZero)
	})
}
