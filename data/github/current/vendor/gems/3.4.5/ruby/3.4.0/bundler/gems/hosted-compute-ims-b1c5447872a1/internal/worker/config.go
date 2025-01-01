package worker

import (
	"time"

	"github.com/github/hosted-compute-ims/internal/worker/aqueduct"
)

// Config holds application configuration, including worker configs.
type Config struct {
	Aqueduct                 aqueduct.Config
	PoolSize                 int           `config:"15,env=WORKER_POOL_SIZE"`
	JobReceiveTimeout        time.Duration `config:"10s,env=WORKER_JOB_RECEIVE_TIMEOUT"`
	RetriesBaseBackoff       time.Duration `config:"10s,env=WORKER_RETRIES_BASE_BACKOFF"`
	RetriesExponentialFactor float64       `config:"2.0,env=WORKER_RETRIES_EXPONENTIAL_FACTOR"`
}
