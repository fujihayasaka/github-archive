package resourceworker

import (
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/kafka"
	"github.com/github/migrations-vnext/internal/pkg/resource"
	"github.com/github/migrations-vnext/internal/pkg/retry"
)

// WithLoader sets the loader for the Worker.
func WithLoader(loader resource.Loader) Option {
	return func(w *Worker) {
		w.loader = loader
	}
}

// WithConsumer sets the consumer for the Worker.
func WithConsumer(consumer kafka.Consumer) Option {
	return func(w *Worker) {
		w.consumer = consumer
	}
}

// WithDeadLetterProducer sets the dead letter producer for the Worker.
func WithDeadLetterProducer(deadLetterProducer kafka.Producer) Option {
	return func(w *Worker) {
		w.deadLetterProducer = deadLetterProducer
	}
}

// WithObjectStore sets the object store for the Worker.
func WithObjectStore(objectStore ObjectStore) Option {
	return func(w *Worker) {
		w.objectStore = objectStore
	}
}

// WithBackoffPolicy sets the backoff policy for the Worker.
func WithBackoffPolicy(backoffPolicyFn retry.BackoffPolicyFn) Option {
	return func(w *Worker) {
		w.backoffPolicy = backoffPolicyFn
	}
}

// WithLogger sets the logger for the Worker.
func WithLogger(logger log.Logger) Option {
	return func(w *Worker) {
		w.logger = logger
	}
}

// WithStatter sets the statter for the Worker.
func WithStatter(statter stats.Client) Option {
	return func(w *Worker) {
		w.statter = statter
	}
}
