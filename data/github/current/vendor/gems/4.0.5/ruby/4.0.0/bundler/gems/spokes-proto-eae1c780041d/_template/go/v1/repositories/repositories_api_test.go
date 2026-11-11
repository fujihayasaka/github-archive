package repositories

import (
	"testing"
	"time"

	"github.com/github/spokes-proto/gen/go/v1/types"
	typesv2 "github.com/github/spokes-proto/gen/go/v2/types"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
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

func TestCreateRepositoryRequestValidate(t *testing.T) {
	validDefaultBranch := &types.Reference{Name: []byte("refs/heads/main")}

	t.Run("missing repository", func(t *testing.T) {
		req := &CreateRepositoryRequest{}
		err := req.Validate()
		require.Error(t, err)
		require.Contains(t, err.Error(), "repository")
	})

	t.Run("missing nwo", func(t *testing.T) {
		req := &CreateRepositoryRequest{
			Repository: types.NewGist(1),
		}
		err := req.Validate()
		require.Error(t, err)
		require.Contains(t, err.Error(), "nwo")
	})

	t.Run("missing default_branch", func(t *testing.T) {
		req := &CreateRepositoryRequest{
			Repository: types.NewGist(1),
			Nwo:        "owner/repo",
		}
		err := req.Validate()
		require.Error(t, err)
		require.Contains(t, err.Error(), "default_branch")
	})

	t.Run("invalid default_branch format", func(t *testing.T) {
		req := &CreateRepositoryRequest{
			Repository:    types.NewGist(1),
			Nwo:           "owner/repo",
			DefaultBranch: &types.Reference{Name: []byte("invalid-ref")},
		}
		err := req.Validate()
		require.Error(t, err)
	})

	t.Run("default_branch without refs/heads/ prefix", func(t *testing.T) {
		req := &CreateRepositoryRequest{
			Repository:    types.NewGist(1),
			Nwo:           "owner/repo",
			DefaultBranch: &types.Reference{Name: []byte("refs/tags/v1.0.0")},
		}
		err := req.Validate()
		require.Error(t, err)
		require.Contains(t, err.Error(), "must have a 'refs/heads/' prefix")
	})

	t.Run("valid minimal request", func(t *testing.T) {
		req := &CreateRepositoryRequest{
			Repository:    types.NewGist(1),
			Nwo:           "owner/repo",
			DefaultBranch: validDefaultBranch,
		}
		err := req.Validate()
		require.NoError(t, err)
	})

	t.Run("valid with initial commit", func(t *testing.T) {
		req := &CreateRepositoryRequest{
			Repository:    types.NewRepository(1),
			Nwo:           "owner/repo",
			DefaultBranch: validDefaultBranch,
			InitialCommit: &CreateRepositoryRequest_InitialCommit{
				Author: &typesv2.Attribution{
					Name:  []byte("Test Author"),
					Email: []byte("author@example.com"),
					Date: &types.Timestamp{
						Timestamp: timestamppb.New(time.Now()),
						Offset:    0,
					},
				},
				Committer: &typesv2.Attribution{
					Name:  []byte("Test Committer"),
					Email: []byte("committer@example.com"),
					Date: &types.Timestamp{
						Timestamp: timestamppb.New(time.Now()),
						Offset:    0,
					},
				},
				Message: []byte("Initial commit"),
				Files: []*CreateRepositoryRequest_InitialCommit_File{
					{
						Path:    &types.Path{Name: []byte("README.md")},
						Content: []byte("# Hello World"),
					},
				},
			},
		}
		err := req.Validate()
		require.NoError(t, err)
	})

	t.Run("initial commit missing author", func(t *testing.T) {
		req := &CreateRepositoryRequest{
			Repository:    types.NewRepository(1),
			Nwo:           "owner/repo",
			DefaultBranch: validDefaultBranch,
			InitialCommit: &CreateRepositoryRequest_InitialCommit{
				Committer: &typesv2.Attribution{
					Name:  []byte("Test Committer"),
					Email: []byte("committer@example.com"),
					Date: &types.Timestamp{
						Timestamp: timestamppb.New(time.Now()),
						Offset:    0,
					},
				},
				Files: []*CreateRepositoryRequest_InitialCommit_File{
					{Path: &types.Path{Name: []byte("README.md")}, Content: []byte("content")},
				},
			},
		}
		err := req.Validate()
		require.Error(t, err)
		require.Contains(t, err.Error(), "author")
	})

	t.Run("initial commit missing committer", func(t *testing.T) {
		req := &CreateRepositoryRequest{
			Repository:    types.NewRepository(1),
			Nwo:           "owner/repo",
			DefaultBranch: validDefaultBranch,
			InitialCommit: &CreateRepositoryRequest_InitialCommit{
				Author: &typesv2.Attribution{
					Name:  []byte("Test Author"),
					Email: []byte("author@example.com"),
					Date: &types.Timestamp{
						Timestamp: timestamppb.New(time.Now()),
						Offset:    0,
					},
				},
				Files: []*CreateRepositoryRequest_InitialCommit_File{
					{Path: &types.Path{Name: []byte("README.md")}, Content: []byte("content")},
				},
			},
		}
		err := req.Validate()
		require.Error(t, err)
		require.Contains(t, err.Error(), "committer")
	})

	t.Run("initial commit missing files", func(t *testing.T) {
		req := &CreateRepositoryRequest{
			Repository:    types.NewRepository(1),
			Nwo:           "owner/repo",
			DefaultBranch: validDefaultBranch,
			InitialCommit: &CreateRepositoryRequest_InitialCommit{
				Author: &typesv2.Attribution{
					Name:  []byte("Test Author"),
					Email: []byte("author@example.com"),
					Date: &types.Timestamp{
						Timestamp: timestamppb.New(time.Now()),
						Offset:    0,
					},
				},
				Committer: &typesv2.Attribution{
					Name:  []byte("Test Committer"),
					Email: []byte("committer@example.com"),
					Date: &types.Timestamp{
						Timestamp: timestamppb.New(time.Now()),
						Offset:    0,
					},
				},
			},
		}
		err := req.Validate()
		require.Error(t, err)
		require.Contains(t, err.Error(), "files")
	})

	t.Run("initial commit file missing path", func(t *testing.T) {
		req := &CreateRepositoryRequest{
			Repository:    types.NewRepository(1),
			Nwo:           "owner/repo",
			DefaultBranch: validDefaultBranch,
			InitialCommit: &CreateRepositoryRequest_InitialCommit{
				Author: &typesv2.Attribution{
					Name:  []byte("Test Author"),
					Email: []byte("author@example.com"),
					Date: &types.Timestamp{
						Timestamp: timestamppb.New(time.Now()),
						Offset:    0,
					},
				},
				Committer: &typesv2.Attribution{
					Name:  []byte("Test Committer"),
					Email: []byte("committer@example.com"),
					Date: &types.Timestamp{
						Timestamp: timestamppb.New(time.Now()),
						Offset:    0,
					},
				},
				Files: []*CreateRepositoryRequest_InitialCommit_File{
					{Content: []byte("content")}, // missing path
				},
			},
		}
		err := req.Validate()
		require.Error(t, err)
		require.Contains(t, err.Error(), "files.path")
	})

	t.Run("initial commit file with non-root path", func(t *testing.T) {
		req := &CreateRepositoryRequest{
			Repository:    types.NewRepository(1),
			Nwo:           "owner/repo",
			DefaultBranch: validDefaultBranch,
			InitialCommit: &CreateRepositoryRequest_InitialCommit{
				Author: &typesv2.Attribution{
					Name:  []byte("Test Author"),
					Email: []byte("author@example.com"),
					Date: &types.Timestamp{
						Timestamp: timestamppb.New(time.Now()),
						Offset:    0,
					},
				},
				Committer: &typesv2.Attribution{
					Name:  []byte("Test Committer"),
					Email: []byte("committer@example.com"),
					Date: &types.Timestamp{
						Timestamp: timestamppb.New(time.Now()),
						Offset:    0,
					},
				},
				Files: []*CreateRepositoryRequest_InitialCommit_File{
					{
						Path:    &types.Path{Name: []byte("docs/README.md")},
						Content: []byte("# Documentation"),
					},
				},
			},
		}
		err := req.Validate()
		require.Error(t, err)
		require.Contains(t, err.Error(), "only root-level files are supported")
	})
}
