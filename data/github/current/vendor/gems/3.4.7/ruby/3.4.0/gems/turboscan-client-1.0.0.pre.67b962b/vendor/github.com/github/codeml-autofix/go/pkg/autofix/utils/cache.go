package utils

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Timeout constants.
const (
	TimeoutNever   = -1
	TimeoutOneWeek = 7 * 24 * time.Hour
)

type Hashable interface {
	Hash() string
}

type HashableString string

func (s HashableString) Hash() string {
	h := sha256.New()
	h.Write([]byte(s))
	return hex.EncodeToString(h.Sum(nil))
}

// Cache defines an interface for caching values.
type Cache[T any, E error] interface {
	// Get returns (cached, value, error). The thunk is only called on cache miss.
	Get(key Hashable, thunk func() (T, E)) (bool, T, E)
}

// CacheFactory creates caches by name.
type CacheFactory[T any, E error] struct {
	cacheRoot string
	// caches is a map from name to a persistent cache.
	caches map[string]*persistentCache[T, E]
	mu     sync.Mutex
}

// NewCacheFactory returns a new cache factory using the given root directory.
func NewCacheFactory[T any, E error](cacheRoot string) *CacheFactory[T, E] {
	return &CacheFactory[T, E]{
		cacheRoot: cacheRoot,
		caches:    make(map[string]*persistentCache[T, E]),
		mu:        sync.Mutex{},
	}
}

// GetCache returns a persistent Cache with the given name, timeout, and cacheVersion.
// If a cache with the name doesn't exist, it is created.
func (f *CacheFactory[T, E]) GetCache(name string, timeout time.Duration, cacheVersion string) Cache[T, E] {
	f.mu.Lock()
	defer f.mu.Unlock()
	if c, ok := f.caches[name]; ok {
		return c
	}
	c := newPersistentCache[T, E](f.cacheRoot, name, timeout, cacheVersion)
	f.caches[name] = c
	return c
}

type persistentCache[T any, E error] struct {
	cacheRoot    string
	name         string
	timeout      time.Duration
	cacheVersion string

	// inProgress prevents concurrent recomputations for the same key.
	inProgress map[string]*inProgressEntry[T]
	mu         sync.Mutex
}

var _ Cache[int, error] = &persistentCache[int, error]{} //nolint:exhaustruct

type inProgressEntry[T any] struct {
	res  resultEntry[T]
	done chan struct{}
}

type resultEntry[T any] struct {
	value T
	err   error
}

func newPersistentCache[T any, E error](cacheRoot, name string, timeout time.Duration, cacheVersion string) *persistentCache[T, E] {
	return &persistentCache[T, E]{
		cacheRoot:    cacheRoot,
		name:         name,
		timeout:      timeout,
		cacheVersion: cacheVersion,
		inProgress:   make(map[string]*inProgressEntry[T]),
		mu:           sync.Mutex{},
	}
}

func (c *persistentCache[T, E]) cacheFilePath(hash string) string {
	subDir := hash[:2]
	relpath := filepath.Join(c.cacheRoot, c.name, subDir, hash)
	abspath, err := filepath.Abs(relpath)
	if err != nil {
		return relpath
	}
	return abspath
}

// isStale returns true if the cached timestamp is older than the allowed timeout.
func isStale(timestamp int64, timeout time.Duration) bool {
	if timeout < 0 {
		return false
	}
	return time.Now().UnixMilli()-timestamp > int64(timeout.Milliseconds())
}

// serialize bundles a value with the current timestamp.
func serialize(value interface{}) (string, error) {
	now := time.Now().UnixMilli()
	var serialized string
	if value == nil {
		serialized = ""
	} else {
		b, err := json.Marshal(value)
		if err != nil {
			return "", err
		}
		serialized = string(b)
	}
	// Format: timestamp then newline then json.
	return strconv.FormatInt(now, 10) + "\n" + serialized, nil
}

// deserialize unbundles a value from a serialized string.
func deserialize[T any](data string) (int64, *T, error) {
	i := strings.Index(data, "\n")
	if i == -1 {
		return 0, nil, errors.New("invalid cache format")
	}
	ts, err := strconv.ParseInt(data[:i], 10, 64)
	if err != nil {
		return 0, nil, err
	}
	valStr := data[i+1:]
	var value T
	if valStr != "" {
		if err = json.Unmarshal([]byte(valStr), &value); err != nil {
			return 0, nil, err
		}
	}
	return ts, &value, nil
}

// Get implements Cache interface. It first looks for a cached value on disk.
// If found and not stale, it returns the cached value. Otherwise, it calls thunk
// to compute the value, caches it, and returns it. Concurrent calls for the same key
// wait on the first computation.
func (c *persistentCache[T, E]) Get(key Hashable, thunk func() (T, E)) (bool, T, E) {
	hash := key.Hash() + ":" + c.cacheVersion

	c.mu.Lock()
	if entry, ok := c.inProgress[hash]; ok {
		c.mu.Unlock()
		<-entry.done
		var errE E
		if entry.res.err != nil {
			errE = entry.res.err.(E)
		}
		return true, entry.res.value, errE
	}
	// Mark as in-progress.
	entry := &inProgressEntry[T]{done: make(chan struct{})} //nolint:exhaustruct
	c.inProgress[hash] = entry
	c.mu.Unlock()

	cacheFile := c.cacheFilePath(hash)
	// Try to read cache file.
	f, err := os.Open(cacheFile)
	if err == nil {
		defer f.Close()
		if data, err := io.ReadAll(f); err == nil {
			if ts, value, err2 := deserialize[T](string(data)); err2 == nil {
				if !isStale(ts, c.timeout) {
					log.Printf("Cache hit for %s (%s).", c.name, hash)
					c.mu.Lock()
					delete(c.inProgress, hash)
					c.mu.Unlock()
					entry.res = resultEntry[T]{value: *value, err: nil}
					close(entry.done)
					var zeroE E // zero value of E, iow: nil
					return true, *value, zeroE
				}
				log.Printf("Cache entry for %s (%s) is stale.", c.name, hash)
				_ = os.Remove(cacheFile)
			} else {
				log.Printf("Failed to deserialize cached value from %s; ignoring.", cacheFile)
			}
		}
	}

	log.Printf("Cache miss for %s (%s); recomputing.", c.name, hash)
	// Compute the value.
	computed, err := thunk()
	if err == nil {
		serialized, serr := serialize(computed)
		if serr == nil {
			if err := os.MkdirAll(filepath.Dir(cacheFile), 0755); err == nil {
				if werr := os.WriteFile(cacheFile, []byte(serialized), 0644); werr != nil {
					log.Printf("Failed to write cached value to %s; ignoring. %s", cacheFile, werr.Error())
				} else {
					log.Printf("Successfully wrote cached value to %s; ignoring.", cacheFile)
				}
			} else {
				log.Printf("Failed to create directory for cache %s; ignoring.", cacheFile)
			}
		} else {
			log.Printf("Failed to serialize value for cache %s; ignoring.", c.name)
		}
	}
	c.mu.Lock()
	delete(c.inProgress, hash)
	c.mu.Unlock()
	entry.res = resultEntry[T]{value: computed, err: err}
	close(entry.done)
	var errE E
	if err != nil {
		errE = err.(E)
	}
	return false, computed, errE
}
