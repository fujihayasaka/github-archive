package auth

import (
	"context"
	"testing"
	"time"

	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/db/noop"
	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/types"

	"github.com/stretchr/testify/require"

	entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	proto "google.golang.org/protobuf/proto"
)

const (
	fakeAccessToken = "test-token"
	fakeIPAddr      = "127.0.0.1"
	ttl             = 24 * time.Hour
	fakeSessionID   = "test-session-id"
)

func requestForActor(actorID uint32) BuildActorRequest {
	return BuildActorRequest{ActorID: actorID, AccessToken: fakeAccessToken, RequestIPAddr: fakeIPAddr, CacheTTL: ttl, SessionID: fakeSessionID}
}

// todo: consolidate these two functions; generics
func convertInt64SliceToUint64(input []int64) []uint64 {
	output := make([]uint64, len(input))
	for i, v := range input {
		output[i] = uint64(v)
	}
	return output
}

func convertIDSetToSlice(idSet map[uint32]bool) []uint64 {
	result := make([]uint64, 0, len(idSet))
	for id := range idSet {
		result = append(result, uint64(id))
	}
	return result
}

func convertRepoIDSetToSlice(idSet map[types.RepoID]bool) []uint64 {
	result := make([]uint64, 0, len(idSet))
	for id := range idSet {
		result = append(result, uint64(id))
	}
	return result
}

func setActorInCache(t *testing.T, ctx context.Context, cache cache.Store, actor *models.Actor) {
	t.Helper()
	var res []byte
	var err error

	resources := &entities.AccessibleResources{
		AccessiblePrivateRepoIds:  convertRepoIDSetToSlice(actor.AccessiblePrivateRepoIDs),
		AccessibleOwnerIds:        convertIDSetToSlice(actor.AccessibleOrganizationIDs),
		AuthorizedOrganizationIds: convertInt64SliceToUint64(actor.AuthorizedOrganizationIDs),
		ProtectedOrganizationIds:  convertInt64SliceToUint64(actor.ProtectedOrganizationIDs),
	}
	res, err = proto.Marshal(resources)
	require.NoError(t, err)

	key := actorKey(actor.ID, actor.SessionID)
	err = cache.Set(ctx, key, res, ttl)
	require.NoError(t, err)
}

func Test_ActorWithNoRepos(t *testing.T) {
	actorID := uint32(1)
	ctx := context.Background()
	cache := cache.NewInMemory()
	auth := NewClient(cache, &Mockzd{}, noop.New())

	actor, _, err := auth.BuildActor(ctx, requestForActor(actorID))
	require.NoError(t, err)
	require.Equal(t, actorID, actor.ID)
	require.Equal(t, actor.AccessiblePrivateRepoIDs, types.RepoIDSet{})
	require.Equal(t, actor.AccessibleOrganizationIDs, types.U32Set{})
	require.Equal(t, actor.AuthorizedOrganizationIDs, []int64{})
	require.Equal(t, actor.ProtectedOrganizationIDs, []int64{})

	setActorInCache(t, ctx, cache, actor)
	cacheActor := auth.GetActor(ctx, actorID, fakeIPAddr, fakeSessionID)
	require.Equal(t, actorID, cacheActor.ID)
	require.Equal(t, 0, len(cacheActor.AccessiblePrivateRepoIDs))
}

func Test_GetActor(t *testing.T) {
	actorID := uint32(1)
	ctx := context.Background()
	cache := cache.NewInMemory()
	auth := NewClient(cache, &Mockzd{RepoIDs: map[int64][]uint64{int64(actorID): {1, 2, 3}}}, noop.New())

	actor, _, err := auth.BuildActor(ctx, requestForActor(actorID))
	require.NoError(t, err)
	require.Equal(t, actorID, actor.ID)

	actor.AccessiblePrivateRepoIDs = types.RepoIDSet{1: true, 2: true, 3: true}
	actor.AccessibleOrganizationIDs = types.U32Set{1: true, 2: true, 3: true}

	originalPrivateRepoIDs := actor.AccessiblePrivateRepoIDs
	require.NotEmpty(t, originalPrivateRepoIDs)
	originalAccessibleOwnerIDs := actor.AccessibleOrganizationIDs
	require.NotEmpty(t, originalAccessibleOwnerIDs)

	setActorInCache(t, ctx, cache, actor)
	cacheActor := auth.GetActor(ctx, actorID, fakeIPAddr, fakeSessionID)
	require.Equal(t, actorID, cacheActor.ID)
	require.Equal(t, 3, len(cacheActor.AccessiblePrivateRepoIDs))
}
