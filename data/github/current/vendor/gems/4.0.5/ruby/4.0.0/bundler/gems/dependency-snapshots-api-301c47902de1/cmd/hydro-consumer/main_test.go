package main

import (
	"context"
	"errors"
	"testing"
	"testing/synctest"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/stretchr/testify/require"
	"go.uber.org/goleak"
)

type fakeRunner struct {
	run func(context.Context) error
}

func (f *fakeRunner) Run(ctx context.Context) error {
	return f.run(ctx)
}

func TestRun(t *testing.T) {
	defer goleak.VerifyNone(t, goleak.IgnoreCurrent())

	logger := log.Named("test")

	t.Run("ShutdownOnContextCancel", func(t *testing.T) {
		// Runs in synctest bubble: deterministic scheduling; no wall-clock sleeps needed.
		synctest.Test(t, func(t *testing.T) {
			globalCtx, cancel := context.WithCancel(context.Background())
			defer cancel()

			consumerStarted := make(chan struct{})
			consumerCtxDone := make(chan struct{})

			consumer := &fakeRunner{run: func(ctx context.Context) error {
				close(consumerStarted)
				<-ctx.Done()
				close(consumerCtxDone)
				return context.Canceled
			}}

			procDone := make(chan struct{})
			proc := &fakeRunner{run: func(ctx context.Context) error {
				<-ctx.Done()
				close(procDone)
				return nil
			}}

			result := make(chan error, 1)
			go func() {
				result <- run(globalCtx, logger, consumer, proc, 100*time.Millisecond)
			}()

			// Wait for consumer goroutine to run.
			synctest.Wait()
			select {
			case <-consumerStarted:
				// ok
			default:
				t.Fatal("expected consumer to start")
			}

			cancel()
			synctest.Wait()

			require.NoError(t, <-result, "expected clean shutdown when context is cancelled")

			select {
			case <-consumerCtxDone:
				// ok
			default:
				t.Fatal("expected consumer ctx to be cancelled")
			}

			select {
			case <-procDone:
				// ok
			default:
				t.Fatal("expected procstats to stop on ctx cancellation")
			}
		})
	})

	t.Run("ReturnsWhenConsumerExitsCleanly", func(t *testing.T) {
		synctest.Test(t, func(t *testing.T) {
			globalCtx := context.Background()

			consumerDone := make(chan struct{})
			consumer := &fakeRunner{run: func(ctx context.Context) error {
				close(consumerDone)
				return nil
			}}

			procDone := make(chan struct{})
			proc := &fakeRunner{run: func(ctx context.Context) error {
				<-ctx.Done()
				close(procDone)
				return nil
			}}

			result := make(chan error, 1)
			go func() {
				result <- run(globalCtx, logger, consumer, proc, 10*time.Second)
			}()

			synctest.Wait()
			select {
			case <-consumerDone:
				// ok
			default:
				t.Fatal("expected consumer to run")
			}

			require.NoError(t, <-result)
			synctest.Wait()

			select {
			case <-procDone:
				// ok: run() should cancel its derived context on return
			default:
				t.Fatal("expected procstats to be cancelled when run() returns")
			}
		})
	})

	t.Run("ReturnsErrorWhenConsumerErrors", func(t *testing.T) {
		synctest.Test(t, func(t *testing.T) {
			globalCtx := context.Background()

			boom := errors.New("boom")
			consumer := &fakeRunner{run: func(ctx context.Context) error {
				return boom
			}}

			proc := &fakeRunner{run: func(ctx context.Context) error {
				<-ctx.Done()
				return nil
			}}

			err := run(globalCtx, logger, consumer, proc, 10*time.Second)
			require.ErrorIs(t, err, boom)
		})
	})

	t.Run("ShutdownTimeoutIfConsumerDoesNotStop", func(t *testing.T) {
		// Deterministically trigger deadline via synctest fake clock.
		synctest.Test(t, func(t *testing.T) {
			stuckConsumerStarted := make(chan struct{})
			unstickConsumer := make(chan struct{})
			defer close(unstickConsumer)

			globalCtx, cancel := context.WithCancel(context.Background())
			defer cancel()

			consumer := &fakeRunner{run: func(ctx context.Context) error {
				close(stuckConsumerStarted)
				<-ctx.Done()
				// ignore cancellation
				<-unstickConsumer
				return nil
			}}

			proc := &fakeRunner{run: func(ctx context.Context) error {
				<-ctx.Done()
				return nil
			}}

			result := make(chan error, 1)
			go func() {
				result <- run(globalCtx, logger, consumer, proc, 25*time.Millisecond)
			}()

			synctest.Wait()
			select {
			case <-stuckConsumerStarted:
				// ok
			default:
				t.Fatal("expected consumer to start")
			}

			cancel()

			// Advance fake time until the shutdown timeout elapses.
			time.Sleep(25 * time.Millisecond)
			synctest.Wait()

			err := <-result
			require.ErrorIs(t, err, context.DeadlineExceeded)
		})
	})

	t.Run("ProcStatsErrorDoesNotFailRun", func(t *testing.T) {
		synctest.Test(t, func(t *testing.T) {
			globalCtx := context.Background()

			consumer := &fakeRunner{run: func(ctx context.Context) error {
				return nil
			}}

			proc := &fakeRunner{run: func(ctx context.Context) error {
				return errors.New("procstats failed")
			}}

			err := run(globalCtx, logger, consumer, proc, 10*time.Second)
			require.NoError(t, err)
		})
	})
}
