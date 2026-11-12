package cache

import (
	"sync"
	"time"
)

// Creates a thread-safe TTL cache.
func NewTTLCache[K comparable, V interface{}](ttl time.Duration) TTLCache[K, V] {
	return TTLCache[K, V]{
		sync.Mutex{},
		make(map[K]ttlEntry[V]),
		ttl,
		time.Time{},
		time.Now,
	}
}

type TTLCache[K comparable, V interface{}] struct {
	mutex         sync.Mutex
	cache         map[K]ttlEntry[V]
	ttl           time.Duration
	evictionAfter time.Time
	now           func() time.Time
}
type ttlEntry[V interface{}] struct {
	value   V
	expires time.Time
}

func (c *TTLCache[K, V]) Insert(key K, value V) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	now := c.now()

	c.tryEviction(now)
	c.cache[key] = ttlEntry[V]{value, now.Add(c.ttl)}
}

func (c *TTLCache[K, V]) Get(key K) (V, bool) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	now := c.now()

	c.tryEviction(now)
	if entry, ok := c.cache[key]; ok && entry.expires.After(now) {
		return entry.value, true
	} else {
		var value V
		return value, false
	}
}

func (c *TTLCache[K, V]) tryEviction(now time.Time) {
	if c.evictionAfter.IsZero() {
		c.evictionAfter = now.Add(c.ttl)
	} else if c.evictionAfter.After(now) {
		return
	}
	for key, entry := range c.cache {
		if entry.expires.Before(now) {
			delete(c.cache, key)
		}
	}
	c.evictionAfter = now.Add(c.ttl)
}
