package azp

import (
	"context"
	"time"
)

type ArtifactCacheClient interface {
	ListCaches(ctx context.Context, key, scope, sort, direction string, page, perPage int64) ([]*CacheEntry, int64, error)
	DeleteCachesByKey(ctx context.Context, key, scope string) ([]*CacheEntry, int64, error)
	DeleteCacheByID(ctx context.Context, id int64) error
}

type CacheEntryResponse struct {
	TotalCount     int64         `json:"totalCount"`
	ArtifactCaches []*CacheEntry `json:"artifactCaches"`
}

type CacheEntry struct {
	ID           int64     `json:"id"`
	Scope        string    `json:"scope"`
	CacheKey     string    `json:"cacheKey"`
	CacheVersion string    `json:"cacheVersion"`
	Size         int64     `json:"size"`
	CreationTime time.Time `json:"creationTime"`
	LastAccessed time.Time `json:"lastAccessed"`
}
