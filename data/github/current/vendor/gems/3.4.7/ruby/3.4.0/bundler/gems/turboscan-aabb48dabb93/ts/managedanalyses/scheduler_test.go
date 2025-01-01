package managedanalyses_test

import (
	"testing"
	"time"

	"github.com/github/turboscan/ts/managedanalyses"
	"github.com/stretchr/testify/require"
)

func TestGetRandomScheduleTime(t *testing.T) {
	counter := 0
	rangeInt := func(maxVal int) int {
		counter++
		if counter > maxVal {
			counter = 0
		}
		return counter
	}

	s := managedanalyses.NewDeterministicScheduler(true, rangeInt)
	for i := 1; i < (60*24 + 1); i++ {
		res := s.GetRandomScheduleTime()
		// The schedule must be in the future but within 1 week.
		require.True(t, res.After(time.Now()))
		require.True(t, res.Before(time.Now().AddDate(0, 0, 7)))
		// Never schedule between 00-03 AM UTC
		require.True(t, res.UTC().Hour() >= 3)
	}
}
func TestGetRandomScheduleTime_IncludeMidnight(t *testing.T) {
	oneAM := func(_ int) int {
		return 1 * 60
	}
	s := managedanalyses.NewDeterministicScheduler(false, oneAM)
	res := s.GetRandomScheduleTime()
	require.Equal(t, 1, res.UTC().Hour())
}

func TestGetNextScheduleTime(t *testing.T) {
	times := []time.Time{time.Now().AddDate(0, -3, 0), time.Now().AddDate(0, 0, -5), time.Now().AddDate(0, 0, 5)}

	for _, current := range times {
		res := managedanalyses.GetNextScheduleTime(current)
		require.True(t, res.After(time.Now()))
		require.True(t, res.Before(time.Now().AddDate(0, 0, 7)))
	}
}
