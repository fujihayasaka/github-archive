package github

import (
	"testing"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"

	terrors "github.com/github/launch/types/errors"
)

func TestConvertGraphQLError(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want func(error) bool
	}{
		{
			name: "Forbidden - Resource not accessible",
			err:  errors.New("Resource not accessible by integration"),
			want: terrors.IsForbiddenError,
		},
		{
			name: "Not Found - commit not found",
			err:  errors.New("No commit found for SHA: f340c7fadcbb574f2697b27d840e9b097b925db2"),
			want: terrors.IsNotFoundError,
		},
		{
			name: "Not Found - could not resolve to a node",
			err:  errors.New("Could not resolve to a node with the global id of 'U_kgDOAP3FAg'"),
			want: terrors.IsNotFoundError,
		},
		{
			name: "Not Found - could not resolve to Repository",
			err:  errors.New("Could not resolve to Repository 'R_kgDOEDT6Uw'"),
			want: terrors.IsNotFoundError,
		},
		{
			name: "unexpected error",
			err:  errors.New("💥"),
			want: func(err error) bool {
				return !terrors.IsForbiddenError(err) && !terrors.IsNotFoundError(err)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := convertGraphQLError(tt.err)
			require.NotNil(t, got)
			require.True(t, tt.want(got))
		})
	}

}
