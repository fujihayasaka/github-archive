package resync

import (
	"context"
	"testing"

	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/stretchr/testify/require"
)

func TestIgnoreRepo(t *testing.T) {
	require.True(t, ignoreRepo(context.Background(), &v1.GetRepositoriesResponse_Repository{
		IsArchived: true,
	}))

	require.True(t, ignoreRepo(context.Background(), &v1.GetRepositoriesResponse_Repository{
		IsPublic: true,
	}))

	require.False(t, ignoreRepo(fromctx.Env.With(context.Background(), "enterprise"), &v1.GetRepositoriesResponse_Repository{
		IsPublic: true,
	}))

	require.False(t, ignoreRepo(context.Background(), &v1.GetRepositoriesResponse_Repository{}))
}
