package retries

import (
	"time"
)

// Config represents the configuration of the retries middleware.
type Config struct {
	// AqueductApp is the name we use to identify ourselves against aqueduct.
	AqueductApp string `config:",env=AQUEDUCT_APP"`

	// RetriesMaxAttempts is the max number of times a message is requeued for retries. After that it
	// is marked as stale and discarded.
	MaxAttempts int32 `config:"5,env=RETRIES_MAX_ATTEMPTS"`

	// RetriesBaseBackoff is the base amount of time that is used as backoff period for a retry.
	BaseBackoff time.Duration `config:"5s,env=RETRIES_BASE_BACKOFF"`

	// RetriesExponentialFactor tells how much the wait between retries grows.
	ExponentialFactor float64 `config:"2.0,env=RETRIES_EXPONENTIAL_FACTOR"`

	// RetriesJitterFactor tells how big is the jitter applied to the retry time. The bigger the
	// factor, the bigger the jitter.
	JitterFactor float64 `config:"0.1,env=RETRIES_JITTER_FACTOR"`
}
