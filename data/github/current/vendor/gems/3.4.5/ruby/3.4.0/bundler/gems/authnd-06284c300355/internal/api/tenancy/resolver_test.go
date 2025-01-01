package tenancy

import (
	"context"
	"database/sql"
	"testing"

	"github.com/github/authnd/internal/common/models"
	"github.com/patrickmn/go-cache"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSuccessfulLookupsAreCached(t *testing.T) {
	var lookupCount int
	r := &resolver{
		tenantCache: cache.New(cache.NoExpiration, cache.NoExpiration),
		businessLookup: func(ctx context.Context, slug string) (*models.Business, error) {
			lookupCount++
			return &models.Business{
				ID:        1337,
				Shortcode: "asdfjkl;",
				Slug:      "test-slug",
			}, nil
		},
	}

	// correct result is returned
	tCtx, err := r.GetTenantForSlug(context.Background(), "test-slug")
	require.NoError(t, err)
	assert.Equal(t, 1337, tCtx.ID)
	assert.Equal(t, "asdfjkl;", tCtx.Shortcode)
	assert.Equal(t, 1, lookupCount)

	// result is cached
	require.Equal(t, 1, r.tenantCache.ItemCount())
	cached, ok := r.tenantCache.Get("test-slug")
	cCtx := cached.(*TenantContext)
	require.True(t, ok)
	assert.Equal(t, 1337, cCtx.ID)
	assert.Equal(t, "asdfjkl;", cCtx.Shortcode)

	// cache is used on subsequent lookups
	tCtx2, err := r.GetTenantForSlug(context.Background(), "test-slug")
	require.NoError(t, err)
	assert.Equal(t, 1337, tCtx2.ID)
	assert.Equal(t, "asdfjkl;", tCtx2.Shortcode)
	assert.Equal(t, 1, lookupCount)
	assert.Equal(t, 1, r.tenantCache.ItemCount())

	// lookup for different slug is not cached
	tCtx3, err := r.GetTenantForSlug(context.Background(), "test-slug-2")
	require.NoError(t, err)
	assert.Equal(t, 1337, tCtx3.ID)
	assert.Equal(t, "asdfjkl;", tCtx3.Shortcode)
	assert.Equal(t, 2, lookupCount)
	assert.Equal(t, 2, r.tenantCache.ItemCount())
}

func TestError(t *testing.T) {
	r := &resolver{
		tenantCache: cache.New(cache.NoExpiration, cache.NoExpiration),
		businessLookup: func(ctx context.Context, slug string) (*models.Business, error) {
			return nil, sql.ErrNoRows
		},
	}

	// error is passed through
	tCtx, err := r.GetTenantForSlug(context.Background(), "test-slug")
	require.EqualError(t, err, "sql: no rows in result set")
	require.Nil(t, tCtx)

	// nothing is cached
	assert.Zero(t, r.tenantCache.ItemCount())
}
