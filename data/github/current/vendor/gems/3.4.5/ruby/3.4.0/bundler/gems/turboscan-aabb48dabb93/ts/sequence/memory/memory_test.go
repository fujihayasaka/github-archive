package memory

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestMemorySequence(t *testing.T) {
	ctx := context.Background()

	seq := MemorySequence{}
	var n uint32
	n, _ = seq.Next(ctx)
	require.Equal(t, uint32(1), n)
	n, _ = seq.Next(ctx)
	require.Equal(t, uint32(2), n)
	n, _ = seq.Next(ctx)
	require.Equal(t, uint32(3), n)
	n, _ = seq.Incr(ctx, 6)
	require.Equal(t, uint32(4), n)
	n, _ = seq.Incr(ctx, 3)
	require.Equal(t, uint32(10), n)
}
