package tester

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/google/uuid"
	"github.com/patrickmn/go-cache"
)

const (
	// default time between each attempt to run tests
	defaultRunSleep = 10 * time.Second
)

// Tester executes configured runnable test
type Tester struct {
	tests    []Runnable
	runCache *cache.Cache
	nextRun  <-chan time.Time
}

// Runnable common interface all tests must implement in order to be run by the Tester
type Runnable interface {
	Name() string
	Frequency() time.Duration
	Timeout() time.Duration
	IsRunning() bool
	Run(ctx context.Context) error
}

func NewTester(cfg *Config) *Tester {
	ticker := time.NewTicker(defaultRunSleep)
	t := &Tester{
		tests: []Runnable{
			NewPublicKeysTest(cfg),
			NewProgrammaticAccessTokenTest(cfg),
			NewSignedAuthTokenTest(cfg),
			NewTokenExchangeTest(cfg),
		},
		runCache: cache.New(1*time.Hour, 1*time.Second),
		nextRun:  ticker.C,
	}

	// verify there are no test name conflicts
	names := make(map[string]bool)
	for _, test := range t.tests {
		if _, found := names[test.Name()]; found {
			panic(fmt.Sprintf("test names are expected to be unique but duplicate found: '%s'", test.Name()))
		}
		names[test.Name()] = true
	}

	return t
}

func (t *Tester) Run(ctx context.Context) error {
	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	diagnostics.StartService(ctx)

	done := make(chan bool)
	go func() {
		for {
			select {
			case <-ctx.Done():
				// shutting down
				done <- true
				return

			case <-t.nextRun:
				// run the tests
				err := t.runTests(ctx)
				if err != nil {
					logger.WithError(err).Error("error while running tests")
					return
				}
			}
		}
	}()

	<-ctx.Done()
	logger.Info("shutting down")
	<-done
	logger.Info("all tests shut down")
	statter.Stop()

	return ctx.Err()
}

func (t *Tester) runTests(ctx context.Context) error {
	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	var wg sync.WaitGroup
	for _, test := range t.tests {
		tLogger := logger.WithFields(kvp.String("gh.authnd.tester", test.Name()), kvp.String("gh.authnd.tester.txn", uuid.New().String()))

		if test.IsRunning() {
			tLogger.Debug("test is already running. skipping.")
			continue
		}

		if _, exp, ok := t.runCache.GetWithExpiration(test.Name()); ok {
			tLogger.Debug("test ran too recently. skipping.", kvp.Time("next run", exp))
			continue
		}

		wg.Add(1)
		go func(r Runnable, rLogger log.Logger) {
			defer wg.Done()

			rCtx, cancel := context.WithTimeout(ctx, r.Timeout())
			defer cancel()
			rCtx = diagnostics.WithLogger(rCtx, rLogger)

			rLogger.Info("starting test")
			start := time.Now()
			err := r.Run(rCtx)
			duration := time.Since(start)

			tags := stats.Tags{
				"test":   r.Name(),
				"result": "success",
			}
			if err != nil {
				tLogger.WithError(err).Error("error running test")
				tags["result"] = "failure"
			}
			statter.Counter("e2e.test.result", tags, 1)
			statter.DistributionMs("e2e.test.duration", tags, duration)

			rLogger.Info("test complete", kvp.String("gh.authnd.tester.result", tags["result"]), kvp.Duration("gh.authnd.tester.duration", duration))
		}(test, tLogger)

		// prevent the test from being run again for the duration of its frequency
		err := t.runCache.Add(test.Name(), "running", test.Frequency())
		if err != nil {
			tLogger.WithError(err).Error("unable to add test to run cache")
		}
	}

	// wait for all tests to complete before exiting
	wg.Wait()

	return nil
}
