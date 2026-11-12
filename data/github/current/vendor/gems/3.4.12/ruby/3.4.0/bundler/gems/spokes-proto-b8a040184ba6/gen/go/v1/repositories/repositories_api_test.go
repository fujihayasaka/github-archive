package repositories

import (
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/require"
)

func TestListAvailableReplicasRequestValidate(t *testing.T) {
	req := &ListAvailableReplicasRequest{}
	require.Error(t, req.Validate())

	req = &ListAvailableReplicasRequest{Repository: types.NewRepository(1)}
	require.NoError(t, req.Validate())
}

func TestCreateForkRequestValidate(t *testing.T) {
	req := &CreateForkRequest{}
	require.Error(t, req.Validate())

	req = &CreateForkRequest{
		Parent: &ParentRepository{Repository: types.NewGist(1)},
	}
	require.Error(t, req.Validate())

	req = &CreateForkRequest{
		Parent: &ParentRepository{
			Repository: types.NewRepository(1),
		},
		Fork: &CreateForkRequest_Fork{
			Id:  2,
			Nwo: "owner/repo",
		},
		BranchMode: CreateForkRequest_BRANCH_MODE_DEFAULT_BRANCH,
	}
	require.NoError(t, req.Validate())
}

func TestGetRepositoryMetadataRequestValidate(t *testing.T) {
	req := &GetRepositoryMetadataRequest{}
	require.Error(t, req.Validate())

	req = &GetRepositoryMetadataRequest{Repository: types.NewRepository(1)}
	require.NoError(t, req.Validate())
}
