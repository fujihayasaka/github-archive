package utils

import (
	"context"

	"golang.org/x/sync/errgroup"
)

// ProcessConcurrently takes a channel of work T and processes it concurrently with a static set of worker goroutines.
// The handle function is called for each item in the work T channel, until the channel is closed or an error occurs.
// If any of the handle functions return an error, the processing stops and the error is returned.
// If the context is canceled, the processing stops and the context error is returned.
// If all work is processed successfully, nil is returned.
// Handle functions should be safe to call concurrently
// Handle should respect the incoming context and return an error if the context is canceled.
func ProcessConcurrently[T any](ctx context.Context, work <-chan T, concurrency uint8, handle func(context.Context, T) error) error {
	eg, ctx := errgroup.WithContext(ctx)
	for i := uint8(0); i < concurrency; i++ {
		eg.Go(func() error {
			for {
				select {
				case <-ctx.Done():
					return ctx.Err()
				case item, ok := <-work:
					if !ok {
						return nil
					}
					if err := handle(ctx, item); err != nil {
						return err
					}
				}
			}
		})
	}

	if err := eg.Wait(); err != nil {
		return err
	}
	return nil
}
