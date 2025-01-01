package aqueduct

import (
	"context"
	"fmt"
	"time"

	"github.com/pkg/errors"

	aq "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/turboscan/ts"
)

// AqueductMock implements JobPerformer but only records submitted jobs locally
type AqueductMock struct {
	enqueuedJobs []EnqueableJob
}

var _ JobRetrier = (*AqueductMock)(nil)

func (a *AqueductMock) PerformLater(ctx context.Context, j EnqueableJob) (string, error) {
	jobId := fmt.Sprint(len(a.enqueuedJobs))
	a.enqueuedJobs = append(a.enqueuedJobs, j)
	return jobId, nil
}

func (a *AqueductMock) PerformLaterAt(ctx context.Context, j EnqueableJob, at time.Time) (string, error) {
	jobId := fmt.Sprint(len(a.enqueuedJobs))
	a.enqueuedJobs = append(a.enqueuedJobs, j)
	return jobId, nil
}

func (a *AqueductMock) RetryLater(ctx context.Context, j EnqueableJob, rc uint8) (string, error) {
	jobId := fmt.Sprint(len(a.enqueuedJobs))
	a.enqueuedJobs = append(a.enqueuedJobs, j)
	return jobId, nil
}

// EnqueuedJobs returns the list of jobs enqueued
func (a *AqueductMock) EnqueuedJobs() []EnqueableJob {
	return a.enqueuedJobs
}

// Reset resets the mock to its initial state, removing all historically enqueued jobs
func (a *AqueductMock) Reset() {
	a.enqueuedJobs = []EnqueableJob{}
}

type TestJob struct{}

func (j TestJob) Name() string {
	return "TestJob"
}
func (j TestJob) Queue() string {
	return "turboscan-test"
}
func (j TestJob) Perform(context.Context, *TSServices) error {
	return nil
}
func (j TestJob) GetRepositoryID() *ts.RepositoryEID {
	return nil
}

func (j TestJob) GetRetryBackoffFunc() RetryBackoffFunc {
	return DefaultRetryBackoffFunc
}

type TestErrorJob struct{}

func (j TestErrorJob) Name() string {
	return "TestErrorJob"
}
func (j TestErrorJob) Queue() string {
	return "turboscan-test-error"
}
func (j TestErrorJob) Perform(context.Context, *TSServices) error {
	return errors.New("empty err")
}

func (j TestErrorJob) GetRepositoryID() *ts.RepositoryEID {
	return nil
}

func (j TestErrorJob) GetRetryBackoffFunc() RetryBackoffFunc {
	return DefaultRetryBackoffFunc
}

type MockAqueductQueue struct {
	enqueuedJobs []aq.Job
}

func (a *MockAqueductQueue) Enqueue(_ context.Context, _ aq.Client, job aq.Job) (string, error) {
	jobId := fmt.Sprint(len(a.enqueuedJobs))
	a.enqueuedJobs = append(a.enqueuedJobs, job)
	return jobId, nil
}
