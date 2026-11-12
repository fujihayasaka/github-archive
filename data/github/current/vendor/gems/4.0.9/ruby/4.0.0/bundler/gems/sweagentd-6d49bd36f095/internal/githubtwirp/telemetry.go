package githubtwirp

// Metric names for repo memory opt-out telemetry.
// These metrics help track admin adoption and debug issues during staffship/rollout.
const (
	// MetricRepoMemoryOptOut is the base metric name for repo-level memory opt-out checks.
	// Tags: success (bool), disabled (bool when success=true)
	MetricRepoMemoryOptOut = "repo_memory_opt_out"
)
