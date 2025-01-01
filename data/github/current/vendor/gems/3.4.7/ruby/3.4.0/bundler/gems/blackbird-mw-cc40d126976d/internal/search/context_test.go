package search

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_ContextTimeouts(t *testing.T) {
	expected := 100 * time.Second
	c := BuildFESuggestQueryContext(&models.Actor{}, expected, []types.RepoID{}, "")
	require.Equal(t, expected, c.Timeout)

	c = BuildFECountQueryContext(&models.Actor{}, expected, []types.RepoID{}, "")
	require.Equal(t, expected, c.Timeout)

	c = BuildFEUserQueryContext(&models.Actor{}, QueryLimits{}, QueryTypeUser, QuerySourceFE, expected, []types.RepoID{}, nil, nil, "", false)
	require.Equal(t, expected, c.Timeout)
}
