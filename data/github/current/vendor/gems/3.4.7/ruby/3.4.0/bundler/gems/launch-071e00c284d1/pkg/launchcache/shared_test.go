package launchcache

import (
	"testing"

	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/cache/cachemem"
)

func TestNamespacedCache(t *testing.T) {
	runCacheTestSuite(t, func(*testing.T) Cache {
		return NewNamespacedCache(
			cachemem.NewExpiringCache(1<<20),
			observability.NewNullObservability(),
		)
	})
}
