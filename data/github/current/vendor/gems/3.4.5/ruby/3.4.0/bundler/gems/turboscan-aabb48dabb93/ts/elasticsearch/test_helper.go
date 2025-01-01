package elasticsearch

import (
	"context"
	"testing"
	"time"

	"github.com/github/turboscan/ts/dbtest"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/stretchr/testify/require"
)

// SetUpTestElasticSearchService sets up a test ElasticSearch environment by creating
// the indices expected by Turboscan and returning the associated ElasticSearch client.
func SetUpTestElasticSearchService(t *testing.T) *Service {
	t.Helper()

	// acquire a lock so that multiple tests do not overwrite each other
	dbtest.Mutex(t)

	cfg, err := config.Load()
	require.NoError(t, err)
	ctx, cancelFunc := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancelFunc()
	es, err := NewService(ctx, cfg.ESUsername, cfg.ESPassword, cfg.ESAddr, cfg.IndexSettings())
	require.NoError(t, err)

	// override the index config to avoid conflicts with the local dev environment
	orgLevelIndex = &IndexConfig{
		name:        "test-index",
		readAlias:   "test-alias-read",
		writeAlias:  "test-alias-write",
		mirrorAlias: "test-alias-mirror",
		mapping:     orglevelMapping,
	}
	override := true
	err = es.CreateIndex(ctx, ts.Index_OrgLevel, override)
	require.NoError(t, err)

	err = es.SetWriteAlias(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)

	err = es.SetReadAlias(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)

	return es
}
