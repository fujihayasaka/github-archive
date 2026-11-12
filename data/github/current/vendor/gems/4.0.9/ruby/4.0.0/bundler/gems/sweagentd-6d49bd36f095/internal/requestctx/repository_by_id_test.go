package requestctx

import (
	"context"
	"sync"
	"testing"

	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"
)

func TestRepositoryByID_MissingReturnsFalse(t *testing.T) {
	ctx := NewContext(context.Background())
	repo, ok := RepositoryByID(ctx, 42)
	require.False(t, ok)
	require.Nil(t, repo)
}

func TestRepositoryByID_AddAndGet(t *testing.T) {
	ctx := NewContext(context.Background())
	repo := &gg.Repository{ID: gg.Ptr(int64(42)), Name: gg.Ptr("hello")}

	require.NoError(t, AddRepositoryByID(ctx, 42, repo))

	got, ok := RepositoryByID(ctx, 42)
	require.True(t, ok)
	require.Same(t, repo, got)

	other, ok := RepositoryByID(ctx, 43)
	require.False(t, ok)
	require.Nil(t, other)
}

func TestRepositoryByID_NoCtxData(t *testing.T) {
	repo, ok := RepositoryByID(context.Background(), 42)
	require.False(t, ok)
	require.Nil(t, repo)

	err := AddRepositoryByID(context.Background(), 42, &gg.Repository{})
	require.Error(t, err)
}

// TestRepositoryByID_ConcurrentAccess verifies the cache is safe under concurrent
// reads/writes, which is required because callers fan out GitHub fetches in parallel.
// Run with `go test -race` to validate.
func TestRepositoryByID_ConcurrentAccess(t *testing.T) {
	ctx := NewContext(context.Background())

	const writers = 16
	const reads = 100

	var wg sync.WaitGroup
	for i := range writers {
		wg.Go(func() {
			id := int64(i)
			repo := &gg.Repository{ID: gg.Ptr(id)}
			require.NoError(t, AddRepositoryByID(ctx, id, repo))
		})
	}
	for i := range writers {
		wg.Go(func() {
			id := int64(i)
			for range reads {
				_, _ = RepositoryByID(ctx, id)
			}
		})
	}
	wg.Wait()

	for i := range int64(writers) {
		repo, ok := RepositoryByID(ctx, i)
		require.True(t, ok)
		require.Equal(t, i, repo.GetID())
	}
}
