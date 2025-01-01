package db

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_SetEpochOffsets(t *testing.T) {
	offsets := EpochOffsets{}
	offsets.Set(1, 1)
	offsets.Set(1, 2)
	offsets.Set(1, 1)
	offsets.Set(2, 100)
	offsets.Set(2, 10)
	offsets.Set(3, 3)
	require.Equal(t, int64(2), offsets[1])
	require.Equal(t, int64(100), offsets[2])
	require.Equal(t, int64(3), offsets[3])
}

func Test_MergeEpochOffsets(t *testing.T) {
	offsets := EpochOffsets{1: 1, 2: 2, 3: 4}
	offsets.Merge(EpochOffsets{1: 2, 2: 2, 3: 1})

	require.Equal(t, int64(2), offsets[1])
	require.Equal(t, int64(2), offsets[2])
	require.Equal(t, int64(4), offsets[3])
}
