package manifests

import (
	"context"
	"testing"

	aqueductmock "github.com/github/dependency-snapshots-api/internal/aqueduct/mock"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	mockstatter "github.com/github/dependency-snapshots-api/internal/testutil/mock"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestRepositoryEnumerator_ResolvesHeadWhenCommitMissing(t *testing.T) {
	ctx := context.Background()

	headOID := types.NewObjectID("head123")
	var seenCommit string
	mc := &aqueductmock.MockGitClient{
		ResolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			return headOID, nil
		},
		ListTreeByCommitFn: func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
			seenCommit = commitOID
			return []*types.TreeEntry{
				{
					Path:   types.NewPath([]byte("go.mod")),
					Object: types.NewBlobObject(types.NewObjectID("blob123")),
				},
			}, nil
		},
	}

	st := &mockstatter.MockedStatter{}
	st.On("Counter", mock.Anything, mock.Anything, mock.Anything).Return()
	st.On("DistributionMs", mock.Anything, mock.Anything, mock.Anything).Return()

	cfg := &config.Config{ManifestETLMaxChanges: 10}
	enumerator := NewRepositoryEnumerator(cfg, nil, st, mc)

	rm, err := enumerator.Process(ctx, 42, "")
	require.NoError(t, err)

	// Should have resolved HEAD and passed it through to ListTreeByCommit
	require.Equal(t, headOID.GetId(), seenCommit)
	require.Len(t, rm.ToUpdate, 1)
}

var _ gitaccess.Client = (*aqueductmock.MockGitClient)(nil)
var _ = mockstatter.MockedStatter{}
