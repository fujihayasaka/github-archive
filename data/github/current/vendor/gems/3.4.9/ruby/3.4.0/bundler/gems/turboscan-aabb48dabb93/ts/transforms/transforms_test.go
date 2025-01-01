package transforms_test

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts/transforms"
)

func TestFlatten(t *testing.T) {
	require.Equal(t, transforms.Flatten([][]int{{1, 2}, {3}}), []int{1, 2, 3})
	v := transforms.Flatten([]json.RawMessage{
		json.RawMessage("moose"),
		json.RawMessage("goose"),
		json.RawMessage("spruce"),
	})
	require.IsType(t, json.RawMessage(""), v)
	require.Equal(t, json.RawMessage("moosegoosespruce"), v)
}

func TestBatchMap(t *testing.T) {
	input := []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
	output := [][]int{{2, 3}, {4, 5}, {6, 7}, {8, 9}, {10, 11}}
	require.Equal(t, transforms.BatchMap(input, 2, func(i int) int { return i + 1 }), output)
}
