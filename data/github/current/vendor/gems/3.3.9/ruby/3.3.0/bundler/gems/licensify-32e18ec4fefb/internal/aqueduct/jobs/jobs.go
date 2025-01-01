// Package jobs contains the names of the jobs the aqueduct workers can process.
package jobs

import (
	"context"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/licensify/internal/config"
)

const (
	// JobNameHeader is the header key for the job name so that we can determine which job processor to use.
	JobNameHeader = "job-name"
	// JobNameProductEnablementUpdated is the header value for the ProductEnablementUpdated job processor.
	JobNameProductEnablementUpdated = "product-enablement-updated"
	// JobNameSyncOrgMemberships is the header value for the SyncOrgMemberships job processor.
	JobNameSyncOrgMemberships = "sync-org-memberships"
	// JobNameDeleteOrgMemberships is the header value for the DeleteOrgMemberships job processor.
	JobNameDeleteOrgMemberships = "delete-org-memberships"
	// JobNameDeleteEnablements is the header value for the DeleteEnablements job processor.
	JobNameDeleteEnablements = "delete-enablements"
	// JobNameCreateRepositoryCollaborators is the header value for the CreateRepositoryCollaborators job processor.
	JobNameCreateRepositoryCollaborators = "create-repository-collaborators"
	// JobNameScheduleEmissions is the header value for the ScheduleEmissions job processor.
	JobNameScheduleEmissions = "schedule-emissions"
	// JobNamePublishEmission is the header value for the PublishEmission job processor.
	JobNamePublishEmission = "publish-emission"
	// JobNameBackfillLicenseStatus is the header value for the BackfillLicenseStatus job processor.
	JobNameBackfillLicenseStatus = "backfill-license-status"
)

// JobProcessor is an interface for processing aqueduct messages.
type JobProcessor interface {
	ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error
}

// Jobby is a struct used to centeralize some job sending logic
type Jobby struct {
	Cfg            *config.Config
	AqueductClient aqueduct.Client
}

// NewJob returns an aqueduct job configured with the provided queue and default headers.
func (j Jobby) NewJob(jobName, queue string, payload []byte) aqueduct.Job {
	headers := make(map[string]string)
	headers[JobNameHeader] = jobName
	return aqueduct.Job{
		App:     j.Cfg.AqueductApp,
		Queue:   queue,
		Payload: payload,
		Headers: headers,
	}
}

// Enqueue sends a job through aqueduct applying some default settings we want to use for all jobs.
func (j Jobby) Enqueue(ctx context.Context, jobName, queue string, payload []byte) (string, error) {
	aqueductJob := j.NewJob(jobName, queue, payload)

	return j.AqueductClient.Send(
		ctx,
		aqueductJob,
		DefaultSendOptions()...,
	)
}

// EnqueueBatch sends a batch of jobs through aqueduct applying some default settings we want to use for all jobs.
func (j Jobby) EnqueueBatch(ctx context.Context, jobName, queue string, payloads [][]byte) (*aqueduct.SendBatchResult, error) {
	batch := make([]aqueduct.BatchItem, len(payloads))

	for i, payload := range payloads {
		batch[i] = aqueduct.BatchItem{
			Job:  j.NewJob(jobName, queue, payload),
			Opts: DefaultSendOptions(),
		}
	}

	return j.AqueductClient.SendBatch(ctx, batch)
}

// DefaultSendOptions returns default aqueduct send options that we want to use for all jobs.
func DefaultSendOptions() []aqueduct.SendOption {
	return []aqueduct.SendOption{
		aqueduct.WithJobRedeliveryTimeoutSeconds(20), // Our heartbeat is 5 seconds (see internal/aqueduct/worker.go), so add a little buffer and consider a job timed out/failed if it hasn't been heartbeated or acked in 20 seconds // default value is 10 minutes
		aqueduct.WithJobMaxRedeliveryAttempts(4),     // 5 total possible attempts (1 initial attempt + 4 redeliveries) // default value is 2
	}
}
