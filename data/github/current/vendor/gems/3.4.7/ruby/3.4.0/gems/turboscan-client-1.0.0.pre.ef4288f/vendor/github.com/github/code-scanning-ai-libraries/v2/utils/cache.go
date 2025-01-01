package utils

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

// Timeout constants.
const (
	TimeoutNever   = -1
	TimeoutOneWeek = 7 * 24 * time.Hour
)

// Hashable defines an interface for objects that can generate a hash string.
type Hashable interface {
	Hash() string
}

// HashableString is a string type that implements the Hashable interface.
type HashableString string

// Hash implements the Hashable interface for HashableString.
func (s HashableString) Hash() string {
	h := sha256.New()
	_, _ = h.Write([]byte(s))
	return hex.EncodeToString(h.Sum(nil))
}

// Cache defines an interface for caching values.
type Cache[T any, E error] interface {
	// Get returns (cached, value, error). The thunk is only called on cache miss.
	Get(key Hashable, thunk func() (T, E), logger log.Logger) (bool, T, E)
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

// Compile-time check to ensure persistentCache implements Cache interface
var _ Cache[int, error] = &persistentCache[int, error]{} //nolint:exhaustruct // Intentionally partial initialization for type check

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
	return time.Now().UnixMilli()-timestamp > timeout.Milliseconds()
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
		if err := json.Unmarshal([]byte(valStr), &value); err != nil {
			return 0, nil, err
		}
	}
	return ts, &value, nil
}

// Get implements Cache interface. It first looks for a cached value on disk.
// If found and not stale, it returns the cached value. Otherwise, it calls thunk
// to compute the value, caches it, and returns it. Concurrent calls for the same key
// wait on the first computation.
func (c *persistentCache[T, E]) Get(key Hashable, thunk func() (T, E), logger log.Logger) (bool, T, E) {
	baseHash := key.Hash()
	hash := HashableString(baseHash + ":" + c.cacheVersion).Hash() // add cache version to the hash

	c.mu.Lock()
	if entry, ok := c.inProgress[hash]; ok {
		c.mu.Unlock()
		<-entry.done
		var errE E
		if entry.res.err != nil {
			errE = entry.res.err.(E) //nolint:revive,errorlint,forcetypeassert // this never fails as we control the error type
		}
		return true, entry.res.value, errE
	}
	// Mark as in-progress.
	entry := &inProgressEntry[T]{done: make(chan struct{})} //nolint:exhaustruct // res field is intentionally left zero-valued initially
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
					logger.Debug("Cache hit", kvp.String("name", c.name), kvp.String("hash", hash))
					c.mu.Lock()
					delete(c.inProgress, hash)
					c.mu.Unlock()
					entry.res = resultEntry[T]{value: *value, err: nil}
					close(entry.done)
					var zeroE E // zero value of E, iow: nil
					return true, *value, zeroE
				}
				logger.Debug("Cache entry is stale", kvp.String("name", c.name), kvp.String("hash", hash))
				_ = os.Remove(cacheFile)
			} else {
				logger.Info("Failed to deserialize cached value",
					kvp.String("cacheFile", cacheFile), kvp.String("error", err2.Error()))
			}
		}
	}

	logger.Debug("Cache miss. Recomputing", kvp.String("name", c.name), kvp.String("hash", hash))
	// Compute the value.
	computed, err := thunk()
	if err == nil {
		c.writeCacheFile(cacheFile, computed, logger)
	}
	c.mu.Lock()
	delete(c.inProgress, hash)
	c.mu.Unlock()
	entry.res = resultEntry[T]{value: computed, err: err}
	close(entry.done)
	var errE E
	if err != nil {
		errE = err.(E) //nolint:revive,errorlint,forcetypeassert // this never fails as we control the error type
	}
	return false, computed, errE
}

// writeCacheFile handles the complexity of writing a value to the cache file.
func (c *persistentCache[T, E]) writeCacheFile(cacheFile string, value T, logger log.Logger) {
	serialized, serr := serialize(value)
	if serr != nil {
		logger.Debug("Failed to serialize value for cache. Ignoring.", kvp.String("name", c.name))
		return
	}

	if err := os.MkdirAll(filepath.Dir(cacheFile), 0o750); err != nil {
		logger.Debug("Failed to create directory for cache. Ignoring.", kvp.String("cacheFile", cacheFile))
		return
	}

	if werr := os.WriteFile(cacheFile, []byte(serialized), 0o644); werr != nil { //nolint:gosec // Cache files don't contain sensitive data
		logger.Debug("Failed to write cached value. Ignoring.", kvp.String("cacheFile", cacheFile), kvp.String("error", werr.Error()))
	} else {
		logger.Debug("Successfully wrote cached value.", kvp.String("cacheFile", cacheFile))
	}
}
