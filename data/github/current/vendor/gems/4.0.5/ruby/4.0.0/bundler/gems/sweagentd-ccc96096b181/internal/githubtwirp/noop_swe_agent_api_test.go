package githubtwirp

import (
	"context"
	"testing"

	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNoopSweagentdAPI_EnterpriseAgents(t *testing.T) {
	t.Run("returns default mock response when no mock function is provided", func(t *testing.T) {
		noop := &NoopSweagentdAPI{}

		req := &sweagentdTwirp.EnterpriseAgentsRequest{
			UserId: 123,
			FindAgentsBy: &sweagentdTwirp.EnterpriseAgentsRequest_RepositoryId{
				RepositoryId: 456,
			},
		}

		resp, err := noop.EnterpriseAgents(context.Background(), req)

		require.NoError(t, err)
		require.NotNil(t, resp)
		assert.Equal(t, uint64(456), resp.RepositoryId)
	})

	t.Run("uses custom mock function when provided", func(t *testing.T) {
		customResponse := &sweagentdTwirp.EnterpriseAgentsResponse{
			RepositoryId: 999,
		}

		noop := &NoopSweagentdAPI{
			MockEnterpriseAgents: func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
				return customResponse, nil
			},
		}

		req := &sweagentdTwirp.EnterpriseAgentsRequest{
			UserId: 789,
			FindAgentsBy: &sweagentdTwirp.EnterpriseAgentsRequest_RepositoryId{
				RepositoryId: 101112,
			},
		}

		resp, err := noop.EnterpriseAgents(context.Background(), req)

		require.NoError(t, err)
		assert.Equal(t, customResponse, resp)
		assert.Equal(t, uint64(999), resp.RepositoryId)
	})
}
