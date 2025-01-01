// Package resourceworker contains the code for the resource worker that consumes resources
// from kafka and loads them into gh/gh.
package resourceworker

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/delayedctx"
	"github.com/github/migrations-vnext/internal/pkg/kafka"
	"github.com/github/migrations-vnext/internal/pkg/migrationctx"
	"github.com/github/migrations-vnext/internal/pkg/resource"
	"github.com/github/migrations-vnext/internal/pkg/retry"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/twitchtv/twirp"
	gproto "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type (
	// Worker is the main struct for a resource worker that consumes resources from kafka and processes them
	// to load them into gh/gh using resource.Loader
	Worker struct {
		// loader is the resource loader that loads the resources into gh/gh
		loader resource.Loader
		// backoffPolicy is the backoff policy to use when retrying to load a resource
		backoffPolicy retry.BackoffPolicyFn

		// consumer is the kafka consumer that consumes resources that need to be loaded
		consumer kafka.Consumer
		// deadLetterProducer is the kafka producer that sends failed resources to the dead letter topic
		deadLetterProducer kafka.Producer

		// objectStore is the object store to use when loading resources from the object store
		objectStore ObjectStore

		// resourceTracker is used to track the number of resources processed for observability purposes
		// mainly used for local dev for now, we'll most likely get rid of this once we have better observability in place
		resourceTracker *tracker

		logger  log.Logger
		statter stats.Client
	}

	// Option defines a function that configures a Worker.
	Option func(*Worker)

	// ObjectStore is an interface for fetching resource payloads from an object store.
	ObjectStore interface {
		GetPayload(ctx context.Context, namespace, key string) ([]byte, error)
	}
)

// nowFn is a function that returns the current time and can be overridden in tests
var nowFn = time.Now

// New creates a new Worker with the provided options.
func New(opts ...Option) (*Worker, error) {
	w := &Worker{
		backoffPolicy: func() backoff.BackOff {
			return backoff.WithMaxRetries(backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(2*time.Second)), 3)
		},
		logger:  log.NewNullLogger(),
		statter: stats.NullStatter,
	}
	for _, opt := range opts {
		opt(w)
	}
	w.logger = w.logger.WithFields(kvp.String("component", "resourceworker"))
	w.resourceTracker = &tracker{logger: w.logger.WithFields(kvp.String("component", "tracker"))}
	if w.loader == nil {
		return nil, errors.New("loader is required")
	}
	if w.consumer == nil {
		return nil, errors.New("consumer is required")
	}
	if w.objectStore == nil {
		return nil, errors.New("object store is required")
	}
	return w, nil
}

// Run starts the worker and consumes resources from kafka to load them into
// gh/gh using the provided loader.
//
// The lifecycle of the worker is managed by the provided context.
func (w *Worker) Run(ctx context.Context) error {
	go w.resourceTracker.start(ctx, 30*time.Second)

	if err := w.consumer.Consume(ctx, w.processMsg); err != nil {
		return fmt.Errorf("failed to consume messages: %w", err)
	}
	return nil
}

// processMsg processes a message from the kafka consumer.
func (w *Worker) processMsg(ctx context.Context, m []byte) error {
	if ctx.Err() != nil {
		return ctx.Err()
	}

	// Add resource to tracker to get some stats
	w.resourceTracker.addResource()

	// Unmarshal the message
	res := &v1.Resource{}
	if err := gproto.Unmarshal(m, res); err != nil {
		return fmt.Errorf("failed to unmarshal resource: %w", err)
	}

	logger := w.logger.WithFields(kvp.String("resource", res.String()))
	logger.Info("processing resource")

	// If resource is not inlined, load it from the object store
	hydratedRes := res
	if res.Location == v1.ResourceLocationType_RESOURCE_LOCATION_TYPE_OBJECT_STORE {
		r, err := w.loadFromObjectStore(ctx, res)
		if err != nil {
			return fmt.Errorf("failed to load resource from object store: %w", err)
		}
		hydratedRes = r
	}

	// Create delayed context to allow some time to the in-flight resources to be processed
	// when a single event fails and limit the number of resources that have been processed
	// but not marked as processed.
	delayedCtx, cancel := delayedctx.WithDelayedCancelContext(ctx, 5*time.Second)
	defer cancel()

	// Try loading the resource with a retry mechanism
	loadFn := func() error { return w.loader.LoadResource(delayedCtx, hydratedRes) }
	backOffCtx := backoff.WithContext(w.backoffPolicy(), delayedCtx)

	if err := retry.Retry(loadFn, backOffCtx, logger); err != nil {
		return w.handleLoadError(ctx, res, err)
	}

	return nil
}

