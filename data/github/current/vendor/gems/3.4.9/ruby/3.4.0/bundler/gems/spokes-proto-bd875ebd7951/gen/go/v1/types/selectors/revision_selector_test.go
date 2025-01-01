package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

var (
	nilSelector *types.Revision
	headRev     = types.NewRevision([]byte("HEAD"))
	defunktRev  = types.NewRevision([]byte("defunkt/cool-new-feature"))
	notRev      = types.NewRevision([]byte("^origin"))
	emptyRev    = types.NewRevision([]byte{})
	nilRev      = types.NewRevision(nil)
)

func TestNewRevisionSelector(t *testing.T) {
	expected := &RevisionSelector{
		Revisions: []*types.Revision{
			headRev,
			defunktRev,
			notRev,
		},
	}
	got := NewRevisionSelector(headRev, defunktRev, notRev)

	require.Equal(t, expected, got)
}

func TestRevisionSelectorValidateError(t *testing.T) {
	var tests = []struct {
		name string
		rs   *RevisionSelector
		err  string
	}{
		{
			"revisions field unpopulated",
			&RevisionSelector{},
			"twirp error invalid_argument: revisions is required",
		},
		{
			"empty revision.name",
			NewRevisionSelector(emptyRev),
			"twirp error invalid_argument: revision.name is required",
		},
		{
			"nil revision.name",
			NewRevisionSelector(nilRev),
			"twirp error invalid_argument: revision.name is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.rs.Validate(), tt.err)
		})
	}
}

func TestRevisionSelectorValidate(t *testing.T) {
	require.NoError(t, nilSelector.Validate())

	validSelector := NewRevisionSelector(headRev)
	require.NoError(t, validSelector.Validate())
}
