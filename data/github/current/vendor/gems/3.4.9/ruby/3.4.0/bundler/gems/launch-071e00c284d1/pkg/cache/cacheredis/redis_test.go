package cacheredis

import (
	"testing"

	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/pkg/cache"
	"github.com/github/launch/pkg/cache/cachetest"
)

func TestWithExpiry(t *testing.T) {
	client, closeFn, err := launchredis.CreateRedisPoolConnectionForTest(t)
	if err != nil {
		t.Fatal(err)
	}
	defer closeFn()

	cachetest.TestWithExpiry(t, func(t *testing.T) cache.ExpiringCache {
		return NewExpiringCache(client)
	}, cachetest.UseRealTime())
}
