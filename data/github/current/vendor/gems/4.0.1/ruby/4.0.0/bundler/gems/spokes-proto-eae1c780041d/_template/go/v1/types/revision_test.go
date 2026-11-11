package types

import (
	"testing"

	"github.com/stretchr/testify/require"
)

var (
	mainRev = []byte("main@2.days.ago")
)

func TestNewRevision(t *testing.T) {
	r := NewRevision(mainRev)
	require.Equal(t, &Revision{Name: mainRev}, r)
}

func TestRevisionValidate(t *testing.T) {
	var nilRev *Revision
	require.NoError(t, nilRev.Validate())

	emptyRev := NewRevision(nil)
	require.EqualError(t, emptyRev.Validate(), "twirp error invalid_argument: revision.name is required")

	rev := NewRevision(mainRev)
	require.NoError(t, rev.Validate())
}