// handleLoadError handles the error that occurred while loading the resource.
// If the error should be sent to the dead letter topic, it sends the resource to the dead letter queue.
// If the dead letter producer is not configured, it returns the error.
func (w *Worker) handleLoadError(ctx context.Context, r *v1.Resource, err error) error {
	// if the dead letter producer is not configured, return the error
	if w.deadLetterProducer == nil {
		return fmt.Errorf("failed to load resource: %w", err)
	}

	// Check if the error should be sent to the dead letter topic
	toDL := shouldSendToDeadLetter(err)

	w.logger.WithError(err).Error("failed to load resource after retries", kvp.Bool("to_dead_letter", toDL))

	// If the error should not be sent to the dead letter, return the error
	if !toDL {
		return fmt.Errorf("failed to load resource: %w", err)
	}

	// Send the failed resource to dead letter topic
	failedResource := v1.FailedResource{
		ErrorMessage: err.Error(),
		FailedAt:     timestamppb.New(nowFn()),
		Resource:     r,
	}
	b, err := gproto.Marshal(&failedResource)
	if err != nil {
		return fmt.Errorf("failed to marshal failed resource: %w", err)
	}

	if err := w.deadLetterProducer.Produce(ctx, b); err != nil {
		return fmt.Errorf("failed to send resource to dead letter: %w", err)
	}

	return nil
}

// loadFromObjectStore loads a resource from the object store.
func (w *Worker) loadFromObjectStore(ctx context.Context, r *v1.Resource) (*v1.Resource, error) {
	ns, err := migrationctx.Namespace(r)
	if err != nil {
		return nil, fmt.Errorf("failed to get namespace: %w", err)
	}

	w.logger.Info("loading resource from object store", kvp.String("namespace", ns), kvp.String("key", r.ObjectStore.Key))

	if r.ObjectStore.Key == "" {
		return nil, errors.New("object store key is empty")
	}

	payload, err := w.objectStore.GetPayload(ctx, ns, r.ObjectStore.Key)
	if err != nil {
		return nil, fmt.Errorf("failed to get payload from object store: %w", err)
	}

	var res v1.Resource
	if err := gproto.Unmarshal(payload, &res); err != nil {
		return nil, fmt.Errorf("failed to unmarshal resource from payload: %w", err)
	}

	return &res, nil
}

// shouldSendToDeadLetter returns true if the error should be sent to the dead letter queue.
// For now, we only send:
//   - Twirp errors that are not a 'Canceled' error
//   - InitialOrganizationSettingsError
//   - InitialRepositorySettingsError
//   - PartialBatchError
func shouldSendToDeadLetter(err error) bool {
	var (
		orgErr  *resource.InitialOrganizationSettingsError
		repoErr *resource.InitialRepositorySettingsError
		partial *resource.PartialBatchError
		twErr   twirp.Error
	)
	switch {
	case errors.As(err, &orgErr):
		return true
	case errors.As(err, &repoErr):
		return true
	case errors.As(err, &partial):
		return true
	case errors.As(err, &twErr):
		return twErr.Code() != twirp.Canceled
	default:
		return false
	}
}
