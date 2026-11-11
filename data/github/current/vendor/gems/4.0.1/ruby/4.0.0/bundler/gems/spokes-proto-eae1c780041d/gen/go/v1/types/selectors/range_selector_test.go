package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

var (
	start = types.NewReference([]byte("refs/heads/main"))
	end   = types.NewReference([]byte("refs/heads/new-branch"))
	paths = []*types.Path{types.NewPath([]byte("path"))}

	treeishStart = types.NewTreeishWithReference(start)
	treeishEnd   = types.NewTreeishWithReference(end)
)

func TestNewRangeSelector(t *testing.T) {
	rs := NewRangeSelector(treeishStart, treeishEnd, paths)
	require.Equal(t, &RangeSelector{Start: treeishStart, End: treeishEnd, Paths: paths}, rs)
}

func TestRangeSelectorValidateError(t *testing.T) {
	var tests = []struct {
		name string
		rs   *RangeSelector
		err  string
	}{
		{
			"empty",
			&RangeSelector{},
			"twirp error invalid_argument: start is required",
		},
		{
			"missing end",
			NewRangeSelector(treeishStart, nil, nil),
			"twirp error invalid_argument: end is required",
		},
		{
			"invalid start",
			NewRangeSelector(&types.Treeish{}, treeishEnd, nil),
			"twirp error invalid_argument: treeish is required",
		},
		{
			"invalid end",
			NewRangeSelector(treeishStart, &types.Treeish{}, nil),
			"twirp error invalid_argument: treeish is required",
		},
		{
			"invalid paths",
			NewRangeSelector(treeishStart, treeishEnd, []*types.Path{types.NewPath([]byte(""))}),
			"twirp error invalid_argument: path.name is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.rs.Validate(), tt.err)
		})
	}
}

func TestRangeSelectorValidate(t *testing.T) {
	var nilSelector *RangeSelector
	require.NoError(t, nilSelector.Validate())

	validSelector := NewRangeSelector(treeishStart, treeishEnd, paths)
	require.NoError(t, validSelector.Validate())
}
