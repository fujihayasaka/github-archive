package artifactcache

import (
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/pkg/azp"
)

func mapCacheEntries(cacheEntries []*azp.CacheEntry) []*CacheEntry {
	var caches []*CacheEntry
	for i := 0; i < len(cacheEntries); i++ {
		cache := &CacheEntry{
			Id:           cacheEntries[i].ID,
			Scope:        cacheEntries[i].Scope,
			Key:          cacheEntries[i].CacheKey,
			Version:      cacheEntries[i].CacheVersion,
			Size:         cacheEntries[i].Size,
			Created:      timestamppb.New(cacheEntries[i].CreationTime),
			LastAccessed: timestamppb.New(cacheEntries[i].LastAccessed),
		}
		caches = append(caches, cache)
	}
	return caches
}
