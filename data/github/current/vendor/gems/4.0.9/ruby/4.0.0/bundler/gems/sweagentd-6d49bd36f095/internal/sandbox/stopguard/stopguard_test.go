package stopguard_test

import (
	"testing"
	"time"

	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/sandbox/stopguard"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewWithZeroTTLFallsBackToDefault(t *testing.T) {
	store := cache.NewMemoryCacheStore()
	g := stopguard.New(store, 0)
	require.NotNil(t, g)

	gen, err := g.Record("compute-1")
	require.NoError(t, err)
	assert.Equal(t, int64(1), gen)
	assert.True(t, g.IsCurrent("compute-1", gen))
}

func TestGuardRecordIncrementsGeneration(t *testing.T) {
	g := stopguard.New(cache.NewMemoryCacheStore(), stopguard.DefaultTTL)

	gen1, err := g.Record("compute-1")
	require.NoError(t, err)
	assert.Equal(t, int64(1), gen1)

	gen2, err := g.Record("compute-1")
	require.NoError(t, err)
	assert.Equal(t, int64(2), gen2)

	gen3, err := g.Record("compute-1")
	require.NoError(t, err)
	assert.Equal(t, int64(3), gen3)
}

func TestGuardRecordNilGuard(t *testing.T) {
	var g *stopguard.Guard
	gen, err := g.Record("compute-1")
	require.Error(t, err)
	assert.Equal(t, int64(0), gen)
}

func TestGuardIsCurrentMatchesLatestGeneration(t *testing.T) {
	g := stopguard.New(cache.NewMemoryCacheStore(), stopguard.DefaultTTL)

	gen, err := g.Record("compute-1")
	require.NoError(t, err)

	assert.True(t, g.IsCurrent("compute-1", gen))
}

func TestGuardIsCurrentStaleGeneration(t *testing.T) {
	g := stopguard.New(cache.NewMemoryCacheStore(), stopguard.DefaultTTL)

	_, err := g.Record("compute-1")
	require.NoError(t, err)
	gen2, err := g.Record("compute-1")
	require.NoError(t, err)

	assert.False(t, g.IsCurrent("compute-1", gen2-1))
	assert.True(t, g.IsCurrent("compute-1", gen2))
}

func TestGuardIsCurrentUnrecorded(t *testing.T) {
	g := stopguard.New(cache.NewMemoryCacheStore(), stopguard.DefaultTTL)
	assert.False(t, g.IsCurrent("never-seen", 1))
}

func TestGuardIsCurrentUnparseableValue(t *testing.T) {
	store := cache.NewMemoryCacheStore()
	store.Set("stop-agent-compute:gen:compute-1", "not-a-number", time.Hour)

	g := stopguard.New(store, stopguard.DefaultTTL)
	assert.False(t, g.IsCurrent("compute-1", 1))
}

func TestGuardIsCurrentNilGuard(t *testing.T) {
	var g *stopguard.Guard
	assert.False(t, g.IsCurrent("compute-1", 1))
}

func TestGuardIndependentComputeIDs(t *testing.T) {
	g := stopguard.New(cache.NewMemoryCacheStore(), stopguard.DefaultTTL)

	a1, err := g.Record("compute-a")
	require.NoError(t, err)
	a2, err := g.Record("compute-a")
	require.NoError(t, err)
	b1, err := g.Record("compute-b")
	require.NoError(t, err)

	assert.Equal(t, int64(1), a1)
	assert.Equal(t, int64(2), a2)
	assert.Equal(t, int64(1), b1)

	assert.True(t, g.IsCurrent("compute-a", a2))
	assert.True(t, g.IsCurrent("compute-b", b1))
	assert.False(t, g.IsCurrent("compute-a", b1+10))
}
