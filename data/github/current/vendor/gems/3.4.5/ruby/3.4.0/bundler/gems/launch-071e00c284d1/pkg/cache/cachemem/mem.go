package cachemem

import (
	"container/heap"
	"context"
	"errors"
	"sync"
	"time"

	"github.com/github/launch/pkg/cache"
)

type expiringCacheOptions struct {
	onExpire          func(context.Context, string, *cache.ExpiringValue)
	onEvict           func(context.Context, string, *cache.ExpiringValue)
	onByteSizeChange  func(ctx context.Context, size, max int)
	onItemCountChange func(ctx context.Context, count int)
}

// WithExpiringCacheEvictionHandler allows registering a callback
// to handle entries that have not yet expired but were evicted
// because the cache is full and higher priority items are being
// added.
//
// You can use this callback to send the expired entry to another
// colder tier of caching, for example.
func WithExpiringCacheEvictionHandler(
	onEvict func(context.Context, string, *cache.ExpiringValue),
) ExpiringCacheOption {
	return func(opts *expiringCacheOptions) {
		opts.onEvict = onEvict
	}
}

// WithExpiringCacheExpiryHandler allows registering a callback
// to handle entries that expire, if desired.
func WithExpiringCacheExpiryHandler(
	onExpire func(context.Context, string, *cache.ExpiringValue),
) ExpiringCacheOption {
	return func(opts *expiringCacheOptions) {
		opts.onExpire = onExpire
	}
}

// WithExpiringCacheTelemetry allows receiving updates when:
// - onByteSizeChange: when the estimated size of the cache, in bytes, changes
// - onItemCountChange: when the count of items in the cache changes
// You can use this to updates gauge-types of metrics for monitoring.
func WithExpiringCacheTelemetry(
	onByteSizeChange func(ctx context.Context, size, max int),
	onItemCountChange func(ctx context.Context, count int),
) ExpiringCacheOption {
	return func(opts *expiringCacheOptions) {
		opts.onByteSizeChange = onByteSizeChange
		opts.onItemCountChange = onItemCountChange
	}
}

type ExpiringCacheOption func(*expiringCacheOptions)

var ErrValueToBigForCache = errors.New("value is too big for cache's max size")

type expiryEntry struct {
	key       string
	value     cache.ExpiringValue
	size      int
	heapIndex int
}

type expiringCache struct {
	opts             *expiringCacheOptions
	maxSizeBytes     int
	currentSizeBytes int

	mu        sync.Mutex
	entryHeap *expiryEntryHeap
	cache     map[string]*expiryEntry
}

func NewExpiringCache(maxSizeBytes int, opts ...ExpiringCacheOption) cache.ExpiringCache {
	return newCacheWithExpiry(maxSizeBytes, opts...)
}

func newCacheWithExpiry(maxSizeBytes int, opts ...ExpiringCacheOption) *expiringCache {
	opt := &expiringCacheOptions{}
	for _, o := range opts {
		o(opt)
	}
	h := new(expiryEntryHeap)
	heap.Init(h)
	return &expiringCache{
		opts:         opt,
		maxSizeBytes: maxSizeBytes,
		entryHeap:    h,
		cache:        make(map[string]*expiryEntry),
	}
}

func (c *expiringCache) Set(ctx context.Context, key string, value []byte, now time.Time, expiresIn time.Duration) (err error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	entry := &expiryEntry{
		key:   key,
		value: cache.ExpiringValue{Value: value, Expiry: now.Add(expiresIn)},
		size:  len(key) + len(value), // good enough approximation
	}
	size := entry.size
	if size > c.maxSizeBytes {
		return ErrValueToBigForCache
	}

	// do some maintenance cleanup
	c.purgeExpired(ctx, now)

	if futureSize := c.currentSizeBytes + size; futureSize > c.maxSizeBytes {
		availableSize := (c.maxSizeBytes - c.currentSizeBytes)
		neededSize := size - availableSize
		c.evict(ctx, neededSize)
	}

	c.currentSizeBytes += size
	c.entryHeap.push(entry)
	c.cache[entry.key] = entry

	c.updateTelemetry(ctx)

	return nil
}

func (c *expiringCache) purgeExpired(ctx context.Context, now time.Time) {
	for c.entryHeap.Len() > 0 {
		entry := c.entryHeap.peek()
		if entry.value.Expiry.After(now) {
			return
		}
		expired := c.entryHeap.pop()
		c.remove(ctx, expired)
		if c.opts.onExpire != nil {
			c.opts.onExpire(ctx, expired.key, &expired.value)
		}
	}
}

func (c *expiringCache) evict(ctx context.Context, toEvictSize int) {
	// if we need to make space, we evict entries
	// in order of soonest-to-expire
	for toEvictSize > 0 && c.entryHeap.Len() > 0 {
		evicted := c.entryHeap.pop()
		toEvictSize -= evicted.size
		c.remove(ctx, evicted)
		if c.opts.onEvict != nil {
			c.opts.onEvict(ctx, evicted.key, &evicted.value)
		}
	}
}

func (c *expiringCache) remove(ctx context.Context, entry *expiryEntry) {
	delete(c.cache, entry.key)
	c.currentSizeBytes -= entry.size
	c.updateTelemetry(ctx)
}

func (c *expiringCache) updateTelemetry(ctx context.Context) {
	if c.opts.onByteSizeChange != nil {
		c.opts.onByteSizeChange(ctx, c.currentSizeBytes, c.maxSizeBytes)
	}
	if c.opts.onItemCountChange != nil {
		c.opts.onItemCountChange(ctx, len(c.cache))
	}
}

func (c *expiringCache) Get(ctx context.Context, key string, now time.Time) (value *cache.ExpiringValue, found bool, err error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// ensures no expired key can be returned from `Get`
	// while also taking the opportunity to cleanup expired
	// items.
	c.purgeExpired(ctx, now)

	entry, ok := c.cache[key]
	if !ok {
		return nil, false, nil
	}
	return &entry.value, true, nil
}

var _ heap.Interface = (*expiryEntryHeap)(nil)

type expiryEntryHeap struct {
	entries []*expiryEntry
}

func (h *expiryEntryHeap) push(x *expiryEntry) { heap.Push(h, x) }
func (h *expiryEntryHeap) pop() *expiryEntry   { return heap.Pop(h).(*expiryEntry) }
func (h *expiryEntryHeap) peek() *expiryEntry {
	return h.entries[0]
}

func (h *expiryEntryHeap) Len() int {
	return len(h.entries)
}

func (h *expiryEntryHeap) Less(i, j int) bool {
	return h.entries[i].value.Expiry.Before(h.entries[j].value.Expiry)
}

func (h *expiryEntryHeap) Swap(i, j int) {
	h.entries[i], h.entries[j] = h.entries[j], h.entries[i]
	h.entries[i].heapIndex = i
	h.entries[j].heapIndex = j
}

func (h *expiryEntryHeap) Push(x any) {
	v := x.(*expiryEntry)
	v.heapIndex = len(h.entries)
	h.entries = append(h.entries, v)
}

func (h *expiryEntryHeap) Pop() any {
	n := len(h.entries)
	entry := h.entries[n-1]
	h.entries[n-1] = nil // avoid leaks
	entry.heapIndex = -1 // failsafe
	h.entries = h.entries[0 : n-1]
	return entry
}
