// Package workerpool provides a worker pool that knows how to run flows.
//
// # Synopsis
//
// Start 10 workers.
//
//	// Start all threads immediately.
//	workers := workerpool.NewSimple(logger, statter)
//	// Run a fixed number of workers.
//	workers := workerpool.NewPool(10, logger, statter)
//
// Start a job.
//
//	workers.Run(ctx, "jobname", func(context.Context) error { return nil })
//
// Stop accepting jobs and wait for pending jobs to complete.
//
//	workers.Stop()
//
// The worker pool reports errors from jobs with the provided logger
// The worker pool sends stats related to jobs processed, job queue size, etc.
package workerpool
