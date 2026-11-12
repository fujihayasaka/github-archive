package githubtwirp

import (
	"context"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestResolveBillingEntity(t *testing.T) {
	t.Run("CfB standalone org", func(t *testing.T) {
		client := NewNoopClient()
		client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                    req.Id,
					BillingOrganizationId: 42,
					BillingEnterpriseId:   0,
					BillingEntityResolved: true,
				},
			}, nil
		}

		entity, err := ResolveBillingEntity(t.Context(), client, 1)
		require.NoError(t, err)
		assert.Equal(t, uint64(42), entity.OrganizationID)
		assert.Equal(t, uint64(0), entity.EnterpriseID)
		assert.True(t, entity.Resolved)
		assert.False(t, entity.IsUnresolved())
	})

	t.Run("CfB under enterprise", func(t *testing.T) {
		client := NewNoopClient()
		client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                    req.Id,
					BillingOrganizationId: 42,
					BillingEnterpriseId:   99,
					BillingEntityResolved: true,
				},
			}, nil
		}

		entity, err := ResolveBillingEntity(t.Context(), client, 1)
		require.NoError(t, err)
		assert.Equal(t, uint64(42), entity.OrganizationID)
		assert.Equal(t, uint64(99), entity.EnterpriseID)
		assert.False(t, entity.IsUnresolved())
	})

	t.Run("CfE direct seat", func(t *testing.T) {
		client := NewNoopClient()
		client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                    req.Id,
					BillingOrganizationId: 0,
					BillingEnterpriseId:   99,
					BillingEntityResolved: true,
				},
			}, nil
		}

		entity, err := ResolveBillingEntity(t.Context(), client, 1)
		require.NoError(t, err)
		assert.Equal(t, uint64(0), entity.OrganizationID)
		assert.Equal(t, uint64(99), entity.EnterpriseID)
		assert.False(t, entity.IsUnresolved())
	})

	t.Run("CfI user is resolved with zero IDs", func(t *testing.T) {
		client := NewNoopClient()
		client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                    req.Id,
					BillingOrganizationId: 0,
					BillingEnterpriseId:   0,
					BillingEntityResolved: true,
				},
			}, nil
		}

		entity, err := ResolveBillingEntity(t.Context(), client, 1)
		require.NoError(t, err)
		assert.Equal(t, uint64(0), entity.OrganizationID)
		assert.Equal(t, uint64(0), entity.EnterpriseID)
		assert.False(t, entity.IsUnresolved())
	})

	t.Run("multi-SKU user without selection is unresolved", func(t *testing.T) {
		client := NewNoopClient()
		client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                    req.Id,
					BillingOrganizationId: 0,
					BillingEnterpriseId:   0,
					BillingEntityResolved: false,
				},
			}, nil
		}

		entity, err := ResolveBillingEntity(t.Context(), client, 1)
		require.NoError(t, err)
		assert.True(t, entity.IsUnresolved())
	})

	t.Run("multi-SKU user with selection is resolved", func(t *testing.T) {
		client := NewNoopClient()
		client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                    req.Id,
					BillingOrganizationId: 42,
					BillingEnterpriseId:   99,
					BillingEntityResolved: true,
				},
			}, nil
		}

		entity, err := ResolveBillingEntity(t.Context(), client, 1)
		require.NoError(t, err)
		assert.Equal(t, uint64(42), entity.OrganizationID)
		assert.Equal(t, uint64(99), entity.EnterpriseID)
		assert.False(t, entity.IsUnresolved())
	})

	t.Run("returns error when user details fetch fails", func(t *testing.T) {
		client := NewNoopClient()
		client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return nil, assert.AnError
		}

		entity, err := ResolveBillingEntity(t.Context(), client, 1)
		assert.Error(t, err)
		assert.Nil(t, entity)
	})

	t.Run("returns error when user details are nil", func(t *testing.T) {
		client := NewNoopClient()
		client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: nil}, nil
		}

		entity, err := ResolveBillingEntity(t.Context(), client, 1)
		assert.Error(t, err)
		assert.Nil(t, entity)
		assert.Contains(t, err.Error(), "user details are nil")
	})
}
