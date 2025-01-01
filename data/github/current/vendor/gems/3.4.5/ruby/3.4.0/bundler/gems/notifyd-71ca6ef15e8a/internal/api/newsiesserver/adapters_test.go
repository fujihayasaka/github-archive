package newsiesserver

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/api/newsiesservice"
	pb "github.com/github/notifyd/proto/services/newsies"
)

func Test_threadTypesAdapter(t *testing.T) {
	r := require.New(t)

	t.Run("for unknown thread types", func(t *testing.T) {
		types := []pb.ThreadTypes{
			// We use a negative number here so that we are sure we are never going to have the real value
			// of one of the enum values as the yare always positive.
			pb.ThreadTypes(-1),
		}

		_, err := threadTypesAdapter(types)
		r.ErrorIs(err, ErrUnknownThreadType)
	})

	cases := []struct {
		given  pb.ThreadTypes
		wanted newsiesservice.ThreadType
	}{
		{given: pb.ThreadTypes_ISSUE, wanted: newsiesservice.Issue},
		{given: pb.ThreadTypes_DISCUSSION, wanted: newsiesservice.Discussion},
		{given: pb.ThreadTypes_SECURITY_ALERT, wanted: newsiesservice.SecurityAlert},
		{given: pb.ThreadTypes_RELEASE, wanted: newsiesservice.Release},
		{given: pb.ThreadTypes_PULL_REQUEST, wanted: newsiesservice.PullRequest},
	}

	for _, test := range cases {
		t.Run(test.given.String(), func(t *testing.T) {
			got, err := threadTypesAdapter([]pb.ThreadTypes{test.given})

			r.NoError(err)
			r.Equal([]newsiesservice.ThreadType{test.wanted}, got)
		})
	}
}
