package queues

// QueueWorkerType determines which queues a queue-worker will process.
type QueueWorkerType string

const (
	UnknownWorkerType          QueueWorkerType = ""                  // UnknownWorkerType is the default value
	WorkerTypeLowPriority      QueueWorkerType = "low-priority"      // WorkerTypeLowPriority is the low-priority queue worker type
	WorkerTypeStandardPriority QueueWorkerType = "standard-priority" // WorkerTypeStandardPriority is the standard-priority queue worker type
)

// String returns the string value of the QueueWorkerType
func (wt QueueWorkerType) String() string {
	return string(wt)
}
