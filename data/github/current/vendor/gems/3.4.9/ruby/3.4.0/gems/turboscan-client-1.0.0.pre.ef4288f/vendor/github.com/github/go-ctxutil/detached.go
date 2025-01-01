package ctxutil

import (
	"context"
	"errors"
	"time"
)

var (
	_         context.Context = (*detached)(nil)
	zeroTime  time.Time
	neverDone = make(chan struct{})
)

// DetachedCancel returns a `context.Context` that detaches the
// deadline and done signals from the parent. This is useful
// if you need to have a sub-context that has all the values
// of a parent context, but shouldn't have this sub-context
// share the parent's lifetime.
//
// A prime example use case is when an asynchronous process is started
// by an HTTP request. Once the HTTP request is served, the
// `context.Context` associated with it is cancelled. However, the async
// process should keep running. If we use `context.Background()`, the
// async process will not have access to any of the values in the original
// `request.Context`, which is problematic. Using a `DetachedCancel`
// context solves this problem.
func DetachedCancel(ctx context.Context) context.Context {
	return &detached{parent: ctx}
}

type detached struct {
	parent context.Context
}

// Deadline returns no deadline.
func (ctx *detached) Deadline() (time.Time, bool) {
	return zeroTime, false
}

// Done returns a channel that will never receive anything.
func (ctx *detached) Done() <-chan struct{} {
	return neverDone
}

// Err returns an error.
func (ctx *detached) Err() error {
	// at the time of writing, `context.Err()` can only return:
	// - `nil`;
	// - `context.Canceled`; or
	// - `context.DeadlineExceeded`
	// but this could change in future versions of Go, so we
	// explicitly filter the errors here.
	err := ctx.parent.Err()
	switch {
	case errors.Is(err, context.Canceled), errors.Is(err, context.DeadlineExceeded):
		return nil
	default:
		return err
	}
}

func (ctx *detached) Value(key interface{}) interface{} {
	return ctx.parent.Value(key)
}

// DelayedCancel is similar to DetachedCancel except that canceling the parent context will trigger a delayed cancellation of
// the returned context. The returned cancel function will still cancel the returned context immediately.
func DelayedCancel(ctx context.Context, delay time.Duration) (context.Context, context.CancelFunc) {
	delayedCtx, cancel := context.WithCancel(DetachedCancel(ctx))
	go func() {
		select {
		case <-ctx.Done():
			select {
			case <-time.After(delay):
				cancel()
			case <-delayedCtx.Done():
			}
		case <-delayedCtx.Done():
		}
	}()
	return delayedCtx, cancel
}
