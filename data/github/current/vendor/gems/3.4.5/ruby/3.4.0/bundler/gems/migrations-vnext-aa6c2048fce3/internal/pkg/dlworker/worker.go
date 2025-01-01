// Package dlworker contains the code for the dead letter worker that consumes failed
// resources from kafka and retries them
package dlworker

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

		// firstResource is the first failed resource that was processed
		// it's used to determine if we are done going through all the resources
		firstResource *v1.FailedResource

		// waitIteration is the time to wait before starting a new iteration
		waitIteration time.Duration

		// objectStore is the object store to use when loading resources from the object store
		objectStore ObjectStore

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
		waitIteration: time.Minute,
		backoffPolicy: func() backoff.BackOff {
			return backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(1 * time.Second))
		},
		logger:  log.NewNullLogger(),
		statter: stats.NullStatter,
	}
	for _, opt := range opts {
		opt(w)
	}
	w.logger = w.logger.WithFields(kvp.String("component", "dlworker"))

	// validate required fields
	if w.loader == nil {
		return nil, errors.New("loader is required")
	}
	if w.consumer == nil {
		return nil, errors.New("consumer is required")
	}
	if w.deadLetterProducer == nil {
		w.logger.Warn("dead letter producer is not configured")
	}

	return w, nil
}

// Run starts the worker and consumes resources from kafka to load them into
// gh/gh using the provided loader.
//
// The lifecycle of the worker is managed by the provided context.
func (w *Worker) Run(ctx context.Context) error {
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

	// Unmarshal the message
	var r v1.FailedResource
	if err := gproto.Unmarshal(m, &r); err != nil {
		return fmt.Errorf("failed to unmarshal failed resource: %w", err)
	}

	// check if we have completed an iteration, i.e: we have retried all the failed resources,
	// and the current resource is the first failed resource that we saw
	if gproto.Equal(w.firstResource, &r) {
		w.logger.Info("all failed resources have been retried, waiting before starting a new iteration")
		select {
		case <-time.After(w.waitIteration):
		case <-ctx.Done():
			return ctx.Err()
		}
		w.firstResource = nil
	}

	logger := w.logger.WithFields(kvp.String("resource", r.String()))
	logger.Info("processing resource")

	var hydratedRes *v1.Resource
	if r.Resource.Location == v1.ResourceLocationType_RESOURCE_LOCATION_TYPE_OBJECT_STORE {
		r, err := w.loadFromObjectStore(ctx, r.Resource)
		if err != nil {
			return fmt.Errorf("failed to load resource from object store: %w", err)
		}
		hydratedRes = r
	} else {
		hydratedRes = r.Resource
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
		return w.handleLoadError(ctx, &r, err)
	}

	// if this was the first resource and was loaded successfully, we can reset the first resource
	if gproto.Equal(w.firstResource, &r) {
		w.firstResource = nil
	}

	return nil
}

// handleLoadError handles the error that occurred while loading the resource.
// when an error occurs, it sends the resource to the dead letter topic again while
// updating its fields: error message, retries attempted, and failed at.
func (w *Worker) handleLoadError(ctx context.Context, r *v1.FailedResource, err error) error {
	// Send the failed resource to dead letter topic
	failedResource := v1.FailedResource{
		ErrorMessage:     err.Error(),
		FailedAt:         timestamppb.New(nowFn()),
		RetriesAttempted: r.RetriesAttempted + 1,
		Resource:         r.Resource,
	}
	b, err := gproto.Marshal(&failedResource)
	if err != nil {
		return fmt.Errorf("failed to marshal failed resource: %w", err)
	}

	if err := w.deadLetterProducer.Produce(ctx, b); err != nil {
		return fmt.Errorf("failed to send resource to dead letter: %w", err)
	}

	// keep track of the first failed resource that failed again to be loaded
	if w.firstResource == nil {
		w.firstResource = &failedResource
	}

	return nil
}

// loadFromObjectStore loads a resource from the object store.
func (w *Worker) loadFromObjectStore(ctx context.Context, r *v1.Resource) (*v1.Resource, error) {
	ns, err := migrationctx.Namespace(r)
	if err != nil {
		return nil, fmt.Errorf("failed to get namespace from resource: %w", err)
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
