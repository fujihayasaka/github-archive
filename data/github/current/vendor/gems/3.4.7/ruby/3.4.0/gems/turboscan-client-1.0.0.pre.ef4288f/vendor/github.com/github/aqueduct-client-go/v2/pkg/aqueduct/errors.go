package aqueduct

import "fmt"

// ErrorSource represents the source of a package error.
type ErrorSource string

const (
	ReceiveErrSource   = ErrorSource("receive")
	HeartbeatErrSource = ErrorSource("heartbeat")
	HandlerErrSource   = ErrorSource("job handler")
	AckErrSource       = ErrorSource("ack")
)

// WorkerError represents an error encountered by a Worker.
type WorkerError struct {
	Source ErrorSource
	Err    error
}

func (we *WorkerError) Error() string {
	return fmt.Sprintf("worker error from %s: %v", we.Source, we.Err)
}

func (we *WorkerError) Unwrap() error {
	return we.Err
}

// JobError represents an error encountered by a Worker when processing a Job.
type JobError struct {
	Source ErrorSource
	Result ReceiveResult
	Err    error
}

func (je *JobError) Error() string {
	return fmt.Sprintf("job %s/%s/%s error from %s: %v",
		je.Result.Job.App,
		je.Result.Job.Queue,
		je.Result.Job.ID,
		je.Source,
		je.Err,
	)
}

func (je *JobError) Unwrap() error {
	return je.Err
}
