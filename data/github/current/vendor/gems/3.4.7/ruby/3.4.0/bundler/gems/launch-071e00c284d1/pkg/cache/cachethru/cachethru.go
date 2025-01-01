package cachethru

import (
	"context"
	"time"

	"github.com/pkg/errors"

	"github.com/github/launch/pkg/cache"
)

type writeThruOptions struct {
	onWriteBackError func(error) error
}

type WriteThruOption func(*writeThruOptions)

// WithOnWriteBackError sets a handler that is used when a Get from the
// remote cache fails to be writen back to the local cache.
// NOTE: If the handler returns an error, the `WriteThru.Get()` also
// returns an error. In normal cases, you wouldn't want that.
func WithOnWriteBackError(handler func(error) error) WriteThruOption {
	return func(opts *writeThruOptions) {
		opts.onWriteBackError = handler
	}
}

// WriteThru uses a local and a remote cache, writing back to
// local the values found on remote.
// Get: reads from local first. On cache miss, reads from remote
// and fills back 'local' on cache hit.
// Set: writes to both local and remote
func WriteThru(local, remote cache.ExpiringCache, opts ...WriteThruOption) cache.ExpiringCache {
	opt := &writeThruOptions{}
	for _, o := range opts {
		o(opt)
	}
	return &writeThru{local: local, remote: remote, opts: opt}
}

type writeThru struct {
	local, remote cache.ExpiringCache
	opts          *writeThruOptions
}

func (c *writeThru) Set(ctx context.Context, key string, value []byte, now time.Time, expiresIn time.Duration) (err error) {
	if err := c.local.Set(ctx, key, value, now, expiresIn); err != nil {
		return errors.Wrap(err, "writing to local cache")
	}
	if err := c.remote.Set(ctx, key, value, now, expiresIn); err != nil {
		return errors.Wrap(err, "writing to remote cache")
	}
	return nil
}

func (c *writeThru) Get(ctx context.Context, key string, now time.Time) (value *cache.ExpiringValue, found bool, err error) {
	// TODO(antoine): if/when `GetOrSet` gets implemented, use this to lock
	// the local cache so we singleflight deduplicate calls to the remote.
	value, found, err = c.local.Get(ctx, key, now)
	if err != nil {
		return nil, false, errors.Wrap(err, "reading from local cache")
	}
	if found {
		return value, found, err
	}

	value, found, err = c.remote.Get(ctx, key, now)
	if err != nil {
		return nil, false, errors.Wrap(err, "reading from remote cache")
	}
	if !found {
		return nil, false, nil
	}
	// don't want to fail the `Get` if the local cache fails to write-back
	wberr := c.local.Set(ctx, key, value.Value, now, value.Expiry.Sub(now))
	if wberr != nil && c.opts.onWriteBackError != nil {
		// however we'll let an error handler know, if one is set.
		if err := c.opts.onWriteBackError(wberr); err != nil {
			// return an error if the error handler said to return one
			return nil, false, err
		}
	}
	return value, found, nil
}
