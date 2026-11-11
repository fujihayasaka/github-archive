package consumer

import (
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
)

// PoolName is the name of the worker pool.
type PoolName string

const (
	// APIPoolName is the name of the pool that processes API jobs.
	APIPoolName PoolName = "sweagentd-api-pool"

	// AgentPoolName is the name of the pool that processes agent jobs that were
	// queued for execution.
	AgentPoolName PoolName = "sweagentd-agent-pool"

	// EventPoolName is the name of the pool that processes hydro event jobs.
	EventPoolName PoolName = "sweagentd-event-pool"

	// StopAgentComputePoolName is the name of the pool that processes delayed
	// stop-agent-compute jobs.
	StopAgentComputePoolName PoolName = "sweagentd-stop-agent-compute-pool"
)

// PoolOption defines a function type that modifies the workerConfig configuration.
type PoolOption func(*workerConfig)

// WithWorkerCount sets the number of workers in the pool.
func WithWorkerCount(count int) PoolOption {
	return func(pool *workerConfig) {
		pool.workerCount = count
	}
}

// WithHeartbeatInterval sets the heartbeat interval for the workers.
func WithHeartbeatInterval(interval time.Duration) PoolOption {
	return func(pool *workerConfig) {
		pool.heartBeatInterval = interval
	}
}

// WithHeartbeatTimeout sets the heartbeat timeout for the workers.
func WithHeartbeatTimeout(timeout time.Duration) PoolOption {
	return func(pool *workerConfig) {
		pool.heartBeatTimeout = timeout
	}
}

// WithHandler sets the job handler for the worker pool.
func WithHandler(handler aqueduct.JobHandler) PoolOption {
	return func(pool *workerConfig) {
		pool.handler = handler
	}
}

// WithBeforeReceiveHook sets the before-receive hook for the worker pool.
func WithBeforeReceiveHook(hook aqueduct.BeforeReceiveHook) PoolOption {
	return func(pool *workerConfig) {
		pool.beforeReceiveHook = hook
	}
}

// WithQueues sets the queues for the worker pool.
func WithQueues(queues []string) PoolOption {
	return func(pool *workerConfig) {
		pool.queues = queues
	}
}

// WithPoolName sets the name of the worker pool.
func WithPoolName(name PoolName) PoolOption {
	return func(pool *workerConfig) {
		pool.poolName = string(name)
	}
}

// WithEnvironmentPoolName sets the name of the worker pool with the environment as a suffix.
func WithEnvironmentPoolName(env string, name PoolName) PoolOption {
	return func(pool *workerConfig) {
		pool.poolName = string(name) + "-" + env
	}
}

// WithErrorHook sets the error hook for the worker pool.
func WithErrorHook(hook aqueduct.ErrorHook) PoolOption {
	return func(pool *workerConfig) {
		pool.errorHook = hook
	}
}
