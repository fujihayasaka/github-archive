package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func TestNewRepoObjectIDSelector(t *testing.T) {
	repo := types.NewRepository(1)
	oid := types.NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")

	repoOid := NewRepoObjectIDSelector(repo, oid)
	require.Equal(t, &RepoObjectIDSelector{BaseRepository: repo, Oid: oid}, repoOid)
}

func TestRepoObjectIDSelectorValidate(t *testing.T) {
	var nilObjectIDSelector *RepoObjectIDSelector
	require.NoError(t, nilObjectIDSelector.Validate())

	repo := types.NewRepository(1)
	oid := types.NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")

	validObjectWithoutRepo := NewRepoObjectIDSelector(nil, oid)
	require.NoError(t, validObjectWithoutRepo.Validate())

	validObjectWithRepo := NewRepoObjectIDSelector(repo, oid)
	require.NoError(t, validObjectWithRepo.Validate())

	invalidObjectID := types.NewObjectID("")
	invalidSelector1 := NewRepoObjectIDSelector(repo, invalidObjectID)
	require.EqualError(t, invalidSelector1.Validate(), "twirp error invalid_argument: object_id.id is required")

	invalidRepo := &types.Repository{Type: 123, Id: 1}
	invalidSelector2 := NewRepoObjectIDSelector(invalidRepo, oid)
	require.EqualError(t, invalidSelector2.Validate(), "twirp error invalid_argument: repository.type type must be repository, wiki or gist")

}
