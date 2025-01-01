package timing

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func Test_Timings(t *testing.T) {
	start := time.Now()
	ctx := context.Background()
	ctx = Start(ctx)

	Record(ctx, QueryStepRanQuery, start)
	qt := Finish(ctx)

	require.Equal(t, 1, len(qt.Timings))
	require.Equal(t, QueryStepRanQuery, qt.Timings[0].Key)
	require.Greater(t, qt.Timings[0].Duration, time.Duration(0))
	require.Greater(t, qt.TotalDuration(), time.Duration(0))
}

func Test_TimingsNoop(t *testing.T) {
	start := time.Now()
	ctx := context.Background()

	Record(ctx, QueryStepRanQuery, start)
	qt := Finish(ctx)

	// Nothing in the context so timings are just nil
	require.Nil(t, qt)
}
