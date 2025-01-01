package metrickeys

// BuildState is the counter key for builds in various states
const BuildState = "build_state"

// BuildQueued is the state tag value when we have a success response from the provider's Run
const BuildQueued = "queued"

// BuildWorker is the state tag value when we know the build has started doing work
const BuildWorking = "working"

// BuildWorker is the state tag value when we know the build has finished
const BuildComplete = "complete"
