// Package store defines interfaces and errors for managing jobs, assignments,
// and commands in the database.
package store

import (
	"context"
	"errors"
	"time"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/jobs/experiments"
	"github.com/github/sweagentd/internal/jobs/progress"
	"github.com/github/sweagentd/internal/sweagentd"
)

// ErrMultipleAssignmentsForResource is returned when more than one active assignment
// is found for a specific resource, which should not happen under normal conditions.
var ErrMultipleAssignmentsForResource = errors.New("more than one active assignment found for resource")

// ErrPreconditionFailedOnUpdate is returned when an update operation fails because
// it attempted to update a stale version of the entity (optimistic concurrency control).
var ErrPreconditionFailedOnUpdate = errors.New("failed to update, attempted to update a stale version")

// ErrBatchPartitionKeysMismatch is returned when attempting a batch operation where
// all items do not share the same partition key, which is required for batch operations.
var ErrBatchPartitionKeysMismatch = errors.New("all items in a batch operation must share the same partition key")

// ErrBatchOperationFailed is returned when one or more operations in a batch
// operation fail to complete successfully.
var ErrBatchOperationFailed = errors.New("one or more operations in the batch failed")

// NewErrMultipleAssignmentsForResource returns ErrMultipleAssignmentsForResource with a stack trace.
func NewErrMultipleAssignmentsForResource() error {
	return goerrors.WithStackOffset(ErrMultipleAssignmentsForResource, 1)
}

// NewErrPreconditionFailedOnUpdate returns ErrPreconditionFailedOnUpdate with a stack trace.
func NewErrPreconditionFailedOnUpdate() error {
	return goerrors.WithStackOffset(ErrPreconditionFailedOnUpdate, 1)
}

// NewErrBatchPartitionKeysMismatch returns ErrBatchPartitionKeysMismatch with a stack trace.
func NewErrBatchPartitionKeysMismatch() error {
	return goerrors.WithStackOffset(ErrBatchPartitionKeysMismatch, 1)
}

// NewErrBatchOperationFailed returns ErrBatchOperationFailed with a stack trace.
func NewErrBatchOperationFailed() error {
	return goerrors.WithStackOffset(ErrBatchOperationFailed, 1)
}

// AssignmentPatch is a struct that can be used to patch specific fields on an
// assignment in the database. This is useful for updating one or two fields efficiently.
type AssignmentPatch struct {
	PullRequestID     *int64
	PullRequestNumber *int
	Experiments       *experiments.AssignmentExperiments
}

// AssignmentStore is the interface for managing Assignments in the database.
//
//nolint:interfacebloat // Temporary until we can split these out.
type AssignmentStore interface {
	CreateAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error)
	GetAssignment(ctx context.Context, owner, repo int64, id string) (*jobs.Assignment, error)
	GetAssignments(ctx context.Context, owner, repo int64) ([]*jobs.Assignment, error)
	UpdateAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error)
	UpsertAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error)

	// PatchAssignment patches specific fields on the assignment in the database.
	// This is useful for updating one or two fields efficiently.
	PatchAssignment(ctx context.Context, assignment *jobs.Assignment, patch AssignmentPatch) error
	DeleteAssignment(ctx context.Context, owner, repo int64, id string) error

	GetAssignmentForResource(ctx context.Context, owner, repo int64, resource jobs.AssignmentResource) (*jobs.Assignment, error)
	DetachAssignmentResource(ctx context.Context, assignment *jobs.Assignment, resource jobs.AssignmentResource) error
	DetachAssignmentResources(ctx context.Context, assignment *jobs.Assignment) error

	// GetAssignmentForPR returns the assignment for the pull request id and/or number.
	//
	// Note: As far as the GitHub API is concerned, every pull request is an issue, but not every issue
	// is a pull request. Some PR related webhooks (e.g. issue_comment) will use an issue field to
	// represent the PR. The issue id however does NOT match the id of the PR, but the numbers do.
	//
	// The database is partitioned hierarchically by owner -> repo -> assignments, so we can guarantee
	// both the pr id and number will be unique within the partition. There is no difference in cost/speed
	// of querying id vs. querying id and number.
	GetAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error)
}

// JobPatch is a struct that can be used to patch specific fields on a job in
// the database. This is useful for updating one or two fields efficiently.
type JobPatch struct {
	Status              *jobs.JobStatus
	ComputeID           *string
	CompletedAt         *int64
	StartedAt           *int64
	BranchName          *string
	PullRequestID       *int64
	PullRequestNumber   *int
	ReplyCommentID      *int64
	OnboardingCommentID *int64
	SessionID           *string
	QueuedAt            *int64
	Error               *jobs.JobError
	Experiments         *experiments.AssignmentExperiments
	Model               *string
	CustomAgent         *customagent.DBRecord
}

