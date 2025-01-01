package artifactcache

import (
	"time"

	"github.com/github/launch/pkg/azp"
)

func mockCaches() []*azp.CacheEntry {
	return []*azp.CacheEntry{
		{
			ID:           1,
			Scope:        "refs/heads/main",
			CacheKey:     "linux-node-key1",
			CacheVersion: "asjdlqjwld12i4ei12o3ndsad312d32dewdew-version1",
			Size:         123,
			CreationTime: time.Date(2021, 9, 10, 0, 0, 0, 0, time.UTC),
			LastAccessed: time.Date(2021, 9, 15, 0, 0, 0, 0, time.UTC),
		},
		{
			ID:           2,
			Scope:        "refs/heads/main",
			CacheKey:     "windows-node-key2",
			CacheVersion: "kdheigd82g3idyfubevyifg27389gfi23f7823-version2",
			Size:         456,
			CreationTime: time.Date(2021, 9, 11, 0, 0, 0, 0, time.UTC),
			LastAccessed: time.Date(2021, 9, 14, 0, 0, 0, 0, time.UTC),
		},
		{
			ID:           3,
			Scope:        "refs/heads/test-branch",
			CacheKey:     "macos-node-key3",
			CacheVersion: "djhasjkdh1389dh9823bd89b2389db3289bd8-version3",
			Size:         123,
			CreationTime: time.Date(2021, 9, 12, 0, 0, 0, 0, time.UTC),
			LastAccessed: time.Date(2021, 9, 13, 0, 0, 0, 0, time.UTC),
		},
	}
}
