package repositories

import (
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/require"
)

func TestGetRepositoryMetadataRequestValidate(t *testing.T) {
	req := &GetRepositoryMetadataRequest{}
	require.Error(t, req.Validate())

	req = &GetRepositoryMetadataRequest{
		Target: &GetRepositoryMetadataRequest_Repository{
			Repository: types.NewRepository(1),
		},
	}
	require.NoError(t, req.Validate())

	req = &GetRepositoryMetadataRequest{
		Target: &GetRepositoryMetadataRequest_Network{
			Network: types.NewNetwork(1),
		},
	}
	require.NoError(t, req.Validate())
}
