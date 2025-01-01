package gormbulk

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestExecInChunksSmaller(t *testing.T) {
	ctx := context.Background()
	expectIndex := 0
	expect := []func(chunk []int){
		func(chunk []int) {
			require.Equal(t, []int{1, 2}, chunk)
		},
		func(chunk []int) {
			require.Equal(t, []int{3}, chunk)
		},
	}
	err := execInChunks(ctx, []int{1, 2, 3}, 2, func(chunk []int) error {
		expect[expectIndex](chunk)
		expectIndex += 1

		return nil
	})
	require.NoError(t, err)
	require.Equal(t, 2, expectIndex)
}

func TestExecInChunksLarger(t *testing.T) {
	ctx := context.Background()
	expectIndex := 0
	expect := []func(chunk []int){
		func(chunk []int) {
			require.Equal(t, []int{1, 2, 3}, chunk)
		},
	}
	err := execInChunks(ctx, []int{1, 2, 3}, 5, func(chunk []int) error {
		expect[expectIndex](chunk)
		expectIndex += 1

		return nil
	})
	require.NoError(t, err)
	require.Equal(t, 1, expectIndex)
}

func TestExecInChunksEqual(t *testing.T) {
	ctx := context.Background()
	expectIndex := 0
	expect := []func(chunk []int){
		func(chunk []int) {
			require.Equal(t, []int{1, 2, 3}, chunk)
		},
	}
	err := execInChunks(ctx, []int{1, 2, 3}, 3, func(chunk []int) error {
		expect[expectIndex](chunk)
		expectIndex += 1

		return nil
	})
	require.NoError(t, err)
	require.Equal(t, 1, expectIndex)
}

func TestExecInChunksEmpty(t *testing.T) {
	ctx := context.Background()
	expectIndex := 0
	err := execInChunks(ctx, []int{}, 3, func(chunk []int) error {
		expectIndex += 1

		return nil
	})
	require.NoError(t, err)
	require.Equal(t, 0, expectIndex)
}