// JobsStore is the interface for managing Jobs in the database.
//
//nolint:interfacebloat // Temporary until we can split these out.
type JobsStore interface {
	// TODO (colbylwilliams):
	// Embedding AssignmentStore and CommandStore temporarily since all services
	// currently accept JobStore and expect the Assignment methods to be there.

	// HealthCheck verifies connectivity to the underlying database.
	// It returns nil if the connection is healthy, or an error if the connection fails.
	HealthCheck(ctx context.Context) error
	// Once we reduce the number of services that need the full JobStore interface,
	// we can separate these out (or better, delete them).
	AssignmentStore
	CommandStore
	ProgressStore

	GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error)
	GetJobForComputeID(ctx context.Context, owner, repo int64, computeID string) (*jobs.Job, error)
	GetJobForSessionID(ctx context.Context, owner, repo int64, sessionID string) (*jobs.Job, error)
	GetJobForActorOnboarding(ctx context.Context, owner, repo, actor int64) (*jobs.Job, error)
	ListJobsForPullRequestNumber(ctx context.Context, owner, repo int64, prNumber int) ([]*jobs.Job, error)

	GetJobSummariesForAssignmentID(ctx context.Context, owner, repo int64, assignmentID string) ([]*jobs.JobSummary, error)

	// GetRunningJobCountForActor retrieves the number of jobs for the actor with the "running" status
	// during the specified duration window.
	//
	// IMPORTANT: This is a potentially expensive operation. Consider the frequency of calls to this method
	// and the number of jobs per actor that may be returned. It queries the database for ALL of the actor's
	// jobs across ALL owners and repositories, and filters only by status.
	//
	// This method is intentionally constrained to the "running" status. Because we limit the number of
	// running jobs per actor, we can assume that the number of jobs returned by this method is relatively
	// small. Querying for most other statuses however (e.g. completed, failed, etc.) is likely to return
	// VERY large numbers of jobs, which would be expensive to query and process.
	//
	// This method should only be called in conjunction with a caching layer (e.g. the limiter) to avoid
	// unnecessary cost or performance hits.
	GetRunningJobCountForActor(ctx context.Context, actor int64, window time.Duration) (int, error)

	// GetJobCountByStatusForActor retrieves the number of jobs for the actor (currently) with the
	// "running" or "queued" status during the specified duration window.
	//
	// IMPORTANT: This is a potentially expensive operation. Consider the frequency of calls to this
	// method and the number of jobs per actor that may be returned. It queries the database for ALL
	// of the actor's jobs across ALL owners and repositories, and filters only by status.
	//
	// This method is intentionally constrained to only the "running" and "queued" status. Because
	// we limit the number of running and queued jobs per actor, we can assume that the number of
	// jobs returned by this method is relatively small. Querying for most other statuses however
	// (e.g. completed, failed, etc.) is likely to return VERY large numbers of jobs, which would
	// be too expensive to query and process.
	//
	// Additionally, the window parameter should be set to a reasonable duration to limit the number
	// of jobs returned. This should typically be set to no more than 24 hours. Setting this to a
	// very large duration (e.g. several days or weeks) may result in a very large number of jobs
	// being returned, which would be expensive to query and process.
	//
	// This method should only be called in conjunction with a caching layer (e.g. the limiter) to
	// avoid unnecessary cost or performance hits.
	GetJobCountByStatusForActor(ctx context.Context, actor int64, window time.Duration) (sweagentd.JobCounts, error)

	CreateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error)
	GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error)
	GetJobs(ctx context.Context, owner, repo int64) ([]*jobs.Job, error)
	UpdateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error)
	UpsertJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error)

	// PatchJob patches specific fields on the job in the database.
	// This is useful for updating one or two fields efficiently.
	PatchJob(ctx context.Context, job *jobs.Job, patch JobPatch, opts ...PatchJobOption) error
	DeleteJob(ctx context.Context, owner, repo int64, id string) error
}

// CommandPatch is a struct that can be used to patch specific fields on a command
// in the database. This is useful for updating one or two fields efficiently.
type CommandPatch struct {
	Status      *command.Status
	DeliveredAt *int64
}

// CommandStore is the interface for managing commands in the database.
type CommandStore interface {
	CreateCommand(ctx context.Context, cmd *command.Command) (*command.Command, error)
	GetCommand(ctx context.Context, assignmentID, jobID string, id string) (*command.Command, error)
	GetCommands(ctx context.Context, assignmentID, jobID string) ([]*command.Command, error)
	GetCommandsWithStatus(ctx context.Context, assignmentID, jobID string, status command.Status) ([]*command.Command, error)
	UpdateCommand(ctx context.Context, cmd *command.Command) (*command.Command, error)
	PatchCommand(ctx context.Context, cmd *command.Command, patch CommandPatch) error
	BatchPatchCommands(ctx context.Context, cmd []*command.Command, patch CommandPatch) error
}

// ProgressStore is the interface for managing progress updates in the database.
type ProgressStore interface {
	CreateProgress(ctx context.Context, progress *progress.Progress) (*progress.Progress, error)
	GetProgress(ctx context.Context, assignmentID, jobID, id string) (*progress.Progress, error)
	BatchCreateProgress(ctx context.Context, progresses []*progress.Progress) ([]*progress.Progress, error)
	ListProgress(ctx context.Context, assignmentID, jobID string) ([]*progress.Progress, error)
	ListProgressByNamespace(ctx context.Context, assignmentID, jobID string, namespaces []string) ([]*progress.Progress, error)
}

// PatchJobOption adds an option that can be applied when patching a job.
type PatchJobOption func(opt *PatchJobOptionsAccumulator)

// WithDisableEtagCheck is an option to disregard the etag consistancy check when patching a job.
func WithDisableEtagCheck() PatchJobOption {
	return func(opt *PatchJobOptionsAccumulator) {
		opt.DisableEtagCheck = true
	}
}

// PatchJobOptionsAccumulator is where all the options end up.  This is exported
// because both subpackages need it, but consumers of this package shouldn't use this.
type PatchJobOptionsAccumulator struct {
	DisableEtagCheck bool
}
